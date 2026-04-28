#!/bin/bash
# ============================================================================
# 0_run_pipeline.sh — Bionfarma main pipeline (CLI)
# ----------------------------------------------------------------------------
# Usage:
#   ./0_run_pipeline.sh                            # interactive, dirs from config
#   ./0_run_pipeline.sh -i <input> -o <o>          # explicit dirs
#   ./0_run_pipeline.sh -i ./in -o ./out -y        # batch (no prompt)
#   ./0_run_pipeline.sh -i ./in -o ./out -y -q     # quiet batch (no clear)
#   ./0_run_pipeline.sh -i ./in -o ./out --no-boltz
#
# Input: the -i folder may contain .pdb and/or .fasta files.
#        If .fasta files are present, Step 0 converts them to .pdb with
#        Boltz-2 (internet required: ColabFold remote MSA generation).
#
# Flags:
#   -i DIR       folder with .pdb/.fasta          (default: $INPUT_DIR_DEFAULT)
#   -o DIR       output folder                    (default: $OUTPUT_DIR_DEFAULT)
#   -y           do not ask for final confirmation
#   -q           do not use `clear`, no graphic headers (useful in logs)
#   --no-boltz   skip Step 0 (any .fasta will be ignored)
#   -h           help
# ============================================================================

set -eo pipefail

# --- Load config ------------------------------------------------------------
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"

# --- Defaults ---------------------------------------------------------------
INPUT_DIR="${INPUT_DIR_DEFAULT}/"
OUTPUT_BASE_DIR="${OUTPUT_DIR_DEFAULT}/"
ASSUME_YES=0
QUIET=0
SKIP_BOLTZ=0

usage() {
    sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

# Two-pass parsing: long options first (getopts does not support them),
# short options afterwards.
_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --no-boltz) SKIP_BOLTZ=1; shift ;;
        --help)     usage ;;
        *)          _ARGS+=("$1"); shift ;;
    esac
done
set -- "${_ARGS[@]}"

while getopts "i:o:yqh" opt; do
    case "$opt" in
        i) INPUT_DIR="${OPTARG%/}/" ;;
        o) OUTPUT_BASE_DIR="${OPTARG%/}/" ;;
        y) ASSUME_YES=1 ;;
        q) QUIET=1 ;;
        h|*) usage ;;
    esac
done

# --- Convert paths to absolute ---------------------------------------------
# Required because some sub-scripts (e.g. 2a) `cd` into other directories.
mkdir -p "$OUTPUT_BASE_DIR" || {
    echo -e "\e[1;31m[ERROR]\e[0m Cannot create output directory: $OUTPUT_BASE_DIR" >&2
    exit 1
}
INPUT_DIR="$(cd "${INPUT_DIR%/}" 2>/dev/null && pwd)/" || {
    echo -e "\e[1;31m[ERROR]\e[0m Input directory not found" >&2
    exit 1
}
OUTPUT_BASE_DIR="$(cd "${OUTPUT_BASE_DIR%/}" && pwd)/"

# --- UI helpers -------------------------------------------------------------
print_header() {
    [ "$QUIET" -eq 1 ] && return
    echo -e "\033[1;32m  ¦¦¦¦¦¦+ ¦¦+ ¦¦¦¦¦¦+ ¦¦¦+   ¦¦+¦¦¦¦¦¦¦+    ¦¦¦¦¦¦¦+ ¦¦¦¦¦+ ¦¦¦¦¦¦+ ¦¦¦+   ¦¦¦+ ¦¦¦¦¦+ \033[0m"
    echo -e "\033[1;32m  ¦¦+--¦¦+¦¦¦¦¦+---¦¦+¦¦¦¦+  ¦¦¦¦¦+----+    ¦¦+----+¦¦+--¦¦+¦¦+--¦¦+¦¦¦¦+ ¦¦¦¦¦¦¦+--¦¦+\033[0m"
    echo -e "\033[1;32m  ¦¦¦¦¦¦++¦¦¦¦¦¦   ¦¦¦¦¦+¦¦+ ¦¦¦¦¦¦¦¦+¦¦¦¦¦+¦¦¦¦¦+  ¦¦¦¦¦¦¦¦¦¦¦¦¦¦++¦¦+¦¦¦¦+¦¦¦¦¦¦¦¦¦¦¦\033[0m"
    echo -e "\033[1;32m  ¦¦+--¦¦+¦¦¦¦¦¦   ¦¦¦¦¦¦+¦¦+¦¦¦¦¦+--++----+¦¦+--+  ¦¦+--¦¦¦¦¦+--¦¦+¦¦¦+¦¦++¦¦¦¦¦+--¦¦¦\033[0m"
    echo -e "\033[1;32m  ¦¦¦¦¦¦++¦¦¦+¦¦¦¦¦¦++¦¦¦ +¦¦¦¦¦¦¦¦         ¦¦¦     ¦¦¦  ¦¦¦¦¦¦  ¦¦¦¦¦¦ +-+ ¦¦¦¦¦¦  ¦¦¦\033[0m"
    echo -e "\033[1;32m  +-----+ +-+ +-----+ +-+  +---++-+         +-+     +-+  +-++-+  +-++-+     +-++-+  +-+\033[0m"
    echo -e "\033[1;37m--------------------------------------------------------------------------------------\033[0m"
    echo -e "\033[1;37m                BIOINFORMATIC PLATFORM POWERED BY IMMUNOHUB                          \033[0m"
    echo -e "\033[1;37m--------------------------------------------------------------------------------------\033[0m"
    echo ""
}

