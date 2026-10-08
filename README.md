# Overview
BLAST-smart is a collection of Bash scripts which allows for easy installation of the local NCBI full nucleotide (nt), core nucleotide (core_nt) and protein (nr) databases and conduction of multithreaded, memory-aware BLAST searches with lower RAM requirements, ideal for personal computer systems, removing the need for Cloud and HPC environments. Currently (14/04/24), the full NCBI nt and nr databases take up around ~450 GB and ~570 GB of disk space when decompressed, respectively, thus requiring just as much RAM to optimally query without additional configurations. BLAST-smart sets up the database and runs a BLAST search over each database volume separately, in a manner which allows the database to be cached based on the user-specified thread and RAM requirements, permitting the BLASTing of the entire NCBI nt database with only 1 core and 4 GB of RAM at user's disposal. The per-volume results are then merged into whole-database results, with E-values calculated for the size of the whole database. The utility of BLAST-smart will only become more apparent with time due to the exponential growth of the sequence data on the NCBI database.

Since August 2024, NCBI's default nucleotide database for web BLAST is **core_nt**: nt without most eukaryotic chromosome sequences, less than half the size of nt and giving very similar top hits for most searches. For most purposes (identifying genes, transcripts and bacterial sequences), core_nt is the better choice for a personal computer, and BLAST-smart supports it directly (`-db core_nt`).

## Minimum requirements (14/04/24)
- 1 core
- 4 GB RAM
- **nt:** 700 GB disk space (~500 GB post-installation, will increase with the future growth of the database; SSD or NVMe storage devices are highly recommended)
- **core_nt:** less than half of the nt requirement
- **nr:** 850 GB disk space (~600 GB post-installation)
- BLAST+ installation and the availability of the BLAST binaries (blastn, blastp, ... and blastdbcmd) in the PATH environmental variable
- wget (for downloading the database)

## Database installation instructions
To set up an NCBI database, the scripts should be executed inside your local working BLAST-smart directory:
  1) ```git clone https://github.com/Maxim-Karpov/BLAST-smart```
  2) ```cd ./BLAST-smart```

**Automated install (recommended)**

  3) ```bash install_db.sh -db core_nt``` (or `nt` / `nr`) - downloads the database, verifies the download, decompresses the volumes and adds metadata. ```-h``` for usage information. If the installation is interrupted, re-run it; the download resumes where it stopped and volumes that were already extracted are skipped. `-checkpoint 2` or `-checkpoint 3` starts from the extraction or metadata step.

**Manual install**

Each script takes the database name as an argument (`nt`, `core_nt` or `nr`), or asks for it if it is left out.

  3) ```bash download_db.sh core_nt``` - downloads the compressed NCBI database by parts and checks every part against NCBI's MD5 checksums.
  4) ```bash extract_db.sh core_nt``` - extracts each volume of the downloaded database.
  5) ```bash add_metadata_files.sh core_nt``` - adds necessary metadata to each extracted volume of the database for multithreading purposes and significantly lower RAM requirements.

**Clean up the directory (optional)**

```bash clean_up.sh core_nt```  -  removes the compressed database volumes (only those that were extracted successfully).

**Uninstall a database**

```bash uninstall_db.sh core_nt```  -  deletes the installed database volumes after asking for confirmation (`-y` to skip the question).

## BLAST-smart search instructions
Run the script BLAST_search.sh in your BLAST-smart directory with a given query FASTA file of choice (e.g. Example_BLAST_query.fasta):

```
bash BLAST_search.sh Example_BLAST_query.fasta -db core_nt
```

Without additional user input, the program will launch a single BLAST process, consuming a single CPU core and about 4 GB of RAM at a time. If higher core and RAM availability is specified, the program will automatically calculate the permissive number of BLAST processes to run, and starts the next database volume as soon as one finishes. The calculated maximal number of BLAST processes is a slight underestimation of the actual number of processes you may feasibly run (at the moment you could possibly squeeze in an extra process for every 3-4 processes assigned by the program), this is primarly due to the calculation of RAM allocation. This means that, when large amounts of RAM are available, you may want to specify the -m paramater to be of a higher value than the actual quantity of RAM at your disposal if you would like to optimise the speed of the BLAST search (i.e. run more simultaneous BLAST processes). Inspecting the process monitor with a RAM consumption display such as ```top``` during BLAST-smart operation at your maximal parameters may help you estimate a more accurate value for the ```-m``` parameter. The automatic process number assignment algorithm is there to ensure that "out of memory" errors are not encountered.

```
Further usage: BLAST_search.sh {query file name (e.g. Example_BLAST_query.fasta)} [options]

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
```

## Output
- out.txt - raw concatenated output of the executed BLAST searches upon each database volume
- out.hits_only.txt - a single header, tab-separated file with the top `-max_seqs` subjects per query, ranked by bitscore across the **whole database** (queries in the order of the query file)
- out.filtered.txt - out.txt but without "0 hit" entries (`-outfmt 7` only)
- out.nomatch.txt - queries that had no hits anywhere in the database
- out.log - warnings or errors reported by BLAST, if there were any

The filtered, ranked and no-match files are produced for tabular output (`-outfmt 6` or `7`); ranking needs the `qseqid` and `bitscore` columns. Use `-out` to give the output files a different prefix, e.g. to keep the results of several searches in one directory.

