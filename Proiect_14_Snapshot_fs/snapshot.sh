#!/bin/bash

SNAPSHOT_DIR="$HOME/snapshots"
EXCLUDE_PATHS=("$SNAPSHOT_DIR")
WORKING_DIR="$HOME/so"

function create_snapshot() {
    local snapshot_name
    read -p "Enter the snapshot name: " snapshot_name

    local timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    local current_timestamp_epoch=$(date +%s)
    local snapshot_path_dir="${SNAPSHOT_DIR}/${snapshot_name}__${timestamp}"
    local snapshot_path="${snapshot_path_dir}/${snapshot_name}__${timestamp}.snapshot"

    mkdir -p "$snapshot_path_dir"

    # exclude paths
    local exclude_args=()
    for exclude in "${EXCLUDE_PATHS[@]}"
    do
        exclude_args+=("-path $exclude -prune -o")
    done
    local exclude_str="${exclude_args[*]}"

    nr_of_snapshots=$(sudo find "$SNAPSHOT_DIR" -maxdepth 1 -not -path '*/.*' | wc -l | cut -f1 -d' ')

    sudo find "$WORKING_DIR" $exclude_str -xdev -type f > "$snapshot_path" 2>/dev/null

    if [[ "$nr_of_snapshots" = '2' ]]     # first_snapshot
    then
        full_backup_dir="${snapshot_path_dir}/full_backup"
        mkdir -p "$full_backup_dir"
        rsync -a "$WORKING_DIR" "$full_backup_dir"
    else
        current_snapshot="${snapshot_path}"
        previous_snapshot_dir_path=$(find "${SNAPSHOT_DIR}" -maxdepth 1 -type d -exec stat -c '%W %n' {} + | sort -n | tail -n 2 | head -n 1 |cut -f2 -d' ')
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
            filename=$(basename "$created_file")
            cp "$created_file" "${created_files_dir}/${filename}"
        done < "${snapshot_path_dir}/created_temp"

        rm "${snapshot_path_dir}/created_temp"

        # deleted_files

        comm -23 "$previous_snapshot" "$current_snapshot" > "$deleted_files_file_path"

        # modified_files

        mkdir -p "$modified_files_dir"

        # to do : remove created_files from entire list
        echo "Modified"
        while read file_path
        do
            check_for_modified_file "$previous_snapshot" "$file_path" "no"
            local result=$(echo $?)
            if [[ $result = '1' ]]
            then
                echo "$file_path"
                file=$(basename "$file_path")
                cp "$file_path" "${modified_files_dir}/${file}"
            fi

        done < "$current_snapshot"
    fi

    echo "Snapshot created: $snapshot_path"
    echo
}

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

compare_snapshots() {
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

    touch "$SNAPSHOT_DIR/temp1"
    touch "$SNAPSHOT_DIR/temp2"

    cat $snapshot1 | egrep "^$specific_path" > "$SNAPSHOT_DIR/temp1"
    cat $snapshot2 | egrep "^$specific_path" > "$SNAPSHOT_DIR/temp2"
 
    compare_snapshots "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"

    rm "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"
}

function compare_snapshots_remove_path() {
    local snapshot1="$1"
    local snapshot2="$2"
    local path_to_delete="$3"

    touch "$SNAPSHOT_DIR/temp1"
    touch "$SNAPSHOT_DIR/temp2"

    sed "\#${path_to_delete}#d" $snapshot1 > "$SNAPSHOT_DIR/temp1"
    sed "\#${path_to_delete}#d" $snapshot2 > "$SNAPSHOT_DIR/temp2"

    compare_snapshots "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"

    rm "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"
}

function check_for_modified_files() {
    local snapshot="$SNAPSHOT_DIR/$1"

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
            echo
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

options=("Create snapshot" "Compare snapshots" "Check if the files has been modified" "Exit")
PS3="Choose an option from the menu: " 
select opt in "${options[@]}"
do
	case $REPLY in
        1)
            create_snapshot
            ;;
        2)
            read -p "Enter the name of the first snapshot: " snapshot1
            read -p "Enter the name of the second snapshot: " snapshot2

            read -p "Do you want to verify for a specific path? (y/n): " specific_response
            if [[ "$specific_response" = 'y' ]]
            then
                read -p "Enter the path: " specific_path
                compare_snapshots_specify_path "$SNAPSHOT_DIR/$snapshot1" "$SNAPSHOT_DIR/$snapshot2" "$specific_path"
            else
                read -p "Do you want to remove a path from verifying? (y/n): " remove_response
                if [[ "$remove_response" = 'y' ]]
                then
                    read -p "Enter the path to remove: " path_to_delete
                    compare_snapshots_remove_path "$SNAPSHOT_DIR/$snapshot1" "$SNAPSHOT_DIR/$snapshot2" "$path_to_delete"
                else
                    compare_snapshots "$SNAPSHOT_DIR/$snapshot1" "$SNAPSHOT_DIR/$snapshot2"
                fi
            fi
            ;;
        3)
            read -p "Specify the snapshot to check: " snapshot_files_check
            read -p "Do you want to check for a specific file? (y/n): " file_response
            if [[ "$file_response" = 'y' ]]
            then
                read -p "Enter the path to the file: " file_path
                check_for_modified_file "$SNAPSHOT_DIR/$snapshot_files_check" "$file_path" "only_one"
            else
                check_for_modified_files "$snapshot_files_check"
            fi
            ;;
        4)
			echo -e "\n==EXIT==\n"
			exit
			;;
    esac
done