print_processing_message() {
    if [ "$QUIET" -eq 1 ]; then
        echo ">> Processing: $1 ($2 of $3)"
        return
    fi
    if [[ -n "$3" && "$3" -gt 1 ]]; then
        echo -e "\e[0m Now processing: \e[1;33m$1\e[0m (\e[1;35m$2 of $3\e[0m)"
    else
        echo -e "\e[0m Now processing: \e[1;33m$1\e[0m (\e[1;35m$2 of 1\e[0m)"
    fi
    echo ""
}

clear_screen() {
    [ "$QUIET" -eq 0 ] && clear
}

print_final_table() {
    clear_screen
    print_header
    echo -e "\033[1;34m                        PROCESSED PDBs - RANKED BY ANTIGENICITY\033[0m"
    echo ""
    echo -e "-------------------------------------------------------------------------------------"
    echo -e "PDB NAME         ANTIGENICITY SCORE     COMBINED EXPRESSION SCORE"
    echo -e "-------------------------------------------------------------------------------------"
    awk 'NR==FNR {if (NR > 1) antigenicity[$1]=$3; next}
         NR > 1 && ($1 in antigenicity) {printf "%-15s %-20.3f %-20.3f\n", $1, antigenicity[$1], $4}
    ' "$OUTPUT_TSV" "$COMBINED_TSV" | sort -k2,2nr | head -n 10
    echo -e "-------------------------------------------------------------------------------------"
}

# --- Start ------------------------------------------------------------------
clear_screen
print_header

# Check input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo -e "\e[1;31m[ERROR]\e[0m Input directory $INPUT_DIR does not exist." >&2
    exit 1
fi

mkdir -p "$OUTPUT_BASE_DIR"

# Define output TSV files
export INPUT_DIR
export OUTPUT_BASE_DIR
export OUTPUT_TSV="${OUTPUT_BASE_DIR}epitope_scores.tsv"
export COMBINED_TSV="${OUTPUT_BASE_DIR}combined_scores.tsv"

# --- Step 0: FASTA -> PDB with Boltz-2 (only if .fasta files are present) --
if [ "$SKIP_BOLTZ" -ne 1 ]; then
    bash "${SCRIPT_DIR}/0a_structure_prediction.sh"
fi

# Count PDB files (including those just generated by Boltz)
shopt -s nullglob
PDB_FILES=("$INPUT_DIR"*.pdb)
shopt -u nullglob
TOTAL_PDB=${#PDB_FILES[@]}

if [ "$TOTAL_PDB" -eq 0 ]; then
    echo -e "\e[1;31m[ERROR]\e[0m No .pdb file found in $INPUT_DIR" >&2
    echo "   (No convertible .fasta found, or Boltz was skipped via --no-boltz)" >&2
    exit 1
fi

# TSV headers
printf 'PDB_NAME\tsequence_length\tantigenicity_score\tdensity_antigenicity_score\tkernel_antigenicity_score\n' > "$OUTPUT_TSV"
printf 'PDB_NAME\tSOLUBILITY_SCORE\tSTABILITY_SCORE\tCOMBINED_SCORE\n' > "$COMBINED_TSV"

# --- Loop over PDBs ---------------------------------------------------------
CURRENT_PDB=1
for PDB_PATH in "${PDB_FILES[@]}"; do
    PDB_FILE=$(basename "$PDB_PATH" .pdb)

    clear_screen
    print_header
    print_processing_message "$PDB_FILE" "$CURRENT_PDB" "$TOTAL_PDB"

    OUTPUT_DIR="${OUTPUT_BASE_DIR}${PDB_FILE}/"
    mkdir -p "$OUTPUT_DIR" || {
        echo -e "\e[1;31m[ERROR]\e[0m Cannot create output directory $OUTPUT_DIR" >&2
        exit 1
    }

    FASTA_NAME="${PDB_FILE}"
    FASTA_PATH="${OUTPUT_DIR}${FASTA_NAME}.fasta"
    LOG_PATH="${OUTPUT_DIR}beppe_snapshot.AMBER.log"
    RAW_OUTPUT_CSV="${OUTPUT_DIR}raw_output.csv"

    export PDB_FILE PDB_PATH FASTA_NAME FASTA_PATH OUTPUT_DIR RAW_OUTPUT_CSV

    # Step 1 — PDB -> FASTA
    bash "${SCRIPT_DIR}/1_pdb_to_fasta.sh"
    if [ ! -f "$FASTA_PATH" ]; then
        echo -e "\e[1;31m[ERROR]\e[0m FASTA not created: $FASTA_PATH" >&2
        exit 1
    fi
    echo ""

    # Step 2 — Epitope prediction
    bash "${SCRIPT_DIR}/2_epitope_prediction.sh"
    if [ ! -f "$LOG_PATH" ]; then
        echo -e "\e[1;31m[ERROR]\e[0m pyBEPPE log not found: $LOG_PATH" >&2
        exit 1
    fi
    echo ""

    # Step 3 — Feature prediction
    bash "${SCRIPT_DIR}/3_feature_prediction.sh"
    echo ""

    CURRENT_PDB=$((CURRENT_PDB + 1))
done

# --- Final message ----------------------------------------------------------
echo -e "\033[1;32m======================================================================================\033[0m"
echo -e "\033[1;32m|                  PIPELINE COMPLETED SUCCESSFULLY FOR ALL PDB FILES!                |\033[0m"
echo -e "\033[1;32m======================================================================================\033[0m"

# Interactive prompt (skipped with -y)
if [ "$ASSUME_YES" -eq 1 ]; then
    print_final_table
    exit 0
fi

while true; do
    read -r -p "Would you like to display the results? (y/n): " VIEW_RESULTS
    case "$VIEW_RESULTS" in
        [Yy]*) print_final_table; break ;;
        [Nn]*) echo "Exiting without displaying the results."; break ;;
        *)     echo "Please enter 'y' or 'n'." ;;
    esac
done