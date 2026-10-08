#!/usr/bin/env bash
#
# BLAST-smart search
# Runs one single-threaded BLAST process per database volume, with the number of
# simultaneous processes limited by the CPU cores and RAM you make available, then
# merges the per-volume results into whole-database results.
#
# Usage: bash BLAST_search.sh {query file} [options]   (see -h)

set -o pipefail

#-------------------------------------------------------------------------------
# Usage description
#-------------------------------------------------------------------------------
usage() {
	cat <<EOF
Usage: $0 {query file name (e.g. Example_BLAST_query.fasta)} [options]

   -n                    number of cores available for use [default=1]
   -m                    GB of RAM available for use [default=5]
   -db                   database name: nt, core_nt or nr (or any other database installed
                         with install_db.sh) [default=nt]
   -dbdir                directory containing the installed database volumes [default=.]
   -program              BLAST program [default: blastn for nucleotide, blastp for protein databases]
                         nucleotide databases: blastn, tblastn, tblastx; protein databases: blastp, blastx
   -max_seqs             max_target_seqs: number of subjects reported per query, ranked by
                         bitscore across the whole database [default=10]
   -max_hsps             max_hsps: HSPs reported per query-subject pair [default=1]
   -e_val                Expect value (E) for saving hits [default=1e-5]
   -dbsize               effective database length used for E-value calculation
                         [default=auto: total length of all volumes; 0 = per-volume E-values (old behaviour)]
   -outfmt               format of the BLAST output [default='7 qseqid sseqid length qlen slen qstart qend sstart send evalue bitscore score pident']
   -out                  prefix for output files [default=out]
   -rc                   continuously refresh cache during BLAST search (requires sudo) [0/1] [default=0]
   -y                    do not ask for confirmation if the RAM limit allows fewer than 1 process
   -custom               custom BLAST options (e.g. '-perc_identity 20 -gapopen 10 -gapextend 5') [default=]
   -h, --help            print description of command line arguments
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
log() { echo "[$(date +%H:%M:%S)] $*"; }
is_int() { [[ $1 =~ ^[0-9]+$ ]]; }

#-------------------------------------------------------------------------------
# Process arguments and options
#-------------------------------------------------------------------------------
QUERY_NAME=""
n=""; m=""; db=""; dbdir=""; program=""; max_seqs=""; max_hsps=""; e_val=""
dbsize=""; OUTFMT=""; out_prefix=""; rc=""; assume_yes=0; CUSTOM=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		-n)        n=$2; shift 2 ;;
		-m)        m=$2; shift 2 ;;
		-db)       db=$2; shift 2 ;;
		-dbdir)    dbdir=$2; shift 2 ;;
		-program)  program=$2; shift 2 ;;
		-max_seqs) max_seqs=$2; shift 2 ;;
		-max_hsps) max_hsps=$2; shift 2 ;;
		-e_val)    e_val=$2; shift 2 ;;
		-dbsize)   dbsize=$2; shift 2 ;;
		-outfmt)   OUTFMT=$2; shift 2 ;;
		-out)      out_prefix=$2; shift 2 ;;
		-rc)       rc=$2; shift 2 ;;
		-y)        assume_yes=1; shift ;;
		-custom)   CUSTOM=$2; shift 2 ;;
		-*)        usage; echo; die "unknown option: $1" ;;
		*)
			[[ -z $QUERY_NAME ]] || die "more than one query file given ('$QUERY_NAME' and '$1')"
			QUERY_NAME=$1; shift ;;
	esac
done

[[ -n $QUERY_NAME ]] || { usage; echo; die "BLAST query file name must be specified (e.g. query.fasta)."; }
[[ -f $QUERY_NAME ]] || die "query file '$QUERY_NAME' not found."

#Set variable names/values and defaults
C="${n:-1}"
RAM="${m:-5}"
DB="${db:-nt}"
DBDIR="${dbdir:-.}"
MAX_SEQS="${max_seqs:-10}"
MAX_HSPS="${max_hsps:-1}"
E_VAL="${e_val:-1e-5}"
RC="${rc:-0}"
PREFIX="${out_prefix:-out}"
OUTFMT="${OUTFMT:-7 qseqid sseqid length qlen slen qstart qend sstart send evalue bitscore score pident}"
read -r -a CUSTOM_ARR <<< "$CUSTOM"

for v in C RAM MAX_SEQS MAX_HSPS; do
	is_int "${!v}" || die "$v must be a whole number (got '${!v}')."
done
(( C >= 1 )) || die "-n must be at least 1."
(( MAX_SEQS >= 1 )) || die "-max_seqs must be at least 1."
[[ -z $dbsize ]] || is_int "$dbsize" || die "-dbsize must be a whole number (got '$dbsize')."

