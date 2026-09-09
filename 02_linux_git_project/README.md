# Linux & Git ETL Project

This is my submission for the CoreDataEngineers Linux & Git exercise. The brief:
as a new Data Engineer on infrastructure that runs on Linux, build a Bash script
that performs a simple ETL process, schedule it with cron, write a Bash script to
move all CSV and JSON files from one folder to another, and version everything
with Git.

This project lives inside my bootcamp repository, `CDE_Bootcamp_3`, under
`02_linux_git_project/`. This README walks through the whole process, explaining
each step I took and why.

## What this project does

| Task | Deliverable | Summary |
| ------ | ------------- | --------- |
| 1 | `etl.sh` | Extract a CSV from the web, transform it, load it into a `Gold` folder |
| 2 | cron job | Run `etl.sh` automatically every day at 12:00 AM |
| 3 | `move_files.sh` | Move all CSV and JSON files from one folder into `json_and_CSV` |
| 4 | Git + GitHub | The whole project is versioned and published |

The dataset is New Zealand's Annual Enterprise Survey 2023 (a public CSV from
Stats NZ).

## Tools I used

Bash for all scripting, `curl` to download the data, `gawk` to parse and
transform the CSV, `cron` to schedule the pipeline, and `git` / GitHub for
version control.

## Project layout

```text
02_linux_git_project/
├── Readme.md
├── etl_pipeline/
│   ├── etl.sh
│   ├── raw/          # Extract writes the downloaded CSV here
│   ├── Transformed/  # Transform writes 2023_year_finance.csv here
│   └── Gold/         # Load writes the final CSV here
└── moving_files/
    ├── move_files.sh
    └── json_and_CSV/ # move_files.sh moves .csv/.json here
```

## Step 1: Create the project folder

Inside the bootcamp repository, I created the project folder and its two
sub folders, one for the ETL pipeline and one for moving files:

```bash
cd ~/projects/CDE_Bootcamp_3
mkdir -p 02_linux_git_project/etl_pipeline 02_linux_git_project/moving_files
cd 02_linux_git_project
```

I check where I am at any point with `pwd`.

## Step 2: Version control with Git

The bootcamp repository is already a Git repository (initialised at the
`CDE_Bootcamp_3` root), so all work in this project folder is versioned as part
of it. Task 4 below covers committing and pushing.

## Step 3: Set up the folder structure

I created the data layer folders and gave each an empty `.gitkeep` file. Git
doesn't track empty folders, so the `.gitkeep` placeholder lets the folders exist
in the repository while their generated contents stay ignored:

```bash
mkdir -p etl_pipeline/raw etl_pipeline/Transformed etl_pipeline/Gold moving_files/json_and_CSV
touch etl_pipeline/raw/.gitkeep etl_pipeline/Transformed/.gitkeep etl_pipeline/Gold/.gitkeep moving_files/json_and_CSV/.gitkeep
```

## Step 4: Add the scripts and `.gitignore`

I wrote the two scripts, `etl.sh` (in `etl_pipeline/`) and `move_files.sh` (in
`moving_files/`), and a `.gitignore`. The `.gitignore` keeps generated data out
of the repo. It ignores the contents of `raw/`, `Transformed/`, `Gold/`, and
`json_and_CSV/` while keeping the folders via their `.gitkeep`, and it also
ignores the local `.env` file and the cron log. I made the scripts executable:

```bash
chmod +x etl_pipeline/etl.sh moving_files/move_files.sh
```

`chmod +x` marks a file as a program I can run with `./etl.sh`; without it the
shell refuses with "permission denied".

## Task 1: The ETL pipeline (`etl.sh`)

`etl.sh` runs the three ETL stages in order and prints a labelled, confirmed
message at every step.

### Providing the URL through an environment variable

The task requires the download URL to live in an environment variable,
`CSV_URL`, that the script calls, rather than being written into the script
directly. I keep that value in a `.env` file next to the script, which it loads
automatically. Because `.env` can hold private values in real projects, I keep it
out of Git, so I create it locally from the dataset link. The dataset is the
Annual Enterprise Survey 2023 (financial year, provisional) CSV from Stats NZ:

> <https://www.stats.govt.nz/assets/Uploads/Annual-enterprise-survey/Annual-enterprise-survey-2023-financial-year-provisional/Download-data/annual-enterprise-survey-2023-financial-year-provisional.csv>

