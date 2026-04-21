#!/bin/bash
# Script: 3b_stability_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 3b: Stability Prediction         ▒            Status            ▒"
echo -e "+---------------------------------------+------------------------------+"

# Accetta argomenti o env vars
FASTA_FILE="${1:-$FASTA_PATH}"
STABILITY_OUTPUT_FILE="${2:-${OUTPUT_DIR%/}/stability_scores.csv}"

if ! pipeline_require OUTPUT_DIR; then exit 1; fi

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$FASTA_FILE" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m Il file FASTA $FASTA_FILE non esiste! ▒"
    exit 1
fi

# Helper locale per esecuzione in un env conda (isolato, non sporca l'env corrente)
run_with_conda() {
    local env_name=$1
    shift
    (
        # shellcheck disable=SC1091
        source "$CONDA_ROOT/etc/profile.d/conda.sh"
        conda activate "$env_name"
        "$@"
    ) > "${OUTPUT_DIR}/${env_name}_log.txt" 2>&1
}

# --- 1. BertThermo ---
echo -ne "▒ Running BertThermo                    ▒  In Progress  ▒"
cd "$BERTTHERMO_DIR" || exit 1
run_with_conda "$CONDA_ENV_BERTTHERMO" \
    python predict.py --infasta "$FASTA_FILE" --out "${OUTPUT_DIR}/BertThermo_output"
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 2. TemStaPro ---
echo -ne "▒ Running TemStaPro                     ▒  In Progress  ▒"
cd "$TEMSTAPRO_DIR" || exit 1
run_with_conda "$CONDA_ENV_TEMSTAPRO" \
    ./temstapro -f "$FASTA_FILE" -d ./ProtTrans/ \
    -e "$OUTPUT_DIR" --mean-output "${OUTPUT_DIR}/TemStaPro_output.tsv"
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 3. ProLaTherm ---
# ProLaTherm richiede almeno 2 sequenze nel FASTA (workaround noto): duplichiamo
FASTA_DUPLICATED="${OUTPUT_DIR}/input_sequence_duplicated.fasta"
cp "$FASTA_FILE" "$FASTA_DUPLICATED"
cat "$FASTA_FILE" >> "$FASTA_DUPLICATED"

echo -ne "▒ Running ProLaTherm                    ▒  In Progress  ▒"
cd "$PROLATHERM_DIR" || exit 1
run_with_conda "$CONDA_ENV_PROLATHERM" \
    python3 run_prolatherm.py -df "$FASTA_DUPLICATED" -sd "$OUTPUT_DIR" --no_gpu True
echo -e "\e[1;32m  Completed  \e[0m ▒"

# Verifica output
BERTTHERMO_FILE="${OUTPUT_DIR}/BertThermo_output.res.pred.csv"
TEMSTAPRO_FILE="${OUTPUT_DIR}/TemStaPro_output.tsv"
PROLATHERM_FILE="${OUTPUT_DIR}/ProLaTherm_Predictions_input_sequence_duplicated.csv"

for file in "$BERTTHERMO_FILE" "$TEMSTAPRO_FILE" "$PROLATHERM_FILE"; do
    if [[ ! -f "$file" ]]; then
        echo -e "▒ \e[1;31m[ERROR]\e[0m $file non esiste! ▒"
        exit 1
    fi
done

# Estrai gli score
input_sequence=$(awk -F',' 'NR==2 {print $2}' "$PROLATHERM_FILE")
temstapro_score=$(awk -F'\t' 'NR==2 {print $14}' "$TEMSTAPRO_FILE" | awk '{printf "%.6f", $1}')
prolatherm_score=$(awk -F',' 'NR==2 {print $5}' "$PROLATHERM_FILE" | awk '{printf "%.6f", $1}')

# BertThermo: probabilità di thermophilic (invertita se NO)
read -r _ id seq thermophilic probability < <(awk -F',' 'NR==2 {print $1, $2, $3, $4, $5}' "$BERTTHERMO_FILE")
probability=$(echo "$probability" | sed 's/%//')
if [[ "$thermophilic" == "YES" ]]; then
    bert_score=$(printf "%.6f" "$(echo "scale=6; $probability / 100" | bc)")
else
    bert_score=$(printf "%.6f" "$(echo "scale=6; 1 - ($probability / 100)" | bc)")
fi

# Header CSV (se non esiste)
if [[ ! -f "$STABILITY_OUTPUT_FILE" ]]; then
    echo "input_sequence,temstapro_score,prolatherm_score,bert_score" > "$STABILITY_OUTPUT_FILE"
fi

echo "$input_sequence,$temstapro_score,$prolatherm_score,$bert_score" >> "$STABILITY_OUTPUT_FILE"

echo -e "+----------------------------------------------------------------------+"
