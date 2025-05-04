#!/bin/bash

# Merge and Clean Veto File Lists

# Ransomware extensions list
dynamic=ransom_veto.txt
# Common extensions list
static=common_veto.txt
# Final List
output=vetofiles.txt

# Remove "veto files = " from both files
static_clean=$(sed 's/^veto files = //' "$static")
dynamic_clean=$(sed 's/^veto files = //' "$dynamic")

# Combine both contents
combined="$static_clean$dynamic_clean"

# Replace occurrences of "//" with "/"
final_output=$(echo "$combined" | sed 's/\/\//\//g')

# Add "veto files = " to the beginning of the line
final_output="veto files = $final_output"

# Save the final content to the output file
echo "$final_output" > "$output"

echo Done

