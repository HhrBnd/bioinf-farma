#!/bin/bash
# Script: 1_pdb_to_fasta.sh

# Carica config se non già caricato dal padre
if [ -z "${PIPELINE_BASE_DIR:-}" ]; then
    _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_SELF_DIR/config.sh"
fi

echo -e "+----------------------------------------------------------------------+"
echo -e "▒ STEP 1: Preprocessing                 ▒            Status            ▒"
echo -e "+---------------------------------------+------------------------------+"

# Verifica variabili d'ambiente necessarie
if ! pipeline_require PDB_FILE INPUT_DIR OUTPUT_DIR; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m Assicurati di eseguire questo script tramite 0_run_pipeline.sh. ▒"
    exit 1
fi

# Percorso PDB originale
pdb_path="${INPUT_DIR}${PDB_FILE}.pdb"
if [ ! -f "$pdb_path" ]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m File $pdb_path non trovato! ▒"
    exit 1
fi

# PDB corretto in output
corrected_pdb_path="${OUTPUT_DIR}${PDB_FILE}_corrected.pdb"

# Verifica presenza pdb4amber
if [ ! -x "$PDB4AMBER" ]; then
    echo -e "▒ \e[1;31m[ERROR]\e[0m pdb4amber non eseguibile: $PDB4AMBER ▒"
    echo "   Controlla la variabile PDB4AMBER in config.sh" >&2
    exit 1
fi

# Run pdb4amber
echo -ne "▒ Running pdb4amber                     ▒  In Progress  ▒"
"$PDB4AMBER" -i "$pdb_path" -o "$corrected_pdb_path" \
    --most-populous -p -y --add-missing-atoms > /dev/null 2>&1
if [ ! -f "$corrected_pdb_path" ]; then
    echo -e "\e[1;31m Failed\e[0m  ▒"
    exit 1
else
    echo -e "\e[1;32m  Completed  \e[0m ▒"
fi

# FASTA output
fasta_name="${PDB_FILE}"
fasta_path="${OUTPUT_DIR}${fasta_name}.fasta"

# Dizionario 3-letter → 1-letter
declare -A aa_dict=(
    ["ALA"]="A" ["CYS"]="C" ["ASP"]="D" ["GLU"]="E" ["PHE"]="F"
    ["GLY"]="G" ["HIS"]="H" ["HIE"]="H" ["HIP"]="H" ["HID"]="H"
    ["ILE"]="I" ["LYS"]="K" ["LEU"]="L" ["MET"]="M" ["ASN"]="N"
    ["PRO"]="P" ["GLN"]="Q" ["ARG"]="R" ["SER"]="S" ["THR"]="T"
    ["VAL"]="V" ["TRP"]="W" ["TYR"]="Y" ["CYX"]="C"
)

# Estrai la sequenza
sequence=$(awk '/^ATOM/ && $3 == "CA" {print $4}' "$corrected_pdb_path" | while read -r aa; do
    echo -n "${aa_dict[$aa]}"
done)

# Scrivi FASTA
{
    echo ">${fasta_name}"
    echo "$sequence"
} > "$fasta_path"

echo -ne "▒ Writing FASTA                         ▒  In Progress  ▒"
if [ ! -s "$fasta_path" ]; then
    echo -e "\e[1;31m Failed\e[0m  ▒"
    exit 1
else
    echo -e "\e[1;32m  Completed  \e[0m ▒"
fi

echo -e "+----------------------------------------------------------------------+"
