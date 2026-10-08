#!/usr/bin/env bash
#
# Downloads the compressed volumes of an NCBI BLAST database (and their MD5
# checksums) into the current directory, then verifies them.
#
# Usage: bash download_db.sh [nt|core_nt|nr]

database=$1
while [[ $database != "nt" && $database != "core_nt" && $database != "nr" ]]; do
	read -r -p "Which database would you like to download? (nt/core_nt/nr): " database || exit 1
done

command -v wget >/dev/null || { echo "ERROR: wget is not installed." >&2; exit 1; }

#-c resumes interrupted downloads, so the script can simply be re-run
wget -c "ftp://ftp.ncbi.nlm.nih.gov/blast/db/${database}.*.tar.gz"
wget -c "ftp://ftp.ncbi.nlm.nih.gov/blast/db/${database}.*.tar.gz.md5"

shopt -s nullglob
md5_files=( "${database}".*.tar.gz.md5 )
if (( ${#md5_files[@]} == 0 )); then
	echo "WARNING: no checksum files were downloaded, so the volumes could not be verified." >&2
	exit 0
fi

echo "Verifying downloaded volumes..."
bad=0
for f in "${md5_files[@]}"; do
	if ! md5sum -c --quiet "$f"; then
		bad=$((bad + 1))
	fi
done

if (( bad > 0 )); then
	echo "ERROR: $bad volume(s) failed the checksum test. Delete the failed .tar.gz file(s) listed above and re-run this script." >&2
	exit 1
fi
echo "All ${#md5_files[@]} volumes downloaded and verified."
