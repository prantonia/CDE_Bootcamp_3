#!/usr/bin/env bash
#
# move_files.sh - Move all CSV and JSON files from a source folder into a
#                 destination folder named "json_and_CSV".
#
# Works with ONE or MANY .csv / .json files. 
# If a file type is missing it is simply skipped (no error). 
# Usage:
#
#     ./move_files.sh [SOURCE_DIR] [DEST_DIR]
#
#   SOURCE_DIR  folder to move files FROM   (default: current directory ".")
#   DEST_DIR    folder to move files INTO   (default: "json_and_CSV")

# 'set' options make the script fail fast and loudly instead of silently continuing after an error:
set -euo pipefail

# Read the two optional arguments, applying defaults if they are not provided.
SRC_DIR="${1:-.}"
DEST_DIR="${2:-json_and_CSV}"

# Make sure the source folder actually exists before doing anything.
if [[ ! -d "$SRC_DIR" ]]; then
    echo "ERROR: source folder '$SRC_DIR' does not exist." >&2
    exit 1
fi

# Create the destination folder if it isn't there yet.
mkdir -p "$DEST_DIR"

# Shell options for safe globbing:
#   nullglob - if a pattern (e.g. *.csv) matches nothing, it expands to
#                 nothing instead of the literal string "*.csv"
#   nocaseglob - also match uppercase extensions like .CSV and .JSON
shopt -s nullglob nocaseglob

echo "Moving CSV and JSON files from '$SRC_DIR' to '$DEST_DIR' ..."

moved=0
# Loop over every .csv and .json file in the source folder.
for file in "$SRC_DIR"/*.csv "$SRC_DIR"/*.json; do
    # Skip anything that isn't a regular file
    [[ -f "$file" ]] || continue

    # Move the file into the destination folder.
    mv "$file" "$DEST_DIR"/
    echo "  moved: $file  -->  $DEST_DIR/"
    moved=$((moved + 1))
done

# Report the outcome.
if [[ "$moved" -eq 0 ]]; then
    echo "No CSV or JSON files found in '$SRC_DIR'. Nothing to move."
else
    echo "Done. $moved file(s) moved into '$DEST_DIR'."
fi
