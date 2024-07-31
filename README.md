# Overview
BLAST-smart is a collection of Bash scripts which allows for easy installation of the local NCBI full nucleotide (nt) and protein (nr) databases and conduction of multithreaded, memory-aware BLAST searches with lower RAM requirements, ideal for personal computer systems, removing the need for Cloud and HPC environments. Currently (14/04/24), the full NCBI nt and nr databases take up around ~450 GB and ~570 GB of disk space when decompressed, respectively, thus requiring just as much RAM to optimally query without additional configurations. BLAST-smart sets up the nt/nr databases and runs a BLASTn/BLASTp search in a manner which allows the database to be cached based on the user-specified thread and RAM requirements, permitting the BLASTing of the entire NCBI nt database with only 1 core and 4 GB of RAM at user's disposal. The utility of BLAST-smart will only become more apparent with time due to the exponential growth of the sequence data on the NCBI database.

## Minimum requirements (14/04/24)
- 1 core
- 4 GB RAM
- **nt:** 700 GB disk space (~500 GB post-installation, will increase with the future growth of the database; SSD or NVMe storage devices are highly recommended)
- **nr:** 850 GB disk space (~600 GB post-installation)
- BLAST+ installation and the availability of blastn/blastp binaries in PATH environmental variable

## Database installation instructions
To set up the NCBI nt/nr database, the scripts should be executed inside your local working BLAST-smart directory:
  1) ```git clone https://github.com/Maxim-Karpov/BLAST-smart```
  2) ```cd ./BLAST-smart```

**Manual install**

  3) ```bash download_db.sh``` - downloads the compressed NCBI nt or nr database by parts.
  4) ```bash extract_db.sh``` - extracts each volume of the downloaded NCBI nt or nr database.
  5) ```bash add_metadata_files.sh``` - adds necessary metadata to each extracted volume of the database for multithreading purposes and significantly lower RAM requirements.

**Automated install**

  3) ```bash install_db.sh``` - downloads database, decompresses volumes, adds metadata. ```-h``` for usage information.

**Clean up the directory (optional)**  

```bash clean_up.sh```  -  removes the compressed database volumes.

## BLAST-smart search instructions
Run the script BLAST_search.sh in your BLAST-smart directory with a given query FASTA file of choice (e.g. Example_BLAST_query.fasta) in the same directory:

```
bash BLAST_search.sh Example_BLAST_query.fasta
```

Without additional user input, the program will launch a single BLASTn/BLASTp thread, consuming a single CPU core and about 4 GB of RAM at a time. If higher core and RAM availability is specified, the program will automatically calculate the permissive number of BLAST processes to run. The calculated maximal number of BLAST processes is a slight underestimation of the actual number of processes you may feasibly run (at the moment you could possibly squeeze in an extra process for every 3-4 processes assigned by the program), this is primarly due to the calculation of RAM allocation. This means that, when large amounts of RAM are available, you may want to specify the -m paramater to be of a higher value than the actual quantity of RAM at your disposal if you would like to optimise the speed of the BLAST search (i.e. run more simultaneous BLASTn/BLASTp processes). Inspecting the process monitor with a RAM consumption display such as ```top``` during BLAST-smart operation at your maximal parameters may help you estimate a more accurate value for the ```-m``` parameter. The automatic process number assignment algorithm is there to ensure that "out of memory" errors are not encountered.

```
Further usage: BLAST_search.sh {query file name (e.g. Example_BLAST_query.fasta)} [options] 

   -n                    number of cores available for use [default=1]
   -m                    GB of RAM available for use [default=5]
   -db                   database selection (nt/nr, corresponding to blastn/blastp search, respectively) [default=nt]
   -max_seqs             BLASTn max_seqs parameter [default=10]
   -max_hsps             BLASTn max_hsps parameter [default=1]
   -e_val                Expect value (E) for saving hits [default=1e-5]
   -outfmt               format of the BLAST output [default='7 qseqid sseqid length qlen slen qstart qend sstart send evalue bitscore score pident']
   -rc                   continuously refresh cache during BLAST search (requires user privileges) [0/1] [default=0]
   -custom               custom BLAST options (e.g. '-perc_identity 20 -gapopen 10 -gapextend 5 -html') [default=]
   -h, --help            print description of command line arguments
```

## Considerations
 - If you plan to move the fully prepared database volumes from one storage drive to another, you may need to re-run the add_metadata_files.sh in the new directory to reset symlinks and avoid possible Segmentation fault (core dumped) errors i.e. the nt.ndb file in the nt.000.tar.gz_dir directory must be on the same storage drive (or a drive of identical hardware characteristics may work) as the rest of the database volumes before symlinks are created via the metadata script.
 - Cancelling the running BLAST_search.sh script (via Ctrl + C or via terminal closure) will not immediately shut down any blastn/blastp processes running in the background, they will shut down upon their completion, and searches over subsequent database volumes will be halted. If you wish to immediately terminate all processes you need to manually run ```pkill -f blastn``` or ```pkill -f blastp``` commands.
 - The ```-rc``` option was implemented in case that automatic cache clearance is not being performed by your operating system (as has been the case with my Ubuntu VM). It requires user permissions, which by default expire after 1 hour of terminal input innactivity, which may become laborious if it takes longer than 1 hour for your search to finish going through a batch of database volumes (as you have to re-type the password).

## Performance statistics 
The benchmarks were gathered using AMD Ryzen 3rd Gen processors, DDR4 2133MHz RAM, and an SSD storage device on a VirtualBox Ubuntu VM.
| Number of query sequences | 1 process run time (minutes) | 20 processes run time (minutes) |
| :---------: | :---------: | :------------: | 
| 1 | 21  | 12 |
| 10 | 28 | 13 |
| 100 | 36 | 14 |
| 1000 | 88 | 20 |
| 10000 | - | 29 |
| 100000 | - | 158 |

There are two main stages in the BLAST process: database caching (storage drive speed bottlenecked), and the search itself (CPU speed bottlenecked). In general, increasing the number of queries places more reliance of the BLAST process on the CPU speed, hence, much better gains in performance are seen with more running BLAST processes as queries increase from 1 to 100000. Increasing the number of BLAST processes causes a speed bottleneck during the database caching process.

## Output
- out.txt - raw concatenated output of the exectuted BLAST searches upon each database volume
- out.filtered.txt - out.txt but without "0 hit" entries
- out.nomatch.txt - "0 hit" entries only
- out.hits_only.txt - a single header, tab-separated file containing all of the matches

## Future implementations
  1) Improved filtering and logic of the output.
  2) Ability to run other types of BLAST searches.
  3) Database de-installation script.
  4) Correction of the output to correctly match the user designated ```-max_hsps``` parameter.
