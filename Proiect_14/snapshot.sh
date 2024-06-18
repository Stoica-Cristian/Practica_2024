#!/bin/bash

SNAPSHOT_DIR="$HOME/snapshots"
EXCLUDE_PATHS=("$SNAPSHOT_DIR")

function create_snapshot() {
    local snapshot_name
    read -p "Enter the snapshot name: " snapshot_name

    local timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}__${timestamp}.snapshot"

    mkdir -p "$SNAPSHOT_DIR"
    local exclude_args=()
    for exclude in "${EXCLUDE_PATHS[@]}"
    do
        exclude_args+=("-path $exclude -prune -o")
    done

    local exclude_str="${exclude_args[*]}"

    sudo find / $exclude_str -xdev -type f -print > "$snapshot_path" 2>/dev/null

    echo "Snapshot created: $snapshot_path"
}

function add_exclude_path() {
    local path_to_add="$1"

    for path in "${EXCLUDE_PATHS[@]}"; do
        if [[ "$path" == "$path_to_add" ]]; then
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

    echo "Files created:"
    comm -13 "$snapshot1" "$snapshot2"

    echo "Deleted files:"
    comm -23 "$snapshot1" "$snapshot2"
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

    sed -E '\#($path_to_delete)#d' $snapshot1 > "$SNAPSHOT_DIR/temp1"
    sed -E '\#($path_to_delete)#d' $snapshot2 > "$SNAPSHOT_DIR/temp2"
 
    compare_snapshots "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"

    # rm "$SNAPSHOT_DIR/temp1" "$SNAPSHOT_DIR/temp2"
}


options=("Create snapshot" "Compare snapshots" "Exit")
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
                read -p "Do you want to remove a path from verifying? (y/n): " response
                if [[ "$response" = 'y' ]]
                then
                    read -p "Enter the path to remove: " path_to_delete
                    echo "$path_to_delete"
                    compare_snapshots_remove_path "$SNAPSHOT_DIR/$snapshot1" "$SNAPSHOT_DIR/$snapshot2" "$path_to_delete"
                else
                    compare_snapshots "$SNAPSHOT_DIR/$snapshot1" "$SNAPSHOT_DIR/$snapshot2"
                fi
            fi
            ;;
        3)
			echo "==EXIT=="
			exit
			;;
    esac
done

    # read -p "Enter the path to exclude: " exclude_path
    # add_exclude_path "$exclude_path"