I wrote that URL into a `.env` file inside `etl_pipeline/`:

```bash
cd etl_pipeline
echo 'CSV_URL="<paste-the-url-here>"' > .env
```

### Running it

```bash
./etl.sh
```

Because the folders already exist (from Step 3), the SETUP step reports them as
already present, while EXTRACT downloads the data:

![Log Output](/02_linux_git_project/assets/log.png)

### What each stage does

- **SETUP** checks the three folders and reports each as already present or newly
  created, so every step is visible in the output.
- **Extract** downloads the CSV with `curl` into `raw/`, then confirms the file is
  present and non-empty.
- **Transform** renames the column `Variable_code` to `variable_code`, selects
  only `year, Value, Units, variable_code`, and writes
  `Transformed/2023_year_finance.csv`.
- **Load** copies the transformed file into `Gold/` and confirms it.

![etl](/02_linux_git_project/assets/etl.png)

### Two decisions worth noting

**Correct CSV parsing.** The source file has quoted fields that contain commas
(for example `"Food, Beverage and Tobacco Product Manufacturing"`). Splitting on
every comma, as `cut -d,` or `awk -F,` would, selects the wrong columns on those
rows. I used `gawk` with `FPAT`, which treats a quoted string as a single field,
and I match columns by name in the header rather than by position. This parses
the file correctly without altering the data.

**Idempotent and resumable.** Each stage checks whether its output already exists
and is non-empty, and skips the work if so. Re-running therefore doesn't
re-download or re-process anything, and a partial run resumes. To force a fresh
run I delete the outputs (from inside `etl_pipeline/`):

```bash
rm -rf raw Transformed Gold && ./etl.sh
```

## Task 2: Schedule with cron (daily at 12:00 AM)

I scheduled the script with cron. I opened my crontab with `crontab -e` and added
this line, using the absolute path to the script (cron does not start in the
project folder, so a relative path would be meaningless):

```cron
0 0 * * * /home/prantonia/projects/CDE_Bootcamp_3/02_linux_git_project/etl_pipeline/etl.sh >> /home/prantonia/projects/CDE_Bootcamp_3/02_linux_git_project/etl_pipeline/etl.log 2>&1
```

I found the absolute path by running `pwd` inside `etl_pipeline/`. The schedule
`0 0 * * *` means minute 0 of hour 0, midnight, every day, and `>> etl.log 2>&1`
appends both output and errors to a log so each run is recorded. I confirmed the
job with `crontab -l`. No `CSV_URL` is needed on the line because the script loads
`.env` next to itself, as long as `.env` exists on the machine.

Since a cron job lives in the system rather than the repo, this line (plus a
`crontab -l` screenshot) is my evidence that Task 2 was completed.

## Task 3: Move CSV and JSON files (`move_files.sh`)

I wrote a second Bash script that moves every `.csv` and `.json` file from a
source folder into a folder named `json_and_CSV`. It works with one or many
files, leaves other file types untouched, and reports how many it moved. It takes
optional source and destination arguments (run from inside `moving_files/`):

```bash
./move_files.sh                  # from current dir into ./json_and_CSV
./move_files.sh test             # from ./test into ./json_and_CSV
./move_files.sh test archive     # from ./test into ./archive
```

![moving_files](/02_linux_git_project/assets/move_files.png)

The task said to use any CSV and JSON of my choice, so I tested it with sample
files I created (for example `sales_2023.csv`, `customers.csv`, `config.json`).

## Task 4: Version everything with Git and publish

The project is versioned as part of the `CDE_Bootcamp_3` repository. To add it, I
staged the project folder (the `.gitignore` keeps the generated data and `.env`
out), committed, and pushed:

```bash
cd ~/projects/CDE_Bootcamp_3
git add 02_linux_git_project
git commit -m "Add Linux & Git ETL project"
git push
```

If the repository had not yet been connected to GitHub, the one-time setup would
be:

```bash
git branch -M main
git remote add origin https://github.com/prantonia/CDE_Bootcamp_3.git
git push -u origin main
```

Before pushing I ran `git status` and confirmed `.env` did not appear as a
tracked file, since it holds local configuration and is kept out of Git.
