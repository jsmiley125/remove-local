#!/bin/bash

# remove-local: Evict local iCloud copies while retaining cloud availability.
# Usage:
#   To evict one file/folder: ./remove-local.sh <file_or_folder_path>
#   To evict from a CSV list: ./remove-local.sh --csv <csv_file_path>
#
# Example CSV file (one file/folder path per line):
# /path/to/file1
# /path/to/folder1

# Function to evict a single file using brctl
evict_file() {
    local file="$1"
    # Optionally, you can comment out the following echo to reduce output.
    # echo "Evicting local copy: $file"
    brctl evict "$file"
}

# Usage message function.
usage() {
    echo "Usage:"
    echo "    $0 <file_or_folder_path>"
    echo "    $0 --csv <csv_file_path>"
    exit 1
}

# Make sure at least one parameter is provided.
if [ "$#" -lt 1 ]; then
    usage
fi

# Function to process a given directory: build an array of files and process them.
process_directory() {
    local dir="$1"
    files=()
    # Build an array of all files found in the directory
    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$dir" -type f)
    total_files=${#files[@]}
    count=0
    start_time=$(date +%s)
    for file in "${files[@]}"; do
        count=$((count + 1))
        evict_file "$file"
        elapsed=$(($(date +%s) - start_time))
        # Calculate average time per file, remaining files and percentage.
        if [ "$count" -gt 0 ]; then
            avg_time=$(echo "scale=2; $elapsed / $count" | bc)
            remaining=$(echo "scale=2; $avg_time * ($total_files - $count)" | bc)
            percent=$(echo "scale=2; 100 * $count / $total_files" | bc)
        else
            avg_time=0
            remaining=0
            percent=0
        fi
        # Print the progress on the same line.
        echo -ne "Progress for $dir: $count/$total_files files evicted, $percent% complete - Estimated time remaining: ${remaining} sec\r"
    done
    echo ""
}

# Check if CSV mode is indicated.
if [ "$1" == "--csv" ] || [ "$1" == "-csv" ]; then
    if [ -z "$2" ]; then
        usage
    fi
    CSV="$2"
    if [ ! -f "$CSV" ]; then
        echo "Error: CSV file '$CSV' does not exist."
        exit 1
    fi

    echo "Processing CSV file: $CSV"
    # Read the CSV file: assume one path per line or comma-separated.
    while IFS=, read -r path || [ -n "$path" ]; do
        # Trim any leading/trailing whitespace.
        path=$(echo "$path" | sed 's/^[ \t]*//;s/[ \t]*$//')
        # Skip empty lines.
        if [ -z "$path" ]; then
            continue
        fi
        echo "Processing: $path"
        if [ -d "$path" ]; then
            process_directory "$path"
        elif [ -f "$path" ]; then
            evict_file "$path"
        else
            echo "Warning: Path '$path' does not exist. Skipping."
        fi
    done < "$CSV"
    exit 0
fi

# If CSV mode is not used, treat the first parameter as a file or folder.
TARGET="$1"

if [ ! -e "$TARGET" ]; then
    echo "Error: The specified path '$TARGET' does not exist."
    exit 1
fi

if [ -d "$TARGET" ]; then
    process_directory "$TARGET"
else
    evict_file "$TARGET"
fi