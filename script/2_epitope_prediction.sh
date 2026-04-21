#!/bin/bash
# Script: 2_epitope_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 2: Epitope Prediction                                           ▒"
echo -e "+---------------------------------------+------------------------------+"

# Verifica env vars
if ! pipeline_require FASTA_PATH OUTPUT_DIR PDB_FILE OUTPUT_TSV RAW_OUTPUT_CSV PDB_PATH; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m Variabili di ambiente non impostate correttamente. ▒"
    exit 1
fi

# Step 2a: structure-based (MLCE/REBELOT)
bash "${SCRIPT_DIR}/2a_structure_epitope_prediction.sh"

# Step 2b: sequence-based (BepiPred3)
bash "${SCRIPT_DIR}/2b_sequence_epitope_prediction.sh"

# File richiesti dallo scoring antigenico
LOG_PATH="${OUTPUT_DIR}beppe_snapshot.AMBER.log"

if [[ ! -f "$FASTA_PATH" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m Il file FASTA $FASTA_PATH non esiste! ▒"
    exit 1
fi

if [[ ! -f "$LOG_PATH" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m File di log pyBEPPE non trovato in $LOG_PATH! ▒"
    exit 1
fi

if [[ ! -f "$RAW_OUTPUT_CSV" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m File raw_output.csv non trovato in $RAW_OUTPUT_CSV! ▒"
    exit 1
fi

# Calcolo antigenicity score
echo -e "+----------------------------------------------------------------------+"
echo -ne "▒ Computing Antigenicity Score          ▒  In Progress  ▒"

pipeline_init_conda "$CONDA_ENV_MAIN"
python "${SCRIPT_DIR}/ag_score.py" \
    "$RAW_OUTPUT_CSV" "$LOG_PATH" "$OUTPUT_DIR" "$PDB_FILE" "$OUTPUT_TSV"
EXIT_CODE=$?
conda deactivate

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\e[1;31m Failed\e[0m ▒"
    exit 1
else
    echo -e "\e[1;32m  Completed  \e[0m ▒"
fi

echo -e "+----------------------------------------------------------------------+"
