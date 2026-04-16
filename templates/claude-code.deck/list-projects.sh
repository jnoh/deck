#!/bin/bash
# List git repos in ~/dev/ as JSON options for the project picker
DEV_DIR="$HOME/dev"

echo "["
first=true
for dir in "$DEV_DIR"/*/; do
    [ -d "$dir/.git" ] || continue
    name=$(basename "$dir")
    path="${dir%/}"
    $first || echo ","
    first=false
    printf '  {"value": "%s", "label": "%s"}' "$path" "$name"
done
echo
echo "]"
