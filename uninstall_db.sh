#!/usr/bin/env bash
#
# Removes an installed database: the extracted volume directories and any
# remaining compressed volumes and checksum files.
#
# Usage: bash uninstall_db.sh [nt|core_nt|nr] [-y]

database=""
yes=0
for arg in "$@"; do
	case "$arg" in
		-y) yes=1 ;;
		*)  database=$arg ;;
	esac
done
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to uninstall? (nt/core_nt/nr): " database || exit 1
done

shopt -s nullglob
targets=( "${database}".*.tar.gz_dir "${database}".*.tar.gz "${database}".*.tar.gz.md5 )
if (( ${#targets[@]} == 0 )); then
	echo "Nothing to remove: no $database files found in $(pwd)."
	exit 0
fi

size=$(du -sch "${targets[@]}" 2>/dev/null | tail -n 1 | cut -f1)
echo "This will permanently delete ${#targets[@]} $database files/directories ($size) from $(pwd)."
if (( ! yes )); then
	read -r -p "Continue? (Y/N) " answer || exit 1
	[[ $answer == [Yy] ]] || { echo "Cancelled."; exit 1; }
fi

rm -rf -- "${targets[@]}"
echo "$database uninstalled."
