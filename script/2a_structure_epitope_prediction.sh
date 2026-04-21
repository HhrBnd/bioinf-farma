#!/bin/bash
# Script: 2a_structure_epitope_prediction.sh

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

RED="\e[1;31m"; RESET="\e[0m"

echo -e "▒ STEP 2a: Structure Epitope Prediction ▒            Status            ▒"
echo -e "▒---------------------------------------+------------------------------▒"

# Verifica env vars
if ! pipeline_require OUTPUT_DIR PDB_FILE PDB_PATH; then
    echo -e "▒ ${RED}[ERROR]${RESET} OUTPUT_DIR, PDB_FILE, PDB_PATH devono essere definite. ▒"
    echo "▒ Esegui questo script tramite 0_run_pipeline.sh. ▒"
    exit 1
fi

# PDB corretto dallo step 1
CORRECTED_PDB_PATH="${OUTPUT_DIR}${PDB_FILE}_corrected.pdb"
if [ ! -f "$CORRECTED_PDB_PATH" ]; then
    echo -e "▒ ${RED}[ERROR]${RESET} File $CORRECTED_PDB_PATH not found! ▒"
    exit 1
fi

# Cleanup delle directory di lavoro MLCE (condivise: si ripuliscono ad ogni run)
rm -rf "${REBELOT_ROOT_OUT:?}"/*
rm -f  "${MLCE_INPUT_DIR:?}"/*

mkdir -p "$MLCE_INPUT_DIR" "$REBELOT_ROOT_OUT"

# Copia il PDB corretto in input MLCE
cp "$CORRECTED_PDB_PATH" "${MLCE_INPUT_DIR}/${PDB_FILE}_corrected.pdb"

# Cambia dir e attiva conda
cd "$MLCE_BIN_DIR" || {
    echo -e "▒ ${RED}[ERROR]${RESET} Cannot cd to $MLCE_BIN_DIR ▒"
    exit 1
}
pipeline_init_conda "$CONDA_ENV_REBELOT" || {
    echo -e "▒ ${RED}[ERROR]${RESET} Cannot activate conda env $CONDA_ENV_REBELOT ▒"
    exit 1
}

# Segnala inizio
touch "${OUTPUT_DIR}/structure_started"

# Run REBELOT
echo -ne "▒ Running REBELOT (mpi=$REBELOT_MPI_CORES)           ▒  In Progress  ▒"
python REBELOT.py -m b -f "${PDB_FILE}_corrected.pdb" --py -M --mpi "$REBELOT_MPI_CORES" \
    > "${OUTPUT_DIR}/rebelot_output.log" 2>&1
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\e[1;31m Failed\e[0m ▒"
    cat "${OUTPUT_DIR}/rebelot_output.log"
    exit 1
else
    echo -e "\e[1;32m  Completed  \e[0m ▒"
fi

# Copia risultati
mkdir -p "$OUTPUT_DIR"
cp "${REBELOT_OUTPUT_DIR}/beppe_snapshot.AMBER.log" "$OUTPUT_DIR" || {
    echo -e "▒ ${RED}[ERROR]${RESET} Cannot copy beppe_snapshot.AMBER.log ▒"
    exit 1
}
cp "${REBELOT_OUTPUT_DIR}/beppe_snapshot.AMBER.pml" "$OUTPUT_DIR" || {
    echo -e "▒ ${RED}[ERROR]${RESET} Cannot copy beppe_snapshot.AMBER.pml ▒"
    exit 1
}

touch "${OUTPUT_DIR}/structure_done"
