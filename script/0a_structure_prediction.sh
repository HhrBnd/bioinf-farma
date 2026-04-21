#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 [Your Name / Organization]

# ============================================================================
# 0a_structure_prediction.sh — Step 0: predizione struttura 3D con Boltz-2
# ----------------------------------------------------------------------------
# Converte tutti i file .fasta presenti in $INPUT_DIR in file .pdb usando
# Boltz-2. I .pdb generati finiscono nella STESSA $INPUT_DIR, così lo step
# successivo (1_pdb_to_fasta.sh) li trova come se fossero stati caricati
# dall'utente.
#
# Se non ci sono .fasta in $INPUT_DIR, lo script esce silenziosamente.
#
# ⚠️ REQUISITI:
#   - env conda $CONDA_ENV_BOLTZ attivo e funzionante
#   - CONNESSIONE INTERNET (Boltz-2 chiama ColabFold in remoto per gli MSA)
#   - $STRUCTURE_DIR deve contenere structure_predictor_docker.py e mmseqs/
# ============================================================================

set -eo pipefail

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

# Verifica env vars necessarie dal padre
if ! pipeline_require INPUT_DIR; then
    exit 1
fi

# Cerca file .fasta
shopt -s nullglob
FASTA_FILES=("$INPUT_DIR"*.fasta)
shopt -u nullglob

# Nessun FASTA → esci silenziosamente (caso normale se l'utente ha già i PDB)
if [ ${#FASTA_FILES[@]} -eq 0 ]; then
    exit 0
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 0: Structure Prediction (Boltz-2) ▒            Status            ▒"
echo -e "+----------------------------------------------------------------------+"
echo "  Trovati ${#FASTA_FILES[@]} file FASTA da processare."
echo "  ⚠️  Serve una connessione internet (ColabFold remoto)."
echo ""

# Verifica tool Boltz
if [ ! -d "$STRUCTURE_DIR" ]; then
    echo -e "\e[1;31m[ERROR]\e[0m STRUCTURE_DIR non esiste: $STRUCTURE_DIR" >&2
    echo "   Imposta STRUCTURE_DIR in config.sh o esportala." >&2
    exit 1
fi

if [ ! -f "$STRUCTURE_PREDICTOR_SCRIPT" ]; then
    echo -e "\e[1;31m[ERROR]\e[0m Script non trovato: $STRUCTURE_PREDICTOR_SCRIPT" >&2
    exit 1
fi

if [ ! -d "$MMSEQS_BIN" ]; then
    echo -e "\e[1;31m[ERROR]\e[0m MMseqs2 non trovato in: $MMSEQS_BIN" >&2
    exit 1
fi

# Attiva conda env Boltz
pipeline_init_conda "$CONDA_ENV_BOLTZ" || {
    echo -e "\e[1;31m[ERROR]\e[0m Cannot activate conda env $CONDA_ENV_BOLTZ" >&2
    exit 1
}

# MMseqs2 nel PATH
export PATH="$MMSEQS_BIN:$PATH"

# Loop sui FASTA
for FASTA_PATH in "${FASTA_FILES[@]}"; do
    FASTA_BASE=$(basename "$FASTA_PATH" .fasta)
    EXPECTED_PDB="${INPUT_DIR}${FASTA_BASE}.pdb"

    # Se il PDB esiste già, skip
    if [ -f "$EXPECTED_PDB" ]; then
        echo "  ↷  $FASTA_BASE.pdb esiste già, skip predizione."
        continue
    fi

    echo -ne "▒ Predicting $FASTA_BASE                ▒  In Progress  ▒"

    # Copia il FASTA dove Boltz lo cerca, esegue lo script, sposta il PDB
    cp "$FASTA_PATH" "${STRUCTURE_DIR}/${FASTA_BASE}.fasta"
    (
        cd "$STRUCTURE_DIR"
        python3 "$STRUCTURE_PREDICTOR_SCRIPT" \
            "${FASTA_BASE}.fasta" \
            --pdb_db "$PDB_DB_DIR"
    ) > "${INPUT_DIR}${FASTA_BASE}_boltz.log" 2>&1
    EXIT_CODE=$?

    GENERATED_PDB="${STRUCTURE_DIR}/${FASTA_BASE}.pdb"
    if [ $EXIT_CODE -eq 0 ] && [ -f "$GENERATED_PDB" ]; then
        mv "$GENERATED_PDB" "$EXPECTED_PDB"
        rm -f "${STRUCTURE_DIR}/${FASTA_BASE}.fasta"
        echo -e "\e[1;32m  Completed  \e[0m ▒"
    else
        echo -e "\e[1;31m Failed\e[0m ▒"
        echo "   Vedi log: ${INPUT_DIR}${FASTA_BASE}_boltz.log" >&2
        # Cleanup parziale
        rm -f "${STRUCTURE_DIR}/${FASTA_BASE}.fasta"
        exit 1
    fi
done

conda deactivate || true

echo -e "+----------------------------------------------------------------------+"