QUERY_ABS="$(cd "$(dirname "$QUERY_NAME")" && pwd)/$(basename "$QUERY_NAME")"
DBDIR_ABS="$(cd "$DBDIR" 2>/dev/null && pwd)" || die "database directory '$DBDIR' not found."

#-------------------------------------------------------------------------------
# Find database volumes (only those belonging to the selected database)
#-------------------------------------------------------------------------------
shopt -s nullglob
VOLS=( "$DBDIR_ABS/$DB".*.tar.gz_dir )
shopt -u nullglob
(( ${#VOLS[@]} > 0 )) || die "no '$DB.*.tar.gz_dir' volume directories found in '$DBDIR_ABS'. Install the database first (bash install_db.sh -db $DB)."

#Work out the database type, the largest sequence file and each volume's name
DBTYPE=""
largest=0
VOL_NAMES=()
for vol in "${VOLS[@]}"; do
	seqfile=$(ls "$vol"/*.nsq "$vol"/*.psq 2>/dev/null | head -n 1)
	[[ -n $seqfile ]] || die "no .nsq/.psq sequence file in '$vol' - was the volume extracted completely?"
	case "$seqfile" in
		*.nsq) type=n ;;
		*.psq) type=p ;;
	esac
	[[ -z $DBTYPE || $DBTYPE == "$type" ]] || die "'$vol' mixes nucleotide and protein volumes."
	DBTYPE=$type
	if [[ ! -f "$vol/$DB.${DBTYPE}al" ]]; then
		die "'$vol' has no $DB.${DBTYPE}al alias file. Run: bash add_metadata_files.sh $DB"
	fi
	sz=$(stat -c %s "$seqfile")
	(( sz > largest )) && largest=$sz
	VOL_NAMES+=( "$(basename "${seqfile%.*}")" )
done

#Choose and check the BLAST program
if [[ -z $program ]]; then
	[[ $DBTYPE == p ]] && PROGRAM=blastp || PROGRAM=blastn
else
	PROGRAM=$program
	case "$DBTYPE:$PROGRAM" in
		n:blastn|n:tblastn|n:tblastx|p:blastp|p:blastx) ;;
		*) die "-program $PROGRAM cannot be used with the $([[ $DBTYPE == p ]] && echo protein || echo nucleotide) database '$DB'." ;;
	esac
fi
command -v "$PROGRAM" >/dev/null || die "'$PROGRAM' not found in PATH. Install BLAST+ first."

#-------------------------------------------------------------------------------
# Effective database size, so that E-values refer to the whole database rather
# than to a single volume
#-------------------------------------------------------------------------------
DBSIZE_ARGS=()
if [[ -n $dbsize ]]; then
	(( dbsize > 0 )) && DBSIZE_ARGS=( -dbsize "$dbsize" )
	(( dbsize == 0 )) && warn "-dbsize 0: E-values will be calculated per volume and will be lower (more significant-looking) than for a whole-database search."
elif command -v blastdbcmd >/dev/null; then
	total_letters=0
	for i in "${!VOLS[@]}"; do
		letters=$(blastdbcmd -db "${VOLS[$i]}/${VOL_NAMES[$i]}" -info 2>/dev/null | awk '/sequences;/ {gsub(",", ""); print $3; exit}')
		if ! is_int "$letters"; then
			total_letters=0
			break
		fi
		total_letters=$(( total_letters + letters ))
	done
	if (( total_letters > 0 )); then
		DBSIZE_ARGS=( -dbsize "$total_letters" )
		log "Whole-database length used for E-values: $total_letters letters"
	else
		warn "could not read the database length with blastdbcmd; E-values will be calculated per volume. Use -dbsize to set it manually."
	fi
else
	warn "blastdbcmd not found; E-values will be calculated per volume. Use -dbsize to set the database length manually."
fi

#-------------------------------------------------------------------------------
# Calculate the maximum number of simultaneous processes from RAM and cores,
# based on the size of the largest sequence file (+2 GB overhead per process)
#-------------------------------------------------------------------------------
per_process_gb=$(( largest / 1000000000 + 2 ))
RAM_process_limit=$(( RAM / per_process_gb ))
MAX_PROCESSES=$(( RAM_process_limit < C ? RAM_process_limit : C ))

log "Database: $DB (${#VOLS[@]} volumes), program: $PROGRAM"
log "Maximum number of processes: $MAX_PROCESSES"

if (( MAX_PROCESSES <= 0 )); then
	echo "Because the calculated maximum number of processes is lower than 1 (each process needs about $per_process_gb GB of RAM), the program may function at a slower rate, or may not function at all (e.g. crash due to an 'Out Of Memory' error), which will be evident during the caching of the first database volume"
	if (( ! assume_yes )); then
		answer_t=""
		while [[ $answer_t != [Yy] ]]; do
			read -r -p "Would you still like to proceed? (Y/N) " answer_t || exit 1
			[[ $answer_t == [Nn] ]] && exit 1
		done
	fi
	MAX_PROCESSES=1
fi

#-------------------------------------------------------------------------------
# Optional cache refresh: ask for the sudo password once, then keep it alive
#-------------------------------------------------------------------------------
KEEPALIVE_PID=""
if [[ $RC == 1 ]]; then
	sudo -v || die "-rc 1 needs sudo rights."
	( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
	KEEPALIVE_PID=$!
	disown
fi

#-------------------------------------------------------------------------------
# Run BLAST
#-------------------------------------------------------------------------------
PARTS="$(pwd)/${PREFIX}_parts"
FAIL_FILE="$PARTS/failed_volumes.txt"
rm -rf "$PARTS"
mkdir -p "$PARTS" || die "cannot create '$PARTS'."

cleanup() {
	[[ -n $KEEPALIVE_PID ]] && kill "$KEEPALIVE_PID" 2>/dev/null
}
trap cleanup EXIT

#Stop every running BLAST process when the search is cancelled (Ctrl+C or terminal closure)
on_interrupt() {
	trap - INT TERM HUP
	echo
	log "Search cancelled - stopping running BLAST processes..."
	local pids
	pids=$(jobs -p)
	#Stop the BLAST processes first, so that their parent processes can clean them up...
	for pid in $pids; do
		pkill -TERM -P "$pid" 2>/dev/null
	done
	sleep 1
	#...then stop the parent processes themselves
	for pid in $pids; do
		kill -TERM "$pid" 2>/dev/null
	done
	wait 2>/dev/null
	log "Stopped. Partial per-volume results are in $PARTS"
	exit 130
}
trap on_interrupt INT TERM HUP

run_volume() {
	local vol=$1 out=$2
	cd "$vol" || { echo "$vol" >> "$FAIL_FILE"; return 1; }
	if ! "$PROGRAM" -query "$QUERY_ABS" -db "$DB" -max_target_seqs "$MAX_SEQS" -max_hsps "$MAX_HSPS" \
			-evalue "$E_VAL" -outfmt "$OUTFMT" -out "$out" -num_threads 1 \
			"${DBSIZE_ARGS[@]}" "${CUSTOM_ARR[@]}" 2> "$out.log"; then
		echo "$vol" >> "$FAIL_FILE"
		return 1
	fi
}

for i in "${!VOLS[@]}"; do
	if [[ $RC == 1 ]]; then
		sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
	fi
	run_volume "${VOLS[$i]}" "$PARTS/$(printf 'part_%05d.txt' "$i")" &
	log "Started volume $((i + 1))/${#VOLS[@]}: ${VOL_NAMES[$i]}"
	#Keep at most MAX_PROCESSES running; start the next volume as soon as one finishes
	while (( $(jobs -rp | wc -l) >= MAX_PROCESSES )); do
		wait -n
	done
done

#Wait for the last processes to finish before collecting the results
wait
log "All volumes searched."

#-------------------------------------------------------------------------------
# Compile all volume outputs into one
#-------------------------------------------------------------------------------
cat "$PARTS"/part_*.txt > "$PREFIX.txt" 2>/dev/null

#Collect any BLAST warnings/errors
: > "$PREFIX.log"
for f in "$PARTS"/part_*.txt.log; do
	[[ -s $f ]] && { echo "== $(basename "${f%.txt.log}")"; cat "$f"; } >> "$PREFIX.log"
done
[[ -s "$PREFIX.log" ]] || rm -f "$PREFIX.log"

FAILED=0
if [[ -s $FAIL_FILE ]]; then
	FAILED=1
	warn "BLAST failed on $(wc -l < "$FAIL_FILE") volume(s) - results are INCOMPLETE. See $PREFIX.log and $FAIL_FILE"
fi

#-------------------------------------------------------------------------------
# Filter and rank results (tabular output formats 6 and 7 only)
#-------------------------------------------------------------------------------
read -r -a fmt_words <<< "$OUTFMT"
fmt=${fmt_words[0]}
fields=( "${fmt_words[@]:1}" )
std_fields=( qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore )

if [[ $fmt != 6 && $fmt != 7 ]] || [[ $OUTFMT == *delim=* ]]; then
	warn "result filtering and whole-database ranking need tabular output (-outfmt 6 or 7 with the default delimiter); only $PREFIX.txt was produced."
else
	#Expand the 'std' keyword (or an empty field list) to BLAST's standard columns
	if (( ${#fields[@]} == 0 )); then
		fields=( "${std_fields[@]}" )
	else
		expanded=()
		for f in "${fields[@]}"; do
			[[ $f == std ]] && expanded+=( "${std_fields[@]}" ) || expanded+=( "$f" )
		done
		fields=( "${expanded[@]}" )
	fi
	qcol=0; scol=0; bcol=0
	for i in "${!fields[@]}"; do
		case "${fields[$i]}" in
			qseqid)   (( qcol )) || qcol=$((i + 1)) ;;
			sseqid)   (( scol )) || scol=$((i + 1)) ;;
			bitscore) (( bcol )) || bcol=$((i + 1)) ;;
		esac
	done

	#Query order and IDs, as given in the FASTA file
	awk '/^>/ { sub(/^>/, ""); split($0, a, /[ \t]/); print a[1] }' "$QUERY_ABS" > "$PARTS/query_ids.txt"

	#out.filtered.txt: out.txt without the "0 hits" query blocks (format 7 only)
	if [[ $fmt == 7 ]]; then
		awk '
			function flush() { if (block != "" && hits > 0) printf "%s", block; block = ""; hits = 0 }
			/^# T?BLAST[NPX] / { flush() }
			/^# BLAST processed/ { flush(); next }
			/^# [0-9]+ hits found/ { hits = $2 }
			{ block = block $0 "\n" }
			END { flush() }
		' "$PREFIX.txt" > "$PREFIX.filtered.txt"
	fi

	#out.nomatch.txt: queries with no hits anywhere in the database
	if [[ $fmt == 7 ]]; then
		awk '
			/^# Query: / { q = $3; d = substr($0, 10); if (!(q in tot)) { tot[q] = 0; def[q] = d; order[++k] = q } }
			/^# [0-9]+ hits found/ { tot[q] += $2 }
			END { for (i = 1; i <= k; i++) if (tot[order[i]] == 0) print def[order[i]] }
		' "$PREFIX.txt" > "$PREFIX.nomatch.txt"
	elif (( qcol )); then
		awk -F'\t' -v q="$qcol" '
			FILENAME == ARGV[1] { ids[++k] = $1; next }
			!/^#/ && NF { seen[$q] = 1 }
			END { for (i = 1; i <= k; i++) if (!(ids[i] in seen)) print ids[i] }
		' "$PARTS/query_ids.txt" "$PREFIX.txt" > "$PREFIX.nomatch.txt"
	fi

	#out.hits_only.txt: one header line plus the top -max_seqs subjects per query, ranked by
	#bitscore across ALL volumes (each volume returns its own top hits, so they must be merged)
	header=$(IFS=$'\t'; echo "${fields[*]}")
	if (( qcol && bcol )); then
		awk -F'\t' -v OFS='\t' -v q="$qcol" -v b="$bcol" '
			FILENAME == ARGV[1] { if (!($1 in ord)) ord[$1] = FNR; next }
			/^#/ || NF == 0 { next }
			{
				if (!($q in ord)) ord[$q] = 1000000000 + (++extra)
				print ord[$q], $b, ++row, $0
			}
		' "$PARTS/query_ids.txt" "$PREFIX.txt" \
		| LC_ALL=C sort -t $'\t' -k1,1n -k2,2gr -k3,3n \
		| awk -F'\t' -v s="$scol" -v n="$MAX_SEQS" '
			{
				line = $0; sub(/^[^\t]*\t[^\t]*\t[^\t]*\t/, "", line)
				key = $1
				if (s) {
					split(line, f, "\t"); subj = f[s]
					if (!((key, subj) in kept)) {
						if (count[key] >= n) next
						kept[key, subj] = 1; count[key]++
					}
				} else if (count[key]++ >= n) next
				print line
			}
		' > "$PARTS/hits_ranked.txt"
		{ echo "$header"; cat "$PARTS/hits_ranked.txt"; } > "$PREFIX.hits_only.txt"
	else
		warn "-outfmt has no qseqid and/or bitscore column, so hits could not be ranked across volumes; $PREFIX.hits_only.txt contains every hit, unranked."
		{ echo "$header"; grep -v '^#' "$PREFIX.txt" | grep -v '^$'; } > "$PREFIX.hits_only.txt"
	fi
fi

if (( FAILED )); then
	log "Done, with errors. Per-volume outputs kept in $PARTS"
	exit 1
fi
rm -rf "$PARTS"
log "Done. Results: $PREFIX.txt$([[ -f $PREFIX.hits_only.txt ]] && echo ", $PREFIX.hits_only.txt")$([[ -f $PREFIX.filtered.txt ]] && echo ", $PREFIX.filtered.txt")$([[ -f $PREFIX.nomatch.txt ]] && echo ", $PREFIX.nomatch.txt")"
