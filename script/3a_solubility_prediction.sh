#!/bin/bash
# Script: 3a_solubility_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+---------------------------------------+------------------------------+"
echo -e "▒ STEP 3a: Solubility Prediction        ▒            Status            ▒"
echo -e "+---------------------------------------+------------------------------+"

# Permetti chiamata sia con argomenti (FASTA, OUTPUT_CSV) sia con env vars
FASTA_FILE="${1:-$FASTA_PATH}"
COMBINED_OUTPUT="${2:-${OUTPUT_DIR%/}/solubility_scores.csv}"

if ! pipeline_require OUTPUT_DIR; then exit 1; fi

if [[ ! -f "$FASTA_FILE" ]]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m Il file FASTA $FASTA_FILE non esiste! ▒"
    exit 1
fi

# File di output interni ai singoli tool
DEEPSOLUE_OUTPUT="$DEEPSOLUE_DIR/results/result_deepsolue.csv"
PROTEINSOL_OUTPUT="$PROTEINSOL_DIR/seq_prediction.txt"
SOLUPROT_OUTPUT="$OUTPUT_DIR/soluprot_predictions.csv"

# Helper: esegue un comando in un env conda (isolato, non sporca l'ambiente corrente)
run_with_conda() {
    local env_name=$1
    shift
    (
        # shellcheck disable=SC1091
        source "$CONDA_ROOT/etc/profile.d/conda.sh"
        conda activate "$env_name"
        "$@"
    ) > "$OUTPUT_DIR/${env_name}_log.txt" 2>&1
}

# --- 1. DeepSoluE ---
echo -ne "▒ Running DeepSoluE                     ▒  In Progress  ▒"
cd "$DEEPSOLUE_DIR" || exit 1
mkdir -p "$DEEPSOLUE_DIR/sequence" "$DEEPSOLUE_DIR/results"
cp "$FASTA_FILE" "$DEEPSOLUE_DIR/sequence/input_seq.fasta"
run_with_conda "$CONDA_ENV_DEEPSOLUE" \
    python DeepSoluE.py -i input_seq.fasta -o result_deepsolue.csv &
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 2. ProteinSol ---
echo -ne "▒ Running ProteinSol                    ▒  In Progress  ▒"
cd "$PROTEINSOL_DIR" || exit 1
cp "$FASTA_FILE" "$PROTEINSOL_DIR/input_seq.fasta"
./multiple_prediction_wrapper_export.sh input_seq.fasta &
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 3. SoluProt ---
echo -ne "▒ Running SoluProt                      ▒  In Progress  ▒"
cd "$SOLUPROT_DIR" || exit 1
chmod +x "$USEARCH_PATH" 2>/dev/null || true
chmod +x "$TMHMM_BIN"    2>/dev/null || true
mkdir -p "$SOLUPROT_DIR/tmp"
run_with_conda "$CONDA_ENV_SOLUPROT" \
    python soluprot.py \
    --i_fa "$FASTA_FILE" \
    --o_csv "$SOLUPROT_OUTPUT" \
    --tmp_dir "$SOLUPROT_DIR/tmp" \
    --usearch "$USEARCH_PATH" \
    --tmhmm "$TMHMM_BIN" &
echo -e "\e[1;32m  Completed  \e[0m ▒"

# Attendi fine di tutti i processi in background
wait

# Estrai i valori
deepsolue_value=$(awk -F, 'NR==2 {print $3}' "$DEEPSOLUE_OUTPUT")
proteinsol_value=$(grep "SEQUENCE PREDICTIONS" "$PROTEINSOL_OUTPUT" | awk -F, '{print $4}')
soluprot_value=$(tail -n 1 "$SOLUPROT_OUTPUT" | cut -d',' -f3)

# Scrivi CSV combinato
{
    echo "input_sequence,Probability_dse,Probability_soluprot,Probability_protsol"
    echo "$(grep -v '>' "$FASTA_FILE" | tr -d '\n'),$deepsolue_value,$soluprot_value,$proteinsol_value"
} > "$COMBINED_OUTPUT"

echo -e "+----------------------------------------------------------------------+"
