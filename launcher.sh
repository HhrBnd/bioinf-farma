#!/bin/bash
# ============================================================================
# launcher.sh — Avvia la pipeline in background via nohup
# ----------------------------------------------------------------------------
# Uso:
#   ./launcher.sh                                   # input/output da config
#   ./launcher.sh -i ./in -o ./out                  # dir esplicite
#   ./launcher.sh -i ./in -o ./out -n mioJob        # nome log custom
#   ./launcher.sh -i ./in -o ./out --name mioJob    # forma lunga
#
# Il flag -y (batch) viene passato automaticamente a 0_run_pipeline.sh.
# Il PID viene stampato a video; il log va in $LOG_DIR/<nome>.log
# ============================================================================

set -eo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"

mkdir -p "$LOG_DIR"

# Estrai un eventuale --name/-n dagli argomenti, il resto passa così com'è
JOB_NAME=""
PIPELINE_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name)
            JOB_NAME="$2"
            shift 2
            ;;
        *)
            PIPELINE_ARGS+=("$1")
            shift
            ;;
    esac
done

if [ -z "$JOB_NAME" ]; then
    JOB_NAME="job_$(date +%Y%m%d_%H%M%S)"
fi

LOG_FILE="$LOG_DIR/${JOB_NAME}.log"

nohup bash "$_SELF_DIR/0_run_pipeline.sh" -y -q "${PIPELINE_ARGS[@]}" \
    > "$LOG_FILE" 2>&1 &
PID=$!

echo "Pipeline avviata in background."
echo "  PID:  $PID"
echo "  Log:  $LOG_FILE"
echo ""
echo "Segui il progresso con:"
echo "  tail -f $LOG_FILE"
echo ""
echo "Per terminare:"
echo "  kill $PID"
