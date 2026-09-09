#!/usr/bin/env bash
#
# etl.sh - A simple ETL pipeline in Bash for CoreDataEngineers.
#
# EXTRACT  : Download the Annual Enterprise Survey CSV into ./raw
# TRANSFORM: Rename "Variable_code" -> "variable_code", keep only
#            (year, Value, Units, variable_code), write to ./transformed
# LOAD     : Copy the transformed file into ./gold
#
# The download URL is supplied via an environment variable (CSV_URL).

# 'set' options make the script fail fast and loudly instead of silently
# continuing after an error:
#   -e  exit immediately if any command returns a non-zero status
#   -u  treat use of an unset variable as an error
#   -o pipefail  a pipeline fails if ANY command in it fails (not just the last)
set -euo pipefail

# Configuration

# Work relative to the folder this script lives in. 
# This is what makes the script safe to run from cron, which starts in a different directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# CSV_URL: the source URL, provided via an environment variable

ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -z "${CSV_URL:-}" && -f "$ENV_FILE" ]]; then
    # Load the .env file. 
    # 'set -a' (allexport) makes every assignment inside it automatically exported.
    # '-f' guards against a missing file so its absence is not an error here.
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# If CSV_URL is still not set, stop here with a clear message rather than
# failing later with a confusing error. Report which situation applies: 
# no .env
# file at all, 
# or a .env file that exists but doesn't define CSV_URL.
if [[ -z "${CSV_URL:-}" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        echo "ERROR: CSV_URL is not set. A .env file exists but does not define CSV_URL" >&2
        echo "       (it may be empty). Add this line to '$ENV_FILE':" >&2
        echo "         CSV_URL=\"<csv-url>\"" >&2
    else
        echo "ERROR: CSV_URL is not set, and no .env file was found." >&2
        echo "       Provide the URL in one of these ways, then re-run:" >&2
        echo "         - export it:      export CSV_URL=\"<csv-url>\"" >&2
        echo "         - or create .env: a file next to etl.sh with  CSV_URL=\"<csv-url>\"" >&2
    fi
    exit 1
fi

# Folder and file names used across the three stages
RAW_DIR="raw"
TRANSFORMED_DIR="Transformed"
GOLD_DIR="Gold"

RAW_FILE="${RAW_DIR}/annual-enterprise-survey-2023.csv"
TRANSFORMED_FILE="${TRANSFORMED_DIR}/2023_year_finance.csv"
GOLD_FILE="${GOLD_DIR}/2023_year_finance.csv"

echo "==================================================================="
echo ">>> ETL pipeline started: $(date '+%Y-%m-%d %H:%M:%S')"
echo ">>> Working directory   : $SCRIPT_DIR"

# SETUP: makes sure the three data-layer folders exist, reporting each one as
# already-present (the usual case after cloning) or newly created.

echo
echo ">>> SETUP: preparing data-layer directories"
for dir in "$RAW_DIR" "$TRANSFORMED_DIR" "$GOLD_DIR"; do
    if [[ -d "$dir" ]]; then
        echo "    Directory '$dir' already exists, no need to create it."
    else
        mkdir -p "$dir"
        echo "    Created directory '$dir'."
    fi
done

# EXTRACT

echo
echo ">>> EXTRACT: ensuring the raw CSV is present"

# Idempotent extract: only download if the raw file isn't already there. 
# '-s' test checks that the file exists and is non-empty. 
if [[ -s "$RAW_FILE" ]]; then
    raw_rows=$(( $(wc -l < "$RAW_FILE") - 1 ))
    echo "    SKIP: '$RAW_FILE' already present (${raw_rows} data rows); no download needed."
else
    echo "    Downloading from data source"
    # curl flags:
    #   -f  fail (return an error) on HTTP errors like 404 instead of saving the
    #       error page as if it were data
    #   -s  silent mode (no progress bar)
    #   -S  show the error message if it fails
    #   -L  follow redirects
    #   -o  write the download to this file
    curl -fsSL "$CSV_URL" -o "$RAW_FILE"

    # Confirm the file actually landed in the raw folder and is not empty.
    if [[ -s "$RAW_FILE" ]]; then
        raw_rows=$(( $(wc -l < "$RAW_FILE") - 1 ))   # subtract 1 for the header row
        echo "    SUCCESS: file saved to '$RAW_FILE' (${raw_rows} data rows)."
    else
        echo "    ERROR: download failed or file is empty." >&2
        exit 1
    fi
fi

# TRANSFORM

echo
echo ">>> TRANSFORM: renaming column and selecting columns"

# Idempotent transform: only rebuild the transformed file if it isn't there yet.
if [[ -s "$TRANSFORMED_FILE" ]]; then
    t_rows=$(( $(wc -l < "$TRANSFORMED_FILE") - 1 ))
    echo "    SKIP: '$TRANSFORMED_FILE' already present (${t_rows} data rows); no transform needed."
else
    # gawk FPAT treats a "quoted,field" as one column, so commas inside quotes
    # don't break parsing; columns are matched BY NAME, not by fixed position.
    gawk -v FPAT='([^,]*)|("[^"]*")' -v OFS=',' '
    NR == 1 {
        # Header row: find the position of each column we care about.
        for (i = 1; i <= NF; i++) {
            name = $i
            gsub(/"/, "", name)                 # strip any surrounding quotes
            if      (name == "Year")          y_col  = i
            else if (name == "Value")         v_col  = i
            else if (name == "Units")         u_col  = i
            else if (name == "Variable_code") vc_col = i   # <- to be renamed below
        }
        # Write the NEW header. "Variable_code" is renamed to "variable_code",
        # and outputs only the four requested columns, in the requested order.
        print "year", "Value", "Units", "variable_code"
        next
    }
    {
        # Data rows: emit only the four selected columns, exactly as they appear
        # in the source file.
        print $y_col, $v_col, $u_col, $vc_col
    }
    ' "$RAW_FILE" > "$TRANSFORMED_FILE"

    # Confirm the transformed file exists and is non-empty.
    if [[ -s "$TRANSFORMED_FILE" ]]; then
        t_rows=$(( $(wc -l < "$TRANSFORMED_FILE") - 1 ))
        echo "    SUCCESS: transformed file saved to '$TRANSFORMED_FILE' (${t_rows} data rows)."
        echo "    Preview:"
        head -3 "$TRANSFORMED_FILE" | sed 's/^/        /'
    else
        echo "    ERROR: transformation produced no output." >&2
        exit 1
    fi
fi

# LOAD

echo
echo ">>> LOAD: copying transformed data into the Gold layer"

# Idempotent load: only copy into gold if it isn't already there.
if [[ -s "$GOLD_FILE" ]]; then
    echo "    SKIP: '$GOLD_FILE' already present; no load needed."
else
    cp "$TRANSFORMED_FILE" "$GOLD_FILE"

    # Confirm the file made it into the gold folder.
    if [[ -s "$GOLD_FILE" ]]; then
        echo "    SUCCESS: data loaded to '$GOLD_FILE'."
    else
        echo "    ERROR: load step failed." >&2
        exit 1
    fi
fi

echo
echo ">>> ETL pipeline finished successfully: $(date '+%Y-%m-%d %H:%M:%S')"
echo "==================================================================="
