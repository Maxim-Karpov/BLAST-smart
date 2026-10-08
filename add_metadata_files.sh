#!/usr/bin/env bash
#
# Prepares each extracted database volume so it can be searched on its own:
#  - writes a single-volume alias file (<db>.nal or <db>.pal) in every volume directory
#  - links the database-wide files that NCBI ships only with the first volume
#    (sequence ID/taxonomy lookup files, taxdb) into every other volume directory
#
# Volume names are read from the extracted files, so this works for any number of
# volumes and for 2- or 3-digit volume numbering (nt, core_nt, nr, ...).
#
# Usage: bash add_metadata_files.sh [nt|core_nt|nr]

database=$1
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to enrich with metadata? (nt/core_nt/nr): " database || exit 1
done

shopt -s nullglob
vols=( "${database}".*.tar.gz_dir )
if (( ${#vols[@]} == 0 )); then
	echo "ERROR: no ${database}.*.tar.gz_dir directories found in $(pwd). Run extract_db.sh first." >&2
	exit 1
fi

first="$(pwd)/${vols[0]}"

#Nucleotide (n) or protein (p) database?
seqfile=( "$first"/*.nsq "$first"/*.psq )
if (( ${#seqfile[@]} == 0 )); then
	echo "ERROR: no .nsq/.psq file in ${vols[0]} - was it extracted completely?" >&2
	exit 1
fi
[[ ${seqfile[0]} == *.psq ]] && t=p || t=n
first_volname=$(basename "${seqfile[0]%.*}")

#Database-wide files that live only in the first volume
shared=()
for f in "$first/${database}".* "$first"/taxdb.* "$first"/taxonomy4blast.sqlite3; do
	[[ -e $f ]] || continue
	name=$(basename "$f")
	[[ $name == "${first_volname}".* ]] && continue      # belongs to the first volume itself
	[[ $name == "${database}.${t}al" ]] && continue       # alias file, written below
	shared+=( "$name" )
done

count=0
for vol in "${vols[@]}"; do
	dir="$(pwd)/$vol"
	volseq=( "$dir"/*."${t}sq" )
	if (( ${#volseq[@]} == 0 )); then
		echo "ERROR: no .${t}sq file in $vol - skipping it." >&2
		continue
	fi
	volname=$(basename "${volseq[0]%.*}")

	#Single-volume alias file, so that "-db $database" inside this directory searches this volume only
	printf "#\n# Alias file created by BLAST-smart add_metadata_files.sh on %s\n#\nTITLE %s (volume %s)\nDBLIST %s\n" \
		"$(date)" "$database" "$volname" "$volname" > "$dir/${database}.${t}al"

	if [[ $dir != "$first" ]]; then
		for name in "${shared[@]}"; do
			ln -s -f "$first/$name" "$dir/$name"
		done
	fi
	count=$((count + 1))
done

echo "Metadata added to $count volume(s) of $database."
