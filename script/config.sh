#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 [Your Name / Organization]

# ============================================================================
# config.sh — Configurazione centralizzata di tutta la pipeline
# ----------------------------------------------------------------------------
# Qualunque script della pipeline fa `source config.sh` in cima.
# Ogni variabile è SOVRASCRIVIBILE via env, per esempio:
#     export PIPELINE_BASE_DIR=/opt/bionfarma
#     export CONDA_ROOT=/opt/miniconda3
#     ./0_run_pipeline.sh -i ./in -o ./out
# ============================================================================

# --- Base dir (auto-detect: si assume config.sh in <BASE>/script/) ---------
if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PIPELINE_BASE_DIR="$(dirname "$_CONFIG_DIR")"
fi
export PIPELINE_BASE_DIR

# "Home" funzionale (dove vivono conda e affini); default: HOME utente.
export PIPELINE_HOME="${PIPELINE_HOME:-$HOME}"

# --- Directory principali --------------------------------------------------
export SCRIPT_DIR="${SCRIPT_DIR:-$PIPELINE_BASE_DIR/script}"
export TOOLS_DIR="${TOOLS_DIR:-$PIPELINE_BASE_DIR/tools}"
export INPUT_DIR_DEFAULT="${INPUT_DIR_DEFAULT:-$PIPELINE_BASE_DIR/input}"
export OUTPUT_DIR_DEFAULT="${OUTPUT_DIR_DEFAULT:-$PIPELINE_BASE_DIR/output}"
export STATUS_DIR="${STATUS_DIR:-$PIPELINE_BASE_DIR/status}"
export LOG_DIR="${LOG_DIR:-$PIPELINE_BASE_DIR/logs}"

# --- Conda -----------------------------------------------------------------
export CONDA_ROOT="${CONDA_ROOT:-$PIPELINE_HOME/miniconda3}"
# Nomi degli environment (rinominabili via env)
export CONDA_ENV_MAIN="${CONDA_ENV_MAIN:-vs_immunohub}"      # feature_prediction + ag_score
export CONDA_ENV_BOLTZ="${CONDA_ENV_BOLTZ:-boltz}"           # Boltz-2 (step 0: FASTA→PDB)
export CONDA_ENV_REBELOT="${CONDA_ENV_REBELOT:-rebelot}"     # MLCE/REBELOT (step 2a)
export CONDA_ENV_BEPIPRED="${CONDA_ENV_BEPIPRED:-bepipred}"  # BepiPred3     (step 2b)
export CONDA_ENV_DEEPSOLUE="${CONDA_ENV_DEEPSOLUE:-deepsolue_env}"
export CONDA_ENV_SOLUPROT="${CONDA_ENV_SOLUPROT:-soluprot}"
export CONDA_ENV_BERTTHERMO="${CONDA_ENV_BERTTHERMO:-BertThermo}"
export CONDA_ENV_TEMSTAPRO="${CONDA_ENV_TEMSTAPRO:-temstapro_env}"
export CONDA_ENV_PROLATHERM="${CONDA_ENV_PROLATHERM:-prolatherm}"

# --- AMBER / pdb4amber (step 1) --------------------------------------------
export AMBERHOME="${AMBERHOME:-$TOOLS_DIR/epitope_tools/MLCE/amber24}"
export PDB4AMBER="${PDB4AMBER:-$AMBERHOME/bin/pdb4amber}"

# --- Boltz-2 / structure prediction (step 0) -------------------------------
# NB: Boltz-2 richiede una connessione internet (ColabFold remoto per gli MSA).
export STRUCTURE_DIR="${STRUCTURE_DIR:-$PIPELINE_HOME/Structure_input_library}"
export STRUCTURE_PREDICTOR_SCRIPT="${STRUCTURE_PREDICTOR_SCRIPT:-$STRUCTURE_DIR/structure_predictor_docker.py}"
export MMSEQS_BIN="${MMSEQS_BIN:-$STRUCTURE_DIR/mmseqs/bin}"
export PDB_DB_DIR="${PDB_DB_DIR:-PDB}"  # relativo a STRUCTURE_DIR quando cd-zati dentro

