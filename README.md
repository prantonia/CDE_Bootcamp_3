# CDE Bootcamp 3

This is the central repository for my work in the **CoreDataEngineers (CDE)
Bootcamp - Cohort 3.0**. It collects the projects and assignments I completed
during the bootcamp, each in its own numbered folder with its own documentation.

Use this README as an index: the summary of each project below links to that
project's own README, where the full details live.

---

## Repository structure

```text
CDE_Bootcamp_3/
├── 01_beejan_conceptual_pipeline/   # Conceptual complaints data-pipeline design
│   ├── README.md
│   ├── LICENSE
│   └── assets/                      # architecture diagram
│
├── 02_linux_git_project/            # Bash ETL pipeline, cron scheduling, file utility
│   ├── README.md
│   ├── etl_pipeline/                # etl.sh + raw / Transformed / Gold layers
│   └── moving_files/                # move_files.sh + demo files
│
└── README.md                        # this file
```

Each numbered folder is a self-contained project. Open a folder to find its own
README with everything specific to that project.

---

## Projects

### 01. Beejan Technologies: Conceptual Complaints Data Pipeline

**Folder:** [`01_beejan_conceptual_pipeline/`](./01_beejan_conceptual_pipeline/)

A **conceptual, end-to-end design** for a data pipeline for Beejan Technologies, a
telecom company whose customers raise thousands of complaints a day across
several channels, social media, call-centre logs, SMS, and website forms, each
in its own format. The project is a **blueprint, not an implementation**: it
settles the concepts and the flow of data so the pipeline can later be built on a
clear foundation, and deliberately names no specific technologies.

The design walks a single complaint from the moment it is raised to the insight
it produces, covering source identification (batch vs. streaming), ingestion, raw
storage in a data lake, a two-step transform (standardise/clean, then classify),
a curated data warehouse, serving (dashboards, ad-hoc querying, real-time
alerts), and orchestration, monitoring, and DataOps. It is documented with an
architecture diagram and a written rationale, including assumptions and open
challenges. See the [project README](./01_beejan_conceptual_pipeline/README.md).

### 02. Linux & Git ETL Project

**Folder:** [`02_linux_git_project/`](./02_linux_git_project/)

A small **ETL pipeline written in Bash** over New Zealand's Annual Enterprise
Survey 2023 dataset. It downloads the source CSV (Extract), renames and selects
columns (Transform), and loads the result into a `Gold` layer (Load). The project
also includes a cron schedule to run the pipeline daily, a utility script that
moves CSV and JSON files between folders, and full Git version control.

Key deliverables: `etl.sh` (the ETL pipeline), `move_files.sh` (the file mover),
a cron job for daily scheduling, and the project README documenting how it was
built. See the [project README](./02_linux_git_project/README.md) for the
step-by-step walkthrough.

---

## About the bootcamp

CoreDataEngineers is a data-engineering training programme. The work in this
repository was produced as part of Bootcamp Cohort 3.0, covering foundational
data-engineering skills - data-pipeline design, the Linux operating system, Bash
scripting, and version control with Git.

As more assignments are completed, each will be added here as a new numbered
folder with its own README, and listed under **Projects** above.
