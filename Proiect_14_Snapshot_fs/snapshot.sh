#!/bin/bash

SNAPSHOTS_DIR="$HOME/snapshots"
EXCLUDE_PATHS=("$SNAPSHOTS_DIR")
WORKING_DIR="/home/stoica/so"
SNAPSHOT_LIST=()

function create_snapshot() {
    local snapshot_name
    read -p "Enter the snapshot name: " snapshot_name

    local timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    local current_timestamp_epoch=$(date +%s)
    local snapshot_path_dir="${SNAPSHOTS_DIR}/${snapshot_name}__${timestamp}"
    local snapshot_path="${snapshot_path_dir}/${snapshot_name}__${timestamp}.snapshot"

    mkdir -p "$snapshot_path_dir"

    # exclude paths
    local exclude_args=()
    for exclude in "${EXCLUDE_PATHS[@]}"
    do
        exclude_args+=("-path $exclude -prune -o")
    done
    local exclude_str="${exclude_args[*]}"

    nr_of_snapshots=$(sudo find "$SNAPSHOTS_DIR" -maxdepth 1 -not -path '*/.*' | wc -l | cut -f1 -d' ')

    sudo find "$WORKING_DIR" $exclude_str -xdev -type f > "$snapshot_path" 2>/dev/null

    if [[ "$nr_of_snapshots" = '2' ]]     # first_snapshot
    then
        full_backup_dir="${snapshot_path_dir}/full_backup"
        mkdir -p "$full_backup_dir"
        rsync -aRq "$WORKING_DIR" "$full_backup_dir"
    else
        current_snapshot="${snapshot_path}"
        previous_snapshot_dir_path=$(find "${SNAPSHOTS_DIR}" -maxdepth 1 -type d -exec stat -c '%W %n' {} + | sort -n | tail -n 2 | head -n 1 |cut -f2 -d' ')
        previous_snapshot_dir_basename=$(basename "$previous_snapshot_dir_path")
        previous_snapshot="${previous_snapshot_dir_path}/${previous_snapshot_dir_basename}.snapshot"

        created_files_dir="${snapshot_path_dir}/created_files"
        modified_files_dir="${snapshot_path_dir}/modified_files"
        deleted_files_file_path="${snapshot_path_dir}/deleted_files"

        # created_files
        sort -o $previous_snapshot $previous_snapshot
        sort -o $current_snapshot $current_snapshot

        comm -13 "$previous_snapshot" "$current_snapshot" > "${snapshot_path_dir}/created_temp"

        mkdir -p "$created_files_dir"

        while read created_file
        do
            rsync -aRq "$created_file" "$created_files_dir"
        done < "${snapshot_path_dir}/created_temp"

        # deleted_files

        comm -23 "$previous_snapshot" "$current_snapshot" > "$deleted_files_file_path"

        # modified_files

        mkdir -p "$modified_files_dir"

        sort -o "${snapshot_path_dir}/created_temp" "${snapshot_path_dir}/created_temp"
        sort -o "$current_snapshot" "$current_snapshot"

        while read modified_file
        do
            check_for_modified_file "$previous_snapshot" "$modified_file" "no"
            local result=$(echo $?)
            if [[ $result = '1' ]]
            then
                rsync -aRq "$modified_file" "$modified_files_dir"
            fi

        done < <(comm -23 "$current_snapshot" "${snapshot_path_dir}/created_temp")
        
        rm "${snapshot_path_dir}/created_temp"
    fi


    echo "Snapshot created: $snapshot_path"
    echo
}

# diff -r so so_full_backup/so/ | cut -f3,4 -d' ' | sed 's#: #/#g'

function apend_to_excluded_paths() {
    local path_to_add="$1"

    if [ ! -e "$path_to_add" ]
    then
        echo "[ apend_to_excluded_paths(path_to_add) ] - The path does not exist!"
    fi

    for path in "${EXCLUDE_PATHS[@]}"; do
        if [[ "$path" == "$path_to_add" ]]
        then
            echo "The path $path_to_add is already in EXCLUDE_PATHS."
            return 1
        fi
    done

    EXCLUDE_PATHS+=("$path_to_add")
    echo "The path $path_to_add has been successfully added in EXCLUDE_PATHS."
}

