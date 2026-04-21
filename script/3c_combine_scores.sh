#!/bin/bash
# Script: 3c_combine_scores.sh
# ----------------------------------------------------------------------------
# NOTA: questo script NON viene chiamato dalla pipeline attuale. La logica
# "combined score" è già dentro 3_feature_prediction.sh. Lo script resta
# qui per compatibilità / uso manuale.
# ----------------------------------------------------------------------------

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "\e[1;36m+-----------------------------------------------+"
echo -e "▒ STEP 3c: Combine Scores   ▒ Status           ▒"
echo -e "+----------------------------+------------------▒"

# Variabili richieste
echo -ne "▒ Checking required variables▒  "
if ! pipeline_require OUTPUT_DIR PDB_FILE; then
    echo -e "\e[1;31mMissing      \e[0m▒"
    exit 1
else
    echo -e "\e[1;32mSet         \e[0m▒"
fi

# File di input
# File di input
SOL_RAW="${OUTPUT_DIR%/}/solubility_scores.csv"
STAB_RAW="${OUTPUT_DIR%/}/stability_scores.csv"
# File effettivamente letti: output AGGREGATO del modello RF
SOL_PREDICTED="${SOL_RAW}_predicted_scores.csv"
STAB_PREDICTED="${STAB_RAW}_predicted_scores.csv"

echo -ne "▒ Checking solubility file   ▒  "
if [[ ! -f "$SOL_PREDICTED" ]]; then
    echo -e "\e[1;31mMissing      \e[0m▒"
    echo "Manca: $SOL_PREDICTED (output del modello RF di solubilità)" >&2
    exit 1
else
    echo -e "\e[1;32mFound       \e[0m▒"
fi

echo -ne "▒ Checking stability file    ▒  "
if [[ ! -f "$STAB_PREDICTED" ]]; then
    echo -e "\e[1;31mMissing      \e[0m▒"
    echo "Manca: $STAB_PREDICTED (output del modello RF di stabilità)" >&2
    exit 1
else
    echo -e "\e[1;32mFound       \e[0m▒"
fi

# Lettura score aggregati RF
solubility_score=$(awk -F, 'NR==2 {print $2}' "$SOL_PREDICTED")
stability_score=$(awk -F, 'NR==2 {print $2}' "$STAB_PREDICTED")

# Combined
echo -ne "▒ Computing combined score   ▒  "
if [[ -n "$solubility_score" && -n "$stability_score" ]]; then
    combined_score=$(echo "scale=6; ($solubility_score * 0.8 + $stability_score * 0.2)" | bc)
    combined_score=$(printf "%.3f" "$combined_score")
    echo -e "\e[1;32mCompleted    \e[0m▒"
else
    echo -e "\e[1;31mFailed       \e[0m▒"
    exit 1
fi

# Salva
echo -ne "▒ Saving results            ▒  "
COMBINED_TSV_LOCAL="${COMBINED_TSV:-${OUTPUT_DIR%/}/combined_scores.tsv}"
if [[ ! -f "$COMBINED_TSV_LOCAL" ]]; then
    printf 'PDB_NAME\tSOLUBILITY_SCORE\tSTABILITY_SCORE\tCOMBINED_SCORE\n' > "$COMBINED_TSV_LOCAL"
fi
printf '%s\t%s\t%s\t%s\n' "$PDB_FILE" "$solubility_score" "$stability_score" "$combined_score" >> "$COMBINED_TSV_LOCAL"
echo -e "\e[1;32mSaved        \e[0m▒"

echo -e "+-----------------------------------------------+"
