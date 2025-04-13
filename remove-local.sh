#!/bin/bash

# remove-local: Evict local iCloud copies while retaining cloud availability.
# Usage:
#   To evict one file/folder: ./remove-local.sh <file_or_folder_path>
#   To evict from a CSV list: ./remove-local.sh --csv <csv_file_path>
#
# Example CSV file (one file/folder path per line):
# /path/to/file1
# /path/to/folder1

# Global counters for overall reporting.
global_total_files=0
global_total_bytes=0
global_start_time=$(date +%s)

# Convert bytes to human-readable format.
human_readable() {
    local bytes=$1
    local value unit
    if [ "$bytes" -ge 1073741824 ]; then 
        value=$(echo "scale=2; $bytes / 1073741824" | bc)
        unit="GB"
    elif [ "$bytes" -ge 1048576 ]; then 
        value=$(echo "scale=2; $bytes / 1048576" | bc)
        unit="MB"
    elif [ "$bytes" -ge 1024 ]; then 
        value=$(echo "scale=2; $bytes / 1024" | bc)
        unit="KB"
    else
        value="$bytes"
        unit="B"
    fi
    echo "$value $unit"
}

# Function to evict a single file using brctl.
# It also calculates the size of the file (if available) and updates global counters.
evict_file() {
    local file="$1"
    if [ -f "$file" ]; then
        size=$(stat -f %z "$file" 2>/dev/null)
        # Update the global bytes counter if size is available.
        if [ -n "$size" ]; then
            global_total_bytes=$(( global_total_bytes + size ))
        fi
    fi
    # Update global file counter.
    global_total_files=$(( global_total_files + 1 ))
    # Run brctl silently.
    brctl evict "$file" > /dev/null 2>&1
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

# Function to process a directory:
# It builds an array of files and processes them with a continuously updating progress line.
process_directory() {
    local dir="$1"
    files=()
    # Populate the array with all files from the directory.
    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$dir" -type f)
    local total_files=${#files[@]}
    local count=0
    local start_time_dir=$(date +%s)
    for file in "${files[@]}"; do
        count=$((count + 1))
        evict_file "$file"
        # Calculate elapsed time (per directory) and update progress.
        local elapsed=$(( $(date +%s) - start_time_dir ))
        if [ "$count" -gt 0 ]; then
            avg_time=$(echo "scale=2; $elapsed / $count" | bc)
            remaining=$(echo "scale=2; $avg_time * ($total_files - $count)" | bc)
            percent=$(echo "scale=2; 100 * $count / $total_files" | bc)
        else
            avg_time=0
            remaining=0
            percent=0
        fi
        # Print a single progress line for the current directory.
        echo -ne "Progress for '$dir': $count/$total_files files evicted, $percent% complete - Estimated time remaining: ${remaining} sec\r"
    done
    echo ""
}

# Main processing branch for CSV mode.
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
    # Process each path (assumed comma-separated or one per line).
    while IFS=, read -r path || [ -n "$path" ]; do
        # Trim leading/trailing whitespace.
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
            echo "Evicted file: $path"
        else
            echo "Warning: Path '$path' does not exist. Skipping."
        fi
    done < "$CSV"
else
    # Non-CSV mode: treat the first parameter as a file or folder.
    TARGET="$1"
    if [ ! -e "$TARGET" ]; then
        echo "Error: The specified path '$TARGET' does not exist."
        exit 1
    fi
    if [ -d "$TARGET" ]; then
        process_directory "$TARGET"
    else
        evict_file "$TARGET"
        echo "Evicted file: $TARGET"
    fi
fi

# Final summary: calculate overall elapsed time and display results.
end_time=$(date +%s)
total_time=$(( end_time - global_start_time ))
echo ""
echo "Process complete."
echo "Total time: ${total_time} seconds."

if [ "$total_time" -gt 0 ]; then
    fps=$(echo "scale=2; $global_total_files / $total_time" | bc)
else
    fps=$global_total_files
fi

echo "Evicted $global_total_files files (${fps} files per second)."

readable=$(human_readable "$global_total_bytes")
echo "Total storage freed: $readable"