function compare_snapshots() {
    local snapshot1="$1"
    local snapshot2="$2"

    sort -o $snapshot1 $snapshot1
    sort -o $snapshot2 $snapshot2

    echo -e "\nFiles created:"
    comm -13 "$snapshot1" "$snapshot2"

    echo -e "\nDeleted files:"
    comm -23 "$snapshot1" "$snapshot2"
    echo
}

function compare_snapshots_specify_path() {
    local snapshot1="$1"
    local snapshot2="$2"
    local specific_path="$3"

    local snapshot1_dir=$(dirname "$snapshot1")
    local snapshot2_dir=$(dirname "$snapshot2")

    cat $snapshot1 | egrep "^$specific_path" > "$snapshot1_dir/temp1"
    cat $snapshot2 | egrep "^$specific_path" > "$snapshot2_dir/temp2"
 
    compare_snapshots "$snapshot1_dir/temp1" "$snapshot2_dir/temp2"

    rm "$SNAPSHOTS_DIR/temp1" "$SNAPSHOTS_DIR/temp2"
}

function compare_snapshots_remove_path() {
    local snapshot1="$1"
    local snapshot2="$2"
    local path_to_delete="$3"

    local snapshot1_dir=$(dirname "$snapshot1")
    local snapshot2_dir=$(dirname "$snapshot2")

    sed "\#${path_to_delete}#d" $snapshot1 > "$snapshot1_dir/temp1"
    sed "\#${path_to_delete}#d" $snapshot2 > "$snapshot2_dir/temp2"

    compare_snapshots "$snapshot1_dir/temp1" "$snapshot1_dir/temp2"

    rm "$SNAPSHOTS_DIR/temp1" "$SNAPSHOTS_DIR/temp2"
}

function check_for_modified_files() {
    local snapshot="$SNAPSHOTS_DIR/$1"

    echo
    while read file_path
    do
        if [[ ! -f $file_path ]]
        then
            continue
        fi

        check_for_modified_file "$snapshot" "$file_path" "no"
        local result=$(echo $?)

        local filename=$(basename "$file_path")
        local file_modification_date=$(stat -c %y $file_path | cut -d'.' -f1)

        if [[ $result = '0' ]]
        then
            # echo "The file $filename has not been modified."
            echo -n
        elif [[ $result = '1' ]]
        then
            echo -e "\e[31mThe file $filename has been modified on ${file_modification_date}\e[0m"
        fi

    done < $snapshot
    echo
}

function check_for_modified_file(){
    local snapshot="$1"
    local file_path="$2"
    local only_one="$3"

    if [ ! -f "$file_path" ]
    then
        echo "[ check_for_modified_file(snapshot, file_path, only_one) ] - The file does not exist!"
        exit 1
    fi

    local file_modification_date=$(stat -c %y $file_path)
    local file_modification_epoch=$(date -d "$file_modification_date" +%s)
    local snapshot_creation_time_epoch=$(stat -c %W "$snapshot")

    if [ "$only_one" = "only_one" ]
    then
        if [[ "$file_modification_epoch" -lt "$snapshot_creation_time_epoch" ]]
        then
            echo "The file has not been modified."
        else
            echo "The file has been modified."
        fi
    else
        if [[ "$file_modification_epoch" -lt "$snapshot_creation_time_epoch" ]]
        then
            return 0
        else
            return 1
        fi
    fi
}

