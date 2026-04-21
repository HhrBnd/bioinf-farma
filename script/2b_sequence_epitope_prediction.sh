#!/bin/bash
# Script: 2b_sequence_epitope_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 2b: Sequence Epitope Prediction  ▒            Status            ▒"
echo -e "▒---------------------------------------+------------------------------▒"

if ! pipeline_require FASTA_PATH OUTPUT_DIR; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m FASTA_PATH o OUTPUT_DIR non definite. ▒"
    exit 1
fi

if [[ ! -f "$FASTA_PATH" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m File $FASTA_PATH non esiste! ▒"
    exit 1
fi

mkdir -p "$OUTPUT_DIR" || {
    echo -e "▒ \e[1;31m[ERROR]\e[0m Cannot create output directory $OUTPUT_DIR ▒"
    exit 1
}

# Attiva conda env e lancia BepiPred3
echo -ne "▒ Running BepiPred3                     ▒  In Progress  ▒"
pipeline_init_conda "$CONDA_ENV_BEPIPRED" || {
    echo -e "\e[1;31m Failed\e[0m ▒"
    exit 1
}

python "${BEPIPRED_DIR}/bepipred3_CLI.py" \
    -i "$FASTA_PATH" -o "$OUTPUT_DIR" -pred vt_pred \
    > "${OUTPUT_DIR}/bepipred3_output.log" 2>&1
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\e[1;31m Failed\e[0m ▒"
    cat "${OUTPUT_DIR}/bepipred3_output.log"
    exit 1
else
    echo -e "\e[1;32m  Completed  \e[0m ▒"
fi

conda deactivate || true

touch "${OUTPUT_DIR}/sequence_done"