## Considerations
 - If you plan to move the fully prepared database volumes from one storage drive to another, you may need to re-run the add_metadata_files.sh in the new directory to reset symlinks and avoid possible Segmentation fault (core dumped) errors i.e. the nt.ndb file in the nt.000.tar.gz_dir directory must be on the same storage drive (or a drive of identical hardware characteristics may work) as the rest of the database volumes before symlinks are created via the metadata script.
 - Cancelling the running BLAST_search.sh script (via Ctrl + C or via terminal closure) stops all running BLAST processes. The per-volume results finished so far are kept in the `out_parts` directory.
 - The ```-rc``` option was implemented in case that automatic cache clearance is not being performed by your operating system (as has been the case with my Ubuntu VM). It asks for your sudo password once at the start of the search and keeps it active until the search ends.
 - If BLAST fails on any database volume, the script says so, keeps the per-volume outputs and logs, and exits with an error, because the merged results would be incomplete.

## Performance statistics
The benchmarks were gathered (with the original April 2024 version) using AMD Ryzen 3rd Gen processors, DDR4 2133MHz RAM, and an SSD storage device on a VirtualBox Ubuntu VM.
| Number of query sequences | 1 process run time (minutes) | 20 processes run time (minutes) |
| :---------: | :---------: | :------------: |
| 1 | 21  | 12 |
| 10 | 28 | 13 |
| 100 | 36 | 14 |
| 1000 | 88 | 20 |
| 10000 | - | 29 |
| 100000 | - | 158 |

There are two main stages in the BLAST process: database caching (storage drive speed bottlenecked), and the search itself (CPU speed bottlenecked). In general, increasing the number of queries places more reliance of the BLAST process on the CPU speed, hence, much better gains in performance are seen with more running BLAST processes as queries increase from 1 to 100000. Increasing the number of BLAST processes causes a speed bottleneck during the database caching process.

## Changelog

### 08/10/2026
**Correctness fixes (results of earlier versions may be affected)**
- **Incomplete results:** the search did not wait for the last batch of BLAST processes to finish before merging the outputs, so whenever the number of database volumes was not a multiple of the number of processes, hits from the last volumes could be missing or truncated. The script now waits for every process.
- **E-values:** each volume was searched as if it were the whole database, so E-values for nt were too small (hits looked more significant than they are) and the `-e_val` cutoff was looser than requested. BLAST-smart now reads the total database length with `blastdbcmd` and passes it to every process with `-dbsize`, so E-values match a whole-database search. On a test database they agreed with a single whole-database BLAST run to within 1%, compared with being about 5 times too small before. nr was less affected, because its alias files had a fixed April 2024 database length written into them; that fixed value has been removed.
- **Top hits:** `-max_seqs` was applied per volume, so out.hits_only.txt could contain up to 10 hits from every volume instead of the 10 best hits overall. Hits are now ranked by bitscore across all volumes and the best `-max_seqs` subjects per query are kept (all HSPs of a kept subject are kept, so `-max_hsps` is honoured).
- **No-match file:** out.nomatch.txt listed queries that had no hits in *a single volume*, and the search for "0 hits" also picked up "10 hits". It now lists queries with no hits in the whole database.
- **Output filtering ignored user settings:** the filtering step reset `-max_seqs` and `-outfmt` to their defaults.
- **nr RAM calculation:** the process limit was calculated from `.nsq` files only, which do not exist in protein databases, so the limit for nr was wrong.
- **Mixed databases:** with nt and nr installed in the same directory, a search used the volumes of both. Only the selected database's volumes are used now.

**Installation fixes**
- `download_db.sh` exited straight away whenever `nt` or `nr` was entered (inverted check), so it never downloaded anything. Fixed; downloads can now be resumed and are verified against NCBI's MD5 checksums.
- `install_db.sh -db nt` did not set the database name, so the download, extraction and metadata steps ran with an empty name. Fixed. `install_db.sh` now calls the individual scripts instead of repeating their code.
- `add_metadata_files.sh` assumed fixed volume names (3-digit for nt, 2-digit for nr). Volume names are now read from the extracted files, so any number of volumes and any numbering works.
- `extract_db.sh` reports volumes that fail to extract and skips volumes that were already extracted, so it can be re-run after an interruption.
- `clean_up.sh` only deletes compressed volumes that were extracted successfully.

**Usability fixes and new features**
- Ctrl+C or closing the terminal now stops all running BLAST processes (previously they continued in the background until finished).
- The help text was printed whenever `-h` appeared anywhere in the command line, e.g. in `-custom '-html'` or a query file called `my-hits.fasta`. An unknown option previously caused an endless loop; it now gives an error.
- Query files can be given with a path (e.g. `../queries/genes.fasta`).
- With `-rc 1`, the sudo password is asked for once and kept active for the whole search.
- The next volume starts as soon as any process finishes, instead of waiting for the whole batch.
- If BLAST fails on any volume, this is reported and the script exits with an error instead of silently producing incomplete results.
- New: core_nt support, `-program` (blastn, tblastn, tblastx for nucleotide databases; blastp, blastx for protein databases), `-dbsize`, `-dbdir`, `-out`, `-y`, and `uninstall_db.sh`.
- This completes all items of the previous "Future implementations" list (improved output filtering, other BLAST search types, a de-installation script, correct `-max_hsps` output).