function display_differences_for_a_modified_file()
{
    local snapshot1="$1"
    local snapshot2="$2"
    local file_path="$3"

    local snapshot1_dir=$(dirname "$snapshot1")
    local snapshot2_dir=$(dirname "$snapshot2")

    local file_path_modified_dir1="${snapshot1_dir}/modified_files${file_path}"
    local file_path_modified_dir2="${snapshot2_dir}/modified_files${file_path}"
    local file_path_created_dir1="${snapshot1_dir}/created_files${file_path}"
    local file_path_created_dir2="${snapshot2_dir}/created_files${file_path}"

    local first_snapshot=${SNAPSHOT_LIST[-1]}

    if [[ "$snapshot1" = "$first_snapshot" && -f "$file_path_modified_dir2" ]]
    then
        local file_path_full_backup="${snapshot1_dir}/full_backup${file_path}"
        echo -e "\nDiferentele dintre cele doua versiuni ale fisierului sunt:\n"
        diff -y "$file_path_full_backup" "$file_path_modified_dir2"
        echo
        return
    fi

    if [[ "$snapshot2" = "$first_snapshot" && -f "$file_path_modified_dir1" ]]
    then
        local file_path_full_backup="${snapshot2_dir}/full_backup${file_path}"
        echo -e "\nDiferentele dintre cele doua versiuni ale fisierului sunt:\n"
        diff -y "$file_path_full_backup" "$file_path_modified_dir1"
        echo
        return
    fi

    # if the file exist localy in both snapshots

    creation_time_snapshot1=$(stat -c %W "$snapshot1")
    creation_time_snapshot2=$(stat -c %W "$snapshot2")

    local most_recent_snapshot=""
    local least_recent_snapshot=""

    if [[ "$creation_time_snapshot1" -gt "$creation_time_snapshot2" ]]
    then
        most_recent_snapshot="$snapshot1"
        least_recent_snapshot="$snapshot2"
    else
        most_recent_snapshot="$snapshot2"
        least_recent_snapshot="$snapshot1"
    fi


    local snapshot_mrs_dir=$(dirname "$snapshot1")
    local snapshot_lrs_dir=$(dirname "$snapshot2")

    local file_path_modified_dir_mrs="${snapshot_mrs_dir}/modified_files${file_path}"
    local file_path_modified_dir_lrs="${snapshot_lrs_dir}/modified_files${file_path}"
    local file_path_created_dir_lrs="${snapshot_lrs_dir}/created_files${file_path}"

    # already exist; modified and modified
    if [[ -f "$file_path_modified_dir_lrs" && -f "$file_path_modified_dir_mrs" ]]
    then
        echo -e "\nDiferentele dintre cele doua versiuni ale fisierului sunt:\n"
        diff -y "$file_path_modified_dir_lrs" "$file_path_modified_dir_mrs"
        echo
        return
    fi

    # exists in created_files in least recent snapshot and then modified in the other
    if [[ -f "$file_path_created_dir_lrs" && -f "$file_path_modified_dir_mrs" ]]
    then
        echo -e "\nDiferentele dintre cele doua versiuni ale fisierului sunt:\n"
        diff -y "$file_path_created_dir_lrs" "$file_path_modified_dir_mrs"
        echo
        return
    fi

    # if the file does not exist localy in both snapshots

    local actual_mrs_snapshot=""
    local actual_lrs_snapshot=""

    for snapshot_mrs in "${SNAPSHOT_LIST[@]}"
    do
        if [[ "$snapshot_mrs" != "$most_recent_snapshot" ]]
        then
            continue
        fi

        if [[ "$snapshot_mrs" = "$least_recent_snapshot" ]]
        then
            # to do: verificare actual_mrs_snapshot gol; fisierul nu a fost modificat

            if [[ -z "$actual_mrs_snapshot" ]]
            then
                echo -e "\nThe file was not modified between the two snapshots!\n"
                return
            fi
            break
        fi

        local current_snapshot_dir=$(dirname "$snapshot_mrs")
        local file_path_modified_dir_current_snap="${current_snapshot_dir}/modified_files${file_path}"

        if [[ -f "$file_path_modified_dir_current_snap" ]]
        then
            actual_mrs_snapshot="$snapshot_mrs"
            break
        fi
    done

    local in_created="false"
    for snapshot_lrs in "${SNAPSHOT_LIST[@]}"
    do
        if [[ "$snapshot_lrs" != "$least_recent_snapshot" ]]
        then
            continue
        fi

        if [[ "$snapshot_lrs" = "$first_snapshot" ]]
        then
            break
        fi

        local current_snapshot_dir=$(dirname "$snapshot_lrs")
        local file_path_modified_dir_current_snap="${current_snapshot_dir}/modified_files${file_path}"
        local file_path_created_dir_current_snap="${current_snapshot_dir}/created_files${file_path}"

        if [[ -f "$file_path_modified_dir_current_snap" ]]
        then
            actual_lrs_snapshot="$snapshot_lrs"
            break
        fi

        if [[ -f "$file_path_created_dir_current_snap" ]]
        then
            in_created="true"
            actual_lrs_snapshot="$snapshot_lrs"
            break
        fi
    done

    # to do: verificare actual_lrs_snapshot gol; fisierul nu a fost modificat

    if [[ -z "$actual_mrs_snapshot" ]]
    then
        echo -e "\nThe file was not modified after the creation of the first snapshot!"
        read -p "You want to display its content? (y/n)" response_display_diff
        if [[ "$response_display_diff" = 'y' ]]
        then
            first_snapshot_dir=$(dirname "$first_snapshot")
            echo
            cat "${first_snapshot_dir}/full_backup${file_path}"
        fi
        return
    fi

    local mrs_snapshot_dir=$(dirname "$actual_mrs_snapshot")
    local lrs_snapshot_dir=$(dirname "$actual_lrs_snapshot")

    echo -e "\nDiferentele dintre cele doua versiuni ale fisierului sunt:\n"
    if [[ "$in_created" = "true" ]]
    then
        diff -y "${lrs_snapshot_dir}/modified_files${file_path}" "${mrs_snapshot_dir}/modified_files${file_path}"
    else
        diff -y "${lrs_snapshot_dir}/created_files${file_path}" "${mrs_snapshot_dir}/modified_files${file_path}"
    fi
    echo
}

