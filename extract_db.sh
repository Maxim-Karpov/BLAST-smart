#!/usr/bin/env bash
#
# Extracts each downloaded volume of an NCBI BLAST database into its own
# directory (<volume>.tar.gz_dir). Volumes that were already extracted
# successfully are skipped, so the script can be re-run after an interruption.
#
# Usage: bash extract_db.sh [nt|core_nt|nr]
# Set BLAST_SMART_RC=1 to drop the page cache before each volume (needs sudo).

database=$1
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to extract? (nt/core_nt/nr): " database || exit 1
done

shopt -s nullglob
archives=( "${database}".*.tar.gz )
if (( ${#archives[@]} == 0 )); then
	echo "ERROR: no ${database}.*.tar.gz files found in $(pwd). Run download_db.sh first." >&2
	exit 1
fi

failed=0
for FILE in "${archives[@]}"; do
	dir="${FILE}_dir"
	if [[ -f "$dir/.extracted" ]]; then
		echo "Skipping $FILE (already extracted)"
		continue
	fi

	if [[ ${BLAST_SMART_RC:-0} == 1 ]]; then
		sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
	fi

	echo "Extracting $FILE"
	mkdir -p "$dir"
	if tar -xzf "$FILE" -C "$dir"; then
		touch "$dir/.extracted"
	else
		echo "ERROR: extraction of $FILE failed (corrupt download?)." >&2
		failed=$((failed + 1))
	fi
done

if (( failed > 0 )); then
	echo "ERROR: $failed volume(s) failed to extract. Re-download them and re-run this script." >&2
	exit 1
fi
echo "All volumes extracted."
