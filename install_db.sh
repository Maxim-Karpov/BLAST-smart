#!/usr/bin/env bash
#
# Installs an NCBI BLAST database for BLAST-smart in the current directory:
# 1) download (with checksum verification), 2) extract volumes, 3) add metadata.
#
# Usage: bash install_db.sh [options]   (see -h)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	cat <<EOF
Usage: $0 [options]

   -db                   database selection [nt/core_nt/nr]
   -checkpoint           start the installation from a certain step [1/2/3] [default=1]:
                           1) Download database (resumes a partial download)
                           2) Decompress volumes (skips volumes already extracted)
                           3) Add metadata files
   -rc                   refresh the page cache during extraction (requires sudo) [0/1] [default=0]
   -h, --help            print description of command line arguments
EOF
}

#Process arguments and options
database=""
cp=""
rc=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)   usage; exit 0 ;;
		-db)         database=$2; shift 2 ;;
		-checkpoint) cp=$2; shift 2 ;;
		-rc)         rc=$2; shift 2 ;;
		*)           usage; echo; echo "ERROR: unknown option: $1" >&2; exit 1 ;;
	esac
done

#User inputs
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to install? (nt/core_nt/nr): " database || exit 1
done

#Set variable names/values and defaults
C="${cp:-1}"
RC="${rc:-0}"
if [[ $C != 1 && $C != 2 && $C != 3 ]]; then
	echo "ERROR: -checkpoint must be 1, 2 or 3." >&2
	exit 1
fi
[[ $RC == 1 ]] && { sudo -v || exit 1; }

#Download compressed database
if (( C <= 1 )); then
	echo "Checkpoint 1: Downloading ${database} database"
	bash "$SCRIPT_DIR/download_db.sh" "$database" || { echo "Installation stopped at checkpoint 1. Re-run with: bash $0 -db $database -checkpoint 1" >&2; exit 1; }
fi

#Unpack compressed database files
if (( C <= 2 )); then
	echo "Checkpoint 2: Extracting ${database} database volumes"
	BLAST_SMART_RC=$RC bash "$SCRIPT_DIR/extract_db.sh" "$database" || { echo "Installation stopped at checkpoint 2. Re-run with: bash $0 -db $database -checkpoint 2" >&2; exit 1; }
fi

#Enrich with metadata
echo "Checkpoint 3: Enriching ${database} database volumes with metadata"
bash "$SCRIPT_DIR/add_metadata_files.sh" "$database" || exit 1

echo "Installation of $database complete. Optionally free up disk space with: bash clean_up.sh $database"
