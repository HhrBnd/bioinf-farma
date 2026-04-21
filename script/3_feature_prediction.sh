#!/bin/bash
# Script: 3_feature_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 3: Feature Prediction                                           ▒"

# Verifica env vars
if ! pipeline_require OUTPUT_DIR FASTA_PATH PDB_FILE COMBINED_TSV; then
    exit 1
fi

# File di output
SOLUBILITY_SCORES="${OUTPUT_DIR%/}/solubility_scores.csv"
STABILITY_SCORES="${OUTPUT_DIR%/}/stability_scores.csv"

# Attiva conda env principale (per gli script python di ML)
pipeline_init_conda "$CONDA_ENV_MAIN"

# --- 1. Solubility (tool grezzi: DeepSoluE + SoluProt + ProteinSol) ---
bash "$SCRIPT_DIR/3a_solubility_prediction.sh" "$FASTA_PATH" "$SOLUBILITY_SCORES"

# --- 2. AI-enhanced solubility (Random Forest che aggrega i 3 score) ---
echo -ne "▒ Computing AI-enhanced Solubility      ▒  In Progress  ▒"
python "$SCRIPT_DIR/solubility_prediction.py" "$SOLUBILITY_SCORES" "$SOLUBILITY_MODEL"
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 3. Stability (tool grezzi: TemStaPro + ProLaTherm + BertThermo) ---
bash "$SCRIPT_DIR/3b_stability_prediction.sh" "$FASTA_PATH" "$STABILITY_SCORES"

# --- 4. AI-enhanced stability (Random Forest che aggrega i 3 score) ---
echo -ne "▒ Computing AI-enhanced Stability       ▒  In Progress  ▒"
python "$SCRIPT_DIR/stability_prediction.py" "$STABILITY_SCORES" "$STABILITY_MODEL"
echo -e "\e[1;32m  Completed  \e[0m ▒"

# --- 5. Combined score ---
# Usiamo i punteggi AGGREGATI dal modello RF, non i valori grezzi dei singoli tool.
# I file _predicted_scores.csv sono prodotti dagli script Python qui sopra
# (solubility_prediction.py / stability_prediction.py → riga `to_csv(f"{dataset_path}_predicted_scores.csv", ...)`).
SOLUBILITY_PREDICTED="${SOLUBILITY_SCORES}_predicted_scores.csv"
STABILITY_PREDICTED="${STABILITY_SCORES}_predicted_scores.csv"

echo -e "+---------------------------------------+------------------------------+"
echo -ne "▒ Computing Combined Expression Score   ▒  In Progress  ▒"

if [[ ! -f "$SOLUBILITY_PREDICTED" ]]; then
    echo -e "\e[1;31m Failed\e[0m ▒"
    echo "Errore: File $SOLUBILITY_PREDICTED non esiste (output del modello RF di solubilità mancante)." >&2
    exit 1
fi

if [[ ! -f "$STABILITY_PREDICTED" ]]; then
    echo -e "\e[1;31m Failed\e[0m ▒"
    echo "Errore: File $STABILITY_PREDICTED non esiste (output del modello RF di stabilità mancante)." >&2
    exit 1
fi

# Leggi gli score aggregati RF (riga 2, colonna 2 = predicted_*_score)
solubility_score=$(awk -F, 'NR==2 {print $2}' "$SOLUBILITY_PREDICTED")
stability_score=$(awk -F, 'NR==2 {print $2}' "$STABILITY_PREDICTED")

solubility_score=$(printf "%.3f" "$solubility_score")
stability_score=$(printf "%.3f" "$stability_score")

# Combined = 0.8 * solubility + 0.2 * stability
combined_score=$(echo "scale=6; ($solubility_score * 0.8 + $stability_score * 0.2)" | bc)
combined_score=$(printf "%.3f" "$combined_score")

printf '%s\t%s\t%s\t%s\n' \
    "$PDB_FILE" "$solubility_score" "$stability_score" "$combined_score" \
    >> "$COMBINED_TSV"

echo -e "\e[1;32m  Completed  \e[0m ▒"
echo -e "+---------------------------------------+------------------------------+"