# --- MLCE / REBELOT (step 2a) ----------------------------------------------
export MLCE_DIR="${MLCE_DIR:-$TOOLS_DIR/epitope_tools/MLCE}"
export MLCE_INPUT_DIR="${MLCE_INPUT_DIR:-$MLCE_DIR/input_pdb}"
export MLCE_BIN_DIR="${MLCE_BIN_DIR:-$MLCE_DIR/bin}"
export REBELOT_OUTPUT_DIR="${REBELOT_OUTPUT_DIR:-$MLCE_DIR/rebelot_output/REBELOT}"
export REBELOT_ROOT_OUT="${REBELOT_ROOT_OUT:-$MLCE_DIR/rebelot_output}"
# Numero di core MPI per REBELOT. Default 32 (configurazione server originale).
# Riduci a 4/8 su macchine più piccole o container con risorse limitate.
export REBELOT_MPI_CORES="${REBELOT_MPI_CORES:-32}"

# --- BepiPred3 (step 2b) ---------------------------------------------------
export BEPIPRED_DIR="${BEPIPRED_DIR:-$TOOLS_DIR/epitope_tools/BepiPred3_src}"

# --- Solubility tools (step 3a) --------------------------------------------
export SOLUBILITY_DIR="${SOLUBILITY_DIR:-$TOOLS_DIR/solubility_tools}"
export DEEPSOLUE_DIR="${DEEPSOLUE_DIR:-$SOLUBILITY_DIR/DeepSoluE/DeepSoluE-master_source_code}"
export PROTEINSOL_DIR="${PROTEINSOL_DIR:-$SOLUBILITY_DIR/protein_sol}"
export SOLUPROT_DIR="${SOLUPROT_DIR:-$SOLUBILITY_DIR/soluprot/soluprot-1.0.1.0}"
export USEARCH_PATH="${USEARCH_PATH:-$SOLUBILITY_DIR/soluprot/usearch11.0.667_i86linux32}"
export TMHMM_BIN="${TMHMM_BIN:-$SOLUPROT_DIR/tmhmm-2.0c/bin/tmhmm}"

# --- Stability tools (step 3b) ---------------------------------------------
export STABILITY_DIR="${STABILITY_DIR:-$TOOLS_DIR/stability_tools}"
export BERTTHERMO_DIR="${BERTTHERMO_DIR:-$STABILITY_DIR/BertThermo}"
export TEMSTAPRO_DIR="${TEMSTAPRO_DIR:-$STABILITY_DIR/TemStaPro}"
export PROLATHERM_DIR="${PROLATHERM_DIR:-$STABILITY_DIR/ProLaTherm/prolatherm}"

# --- Modelli ML (step 3) ---------------------------------------------------
# I modelli sono committati in models/ (vedi models/README.md).
export MODELS_DIR="${MODELS_DIR:-$PIPELINE_BASE_DIR/models}"
export SOLUBILITY_MODEL="${SOLUBILITY_MODEL:-$MODELS_DIR/best_rf_model.pkl}"
export STABILITY_MODEL="${STABILITY_MODEL:-$MODELS_DIR/best_rf_model_3tools.pkl}"

# ============================================================================
# Helpers
# ============================================================================

# Inizializza conda in modo idempotente. Uso:
#   pipeline_init_conda <env_name>
pipeline_init_conda() {
    local env_name="${1:-base}"
    if [ ! -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]; then
        echo "ERROR: conda.sh non trovato in $CONDA_ROOT/etc/profile.d/" >&2
        echo "       Imposta CONDA_ROOT al path corretto." >&2
        return 1
    fi
    # shellcheck disable=SC1091
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    conda activate "$env_name"
}

# Esporta le variabili d'ambiente AMBER
pipeline_init_amber() {
    export LD_LIBRARY_PATH="$AMBERHOME/lib:${LD_LIBRARY_PATH:-}"
    export PERL5LIB="$AMBERHOME/lib/perl/mm_pbsa:${PERL5LIB:-}"
    export PYTHONPATH="$AMBERHOME/lib/python3.6/site-packages/:${PYTHONPATH:-}"
    export PATH="$AMBERHOME/bin:$PATH"
}

# Verifica che una variabile sia non vuota. Uso:
#   pipeline_require VAR_NAME [VAR_NAME2 ...]
pipeline_require() {
    local missing=0
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: variabile $var non definita" >&2
            missing=1
        fi
    done
    return $missing
}
