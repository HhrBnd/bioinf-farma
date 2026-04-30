#!/bin/bash
# ============================================================================
# 0a_structure_prediction.sh - Step 0: 3D structure prediction
# ----------------------------------------------------------------------------
# For each .fasta in $INPUT_DIR, predicts the 3D structure using the
# hierarchical strategy implemented in structure_predictor.py:
#
#   1. MMseqs2 search against a local PDB database -> if a match is found,
#      download the structure from RCSB.
#   2. (optional) MMseqs2 search against a local UniProtKB-TrEMBL database
#      -> if a match is found, fetch the AlphaFold pre-computed model
#      (pLDDT >= 75 required). Skipped if $UNIPROT_DB is unset/empty.
#   3. Otherwise, de novo prediction with Boltz-2 (native conda env, MSA
#      generated remotely via the ColabFold server).
#
# The resulting .pdb is saved next to the original .fasta so that step 1
# picks it up as if provided by the user.
#
# REQUIREMENTS:
#   - conda env $CONDA_ENV_MAIN (default: vs_immunohub) with biopython
#   - conda env $CONDA_ENV_BOLTZ (default: boltz) with boltz installed
#   - MMseqs2 binary in $MMSEQS_BIN (added to PATH automatically)
#   - Local PDB database at $PDB_DB
#   - (optional) Local UniProtKB-TrEMBL database at $UNIPROT_DB
#   - Internet connection (api.colabfold.com for MSAs; alphafold.ebi.ac.uk
#     and files.rcsb.org for structure downloads)
# ============================================================================

set -eo pipefail

if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

if ! pipeline_require INPUT_DIR; then
    exit 1
fi

# Find FASTA files in INPUT_DIR
shopt -s nullglob
FASTA_FILES=("$INPUT_DIR"*.fasta)
shopt -u nullglob

# No FASTA found -> silently exit (normal case if user provided PDBs)
if [ ${#FASTA_FILES[@]} -eq 0 ]; then
    exit 0
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "STEP 0: Structure Prediction                                           "
echo -e "+----------------------------------------------------------------------+"
echo "  Found ${#FASTA_FILES[@]} FASTA file(s) to process."
echo "  Strategy: PDB local search -> (UniProt+AlphaFold if configured) -> Boltz-2"
echo "  An internet connection is required."
echo ""

# Verify that the Python helper exists
PYTHON_PREDICTOR="${SCRIPT_DIR}/structure_predictor.py"
if [ ! -f "$PYTHON_PREDICTOR" ]; then
    echo "[ERROR] structure_predictor.py not found at: $PYTHON_PREDICTOR" >&2
    exit 1
fi

# Verify that the PDB database exists
if [ -z "${PDB_DB:-}" ]; then
    PDB_DB="${STRUCTURE_DIR}/PDB"
fi
if [ ! -f "$PDB_DB" ]; then
    echo "[WARNING] PDB database not found at: $PDB_DB" >&2
    echo "          The PDB local search will be skipped." >&2
    PDB_DB=""
fi

# Add MMseqs2 to PATH if available
if [ -d "${MMSEQS_BIN:-}" ]; then
    export PATH="${MMSEQS_BIN}:${PATH}"
fi

# Build the optional UniProt args
UNIPROT_ARGS=()
if [ -n "${UNIPROT_DB:-}" ] && [ -e "${UNIPROT_DB}" ]; then
    UNIPROT_ARGS=(--uniprot_db "$UNIPROT_DB")
    echo "  UniProt DB found: $UNIPROT_DB (AlphaFold lookup ENABLED)"
else
    UNIPROT_ARGS=(--no_uniprot)
    echo "  UniProt DB not configured (AlphaFold lookup DISABLED)"
fi

# Build the optional PDB args
PDB_ARGS=()
if [ -n "$PDB_DB" ]; then
    PDB_ARGS=(--pdb_db "$PDB_DB")
fi

# Build the optional Boltz env arg
BOLTZ_ENV_ARGS=()
if [ -n "${CONDA_ENV_BOLTZ:-}" ]; then
    BOLTZ_ENV_ARGS=(--boltz_env "$CONDA_ENV_BOLTZ")
fi

echo ""

# Activate the main conda env (provides Biopython for the predictor script)
pipeline_init_conda "$CONDA_ENV_MAIN" || {
    echo "[ERROR] Cannot activate conda env $CONDA_ENV_MAIN" >&2
    exit 1
}

# Loop over FASTA files
SUCCESS=0
FAILED=0
for FASTA_PATH in "${FASTA_FILES[@]}"; do
    FASTA_BASE=$(basename "$FASTA_PATH" .fasta)
    EXPECTED_PDB="${INPUT_DIR}${FASTA_BASE}.pdb"

    # Skip if the PDB already exists (user provided it directly)
    if [ -f "$EXPECTED_PDB" ]; then
        echo "  [SKIP] $FASTA_BASE: PDB already present"
        continue
    fi

    echo -ne "  Predicting ${FASTA_BASE}... "

    if python "$PYTHON_PREDICTOR" \
            "$FASTA_PATH" \
            "${PDB_ARGS[@]}" \
            "${UNIPROT_ARGS[@]}" \
            "${BOLTZ_ENV_ARGS[@]}" \
            > /dev/null 2>&1; then
        if [ -f "$EXPECTED_PDB" ]; then
            echo "OK"
            SUCCESS=$((SUCCESS + 1))
        else
            echo "FAILED (no PDB produced)"
            echo "    See log: ${INPUT_DIR}${FASTA_BASE}_report.log"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "FAILED"
        echo "    See log: ${INPUT_DIR}${FASTA_BASE}_report.log"
        FAILED=$((FAILED + 1))
    fi
done

conda deactivate

echo ""
echo "  Predicted: $SUCCESS   Failed: $FAILED"
echo "+----------------------------------------------------------------------+"

# Exit with error if at least one FASTA failed to produce a PDB
[ "$FAILED" -gt 0 ] && exit 1 || exit 0