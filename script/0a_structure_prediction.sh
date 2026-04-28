#!/bin/bash
# ============================================================================
# 0a_structure_prediction.sh — Step 0: 3D structure prediction with Boltz-2
# ----------------------------------------------------------------------------
# For each .fasta in $INPUT_DIR, predicts the 3D structure using Boltz-2 in
# native mode (no Docker). The MSA is generated remotely via ColabFold.
# The resulting PDB is saved in $INPUT_DIR so that step 1 picks it up as if
# it had been provided by the user.
#
# If no .fasta is found in $INPUT_DIR, the script exits silently.
#
# REQUIREMENTS:
#   - conda env $CONDA_ENV_BOLTZ with boltz installed
#   - conda env $CONDA_ENV_MAIN with biopython (for CIF→PDB conversion)
#   - Internet connection (api.colabfold.com for MSA generation)
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

shopt -s nullglob
FASTA_FILES=("$INPUT_DIR"*.fasta)
shopt -u nullglob

if [ ${#FASTA_FILES[@]} -eq 0 ]; then
    exit 0
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 0: Structure Prediction (Boltz-2)                              ▒"
echo -e "+----------------------------------------------------------------------+"
echo "  Found ${#FASTA_FILES[@]} FASTA file(s) to process."
echo "  ⚠️  An internet connection is required (api.colabfold.com for MSAs)."
echo ""

BOLTZ_WORK_DIR="${OUTPUT_BASE_DIR}.boltz_tmp"
mkdir -p "$BOLTZ_WORK_DIR"

SUCCESS=0
FAILED=0
for FASTA_PATH in "${FASTA_FILES[@]}"; do
    FASTA_BASE=$(basename "$FASTA_PATH" .fasta)
    EXPECTED_PDB="${INPUT_DIR}${FASTA_BASE}.pdb"

    if [ -f "$EXPECTED_PDB" ]; then
        echo "  ⏭️  $FASTA_BASE: PDB already present, skipping"
        continue
    fi

    echo -ne "▒ Predicting $FASTA_BASE                ▒  In Progress  ▒"

    # 1. Reformat header into Boltz format (>A|protein)
    BOLTZ_INPUT="${BOLTZ_WORK_DIR}/${FASTA_BASE}_boltz.fasta"
    {
        echo ">A|protein"
        awk '/^>/ {next} {print}' "$FASTA_PATH"
    } > "$BOLTZ_INPUT"

    # 2. Run Boltz inside the boltz conda env
    pipeline_init_conda "$CONDA_ENV_BOLTZ" || {
        echo -e "\e[1;31m Failed (conda)\e[0m ▒"
        FAILED=$((FAILED + 1))
        continue
    }

    BOLTZ_LOG="${BOLTZ_WORK_DIR}/${FASTA_BASE}.log"
    (cd "$BOLTZ_WORK_DIR" && boltz predict "$BOLTZ_INPUT" --use_msa_server > "$BOLTZ_LOG" 2>&1) || {
        echo -e "\e[1;31m Failed (boltz)\e[0m ▒"
        echo "    See log: $BOLTZ_LOG"
        FAILED=$((FAILED + 1))
        conda deactivate
        continue
    }

    # 3. Locate the generated CIF file
    CIF_PATH="${BOLTZ_WORK_DIR}/boltz_results_${FASTA_BASE}_boltz/predictions/${FASTA_BASE}_boltz/${FASTA_BASE}_boltz_model_0.cif"
    if [ ! -f "$CIF_PATH" ]; then
        echo -e "\e[1;31m Failed (no CIF)\e[0m ▒"
        FAILED=$((FAILED + 1))
        conda deactivate
        continue
    fi

    conda deactivate

    # 4. Convert CIF → PDB using Biopython
    pipeline_init_conda "$CONDA_ENV_MAIN" || {
        echo -e "\e[1;31m Failed (conda main)\e[0m ▒"
        FAILED=$((FAILED + 1))
        continue
    }

    if ! python -c "
from Bio.PDB.MMCIFParser import MMCIFParser
from Bio.PDB.PDBIO import PDBIO
parser = MMCIFParser(QUIET=True)
structure = parser.get_structure('m', '$CIF_PATH')
io = PDBIO()
io.set_structure(structure)
io.save('$EXPECTED_PDB')
" 2>>"$BOLTZ_LOG"; then
        echo -e "\e[1;31m Failed (cif->pdb)\e[0m ▒"
        FAILED=$((FAILED + 1))
        conda deactivate
        continue
    fi

    conda deactivate

    if [ -f "$EXPECTED_PDB" ]; then
        echo -e "\e[1;32m  Completed   \e[0m ▒"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "\e[1;31m Failed (no PDB)\e[0m ▒"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "  Predicted: $SUCCESS   Failed: $FAILED"

if [ "$FAILED" -eq 0 ]; then
    rm -rf "$BOLTZ_WORK_DIR"
fi

[ "$FAILED" -gt 0 ] && exit 1 || exit 0