function initialize_snapshot_list(){
    SNAPSHOT_LIST=($(ls -t "$SNAPSHOTS_DIR" | sed -E 's#^(.*)#\1/\1.snapshot#' | sed "s#^#${SNAPSHOTS_DIR}/#g"))
}


initialize_snapshot_list

options=("Create snapshot" "Compare snapshots" "Check if the files has been modified" "Show the differences between two modified files" "Exit")
PS3="Choose an option from the menu: " 
select opt in "${options[@]}"
do
	case $REPLY in
        1)
            create_snapshot
            ;;
        2)
            echo
            read -p "Enter the name of the first snapshot: " snapshot1
            read -p "Enter the name of the second snapshot: " snapshot2

            read -p "Do you want to verify for a specific path? (y/n): " specific_response
            if [[ "$specific_response" = 'y' ]]
            then
                read -p "Enter the path: " specific_path
                compare_snapshots_specify_path "$SNAPSHOTS_DIR/$snapshot1/${snapshot1}.snapshot" "$SNAPSHOTS_DIR/$snapshot2/${snapshot2}.snapshot" "$specific_path"
            else
                read -p "Do you want to remove a path from verifying? (y/n): " remove_response
                if [[ "$remove_response" = 'y' ]]
                then
                    read -p "Enter the path to remove: " path_to_delete
                    compare_snapshots_remove_path "$SNAPSHOTS_DIR/$snapshot1/${snapshot1}.snapshot" "$SNAPSHOTS_DIR/$snapshot2/${snapshot2}.snapshot" "$path_to_delete"
                else
                    compare_snapshots "$SNAPSHOTS_DIR/$snapshot1/${snapshot1}.snapshot" "$SNAPSHOTS_DIR/$snapshot2/${snapshot2}.snapshot"
                fi
            fi
            ;;
        3)
            echo
            read -p "Specify the snapshot to check: " snapshot_files_check
            read -p "Do you want to check for a specific file? (y/n): " file_response
            if [[ "$file_response" = 'y' ]]
            then
                read -p "Enter the path to the file: " file_path
                check_for_modified_file "$SNAPSHOTS_DIR/$snapshot_files_check/${snapshot_files_check}.snapshot" "$file_path" "only_one"
            else
                check_for_modified_files "$snapshot_files_check/${snapshot_files_check}.snapshot"
            fi
            ;;
        4)
            echo
            read -p "Specify the file: " modified_file_check
            read -p "Enter the name of the first snapshot: " snapshot1_display_diff
            read -p "Enter the name of the second snapshot: " snapshot2_display_diff

            display_differences_for_a_modified_file "$SNAPSHOTS_DIR/$snapshot1_display_diff/${snapshot1_display_diff}.snapshot" "$SNAPSHOTS_DIR/$snapshot2_display_diff/${snapshot2_display_diff}.snapshot" "$modified_file_check"
            ;;
        5)
			echo -e "\n==EXIT==\n"
			exit
			;;
    esac
done