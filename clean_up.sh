#!/usr/bin/env bash
#
# Deletes the compressed database volumes (and their checksum files) once they
# have been extracted, to free up disk space.
#
# Usage: bash clean_up.sh [nt|core_nt|nr]

database=$1
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to clean up (delete the compressed db volumes)? (nt/core_nt/nr): " database || exit 1
done

shopt -s nullglob
removed=0
kept=0
for FILE in "${database}".*.tar.gz; do
	dir="${FILE}_dir"
	#Only delete archives whose volume was extracted (older installs have no .extracted marker)
	if [[ -f "$dir/.extracted" ]] || compgen -G "$dir/*.?sq" > /dev/null; then
		rm -f "$FILE" "$FILE.md5"
		removed=$((removed + 1))
	else
		echo "Keeping $FILE: it has not been extracted yet."
		kept=$((kept + 1))
	fi
done

echo "Removed $removed compressed volume(s)$( (( kept > 0 )) && echo ", kept $kept")."
