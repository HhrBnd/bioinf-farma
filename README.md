
# BIOINF-farma Pipeline

Bioinformatics pipeline for **antigenicity**, **solubility** and **stability**
prediction of protein antigens starting from PDB structures.

The pipeline integrates structural and sequence-based B-cell epitope
predictors, and aggregates the output of multiple solubility/stability tools
with Random Forest models to produce a combined expression score.

---

## Table of contents

- [Pipeline overview](#pipeline-overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Repository layout](#repository-layout)
- [Configuration](#configuration)
- [Output](#output)
- [Known limitations](#known-limitations)
- [License](#license)

---

## Pipeline overview

The pipeline accepts `.pdb` and/or `.fasta` files as input. For each input file, it runs:

0. **(optional) Structure prediction** — if the input folder contains
   `.fasta` files, they are converted to `.pdb` with **Boltz-2**
   (`0a_structure_prediction.sh`).
   ⚠️ Requires an internet connection (ColabFold remote MSA generation).
1. **Preprocessing** — structure cleanup with `pdb4amber` and FASTA sequence
   extraction (`1_pdb_to_fasta.sh`).
2. **B-cell epitope prediction** (`2_epitope_prediction.sh`):
   - 2a — structure-based with MLCE/REBELOT
   - 2b — sequence-based with BepiPred3
   - aggregated antigenicity score (`ag_score.py`)
3. **Solubility and stability prediction** (`3_feature_prediction.sh`):
   - 3a — solubility: DeepSoluE + SoluProt + ProteinSol, aggregated with a
     Random Forest meta-learner (`solubility_prediction.py`)
   - 3b — stability: TemStaPro + ProLaTherm + BertThermo, aggregated with a
     Random Forest meta-learner (`stability_prediction.py`)
   - 3c — combined expression score: `0.8 × solubility + 0.2 × stability`

---

## Requirements

### System

- Linux (tested on Ubuntu/Debian)
- Miniconda or Anaconda
- AMBER 24 (for `pdb4amber`)
- `bc`, `awk`, `bash` ≥ 4 (any modern distro)

### Conda environments

The pipeline uses 9 separate conda environments — one per tool, as most of
them have conflicting dependencies. The default names (rename them in
`script/config.sh`) are:

| Environment           | Used by                     |
|-----------------------|-----------------------------|
| `boltz`               | step 0 (Boltz-2, optional)  |
| `vs_immunohub`        | step 2 (ag_score), step 3 ML|
| `rebelot`             | step 2a (MLCE/REBELOT)      |
| `bepipred`            | step 2b (BepiPred3)         |
| `deepsolue_env`       | step 3a (DeepSoluE)         |
| `soluprot`            | step 3a (SoluProt)          |
| `BertThermo`          | step 3b (BertThermo)        |
| `temstapro_env`       | step 3b (TemStaPro)         |
| `prolatherm`          | step 3b (ProLaTherm)        |

> ProteinSol (step 3a) does not use a dedicated conda env: it runs through
> its own bash wrapper `multiple_prediction_wrapper_export.sh`.

### Third-party tools

Install separately under `$TOOLS_DIR` (default: `tools/`). See
[`docs/INSTALL.md`](docs/INSTALL.md) for the full list of official sources
and citations.

**Step 1 — Preprocessing**
- AMBER 24 (pdb4amber) — https://ambermd.org/

**Step 2 — Epitope prediction**
- MLCE / REBELOT / BEPPE — https://github.com/colombolab/MLCE
- BepiPred-3.0 — https://github.com/UberClifford/BepiPred-3.0

**Step 3a — Solubility**
- DeepSoluE — https://github.com/wangchao-malab/DeepSoluE
- SoluProt + USEARCH + TMHMM — https://loschmidt.chemi.muni.cz/soluprot/?page=download
- Protein-Sol — https://protein-sol.manchester.ac.uk/software

**Step 3b — Stability**
- BertThermo — https://github.com/zhibinlv/BertThermo
- TemStaPro — https://github.com/ievapudz/TemStaPro
- ProLaTherm — https://github.com/grimmlab/ProLaTherm

For Step 0 (optional, only if you start from FASTA):

- **Boltz-2 wrapper** — https://github.com/biochorl/Structure_input_library
- **Boltz-2** — https://github.com/jwohlwend/boltz
- **MMseqs2** — https://github.com/soedinglab/MMseqs2
- Indexed PDB database (~500 MB)

> `tools/` and `Structure_input_library/` are in `.gitignore`: they are
> external tools, not part of this repository.

### Random Forest models

Two pre-trained models are included in the repository:

- `models/best_rf_model.pkl` — solubility aggregator (~20 MB)
- `models/best_rf_model_3tools.pkl` — stability aggregator (~164 KB)

They are loaded automatically by the pipeline. See
[`models/README.md`](models/README.md) for details and override options.

---

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/<your-user>/bioinf-farma-pipeline.git
cd bioinf-farma-pipeline

# 2. Make the scripts executable
chmod +x script/*.sh launcher.sh

# 3. Install the third-party tools under tools/ (see docs/INSTALL.md)

# 4. Create the 9 conda environments at once
for env in envs/*.yml; do conda env create -f "$env"; done

# 5. Try it out on the included example files
./script/0_run_pipeline.sh -i examples -o output
```

See [`docs/INSTALL.md`](docs/INSTALL.md) for a detailed installation guide.

---

## Usage

### Interactive mode

```bash
./script/0_run_pipeline.sh
```

### CLI with explicit directories

```bash
./script/0_run_pipeline.sh -i ./input -o ./output
```

### Batch mode (for automated jobs)

```bash
./script/0_run_pipeline.sh -i ./input -o ./output -y -q
```

| Flag          | Description                                              |
|---------------|----------------------------------------------------------|
| `-i`          | folder with `.pdb` and/or `.fasta` files                 |
| `-o`          | output folder                                            |
| `-y`          | auto-yes (skip the final prompt)                         |
| `-q`          | quiet (no `clear`, no ANSI headers: good for log files)  |
| `--no-boltz`  | skip Step 0 (any `.fasta` in input will be ignored)      |
| `-h`          | help                                                     |

### Starting from FASTA instead of PDB

If the input folder contains `.fasta` files, Step 0 automatically converts
them to `.pdb` with Boltz-2 before continuing. No extra flag is needed:
just drop them in.

```bash
mkdir -p input
cp sequences/*.fasta input/
./script/0_run_pipeline.sh -i ./input -o ./output
```

If Boltz is not available (or you have no internet) and `.fasta` files
ended up in the input folder by mistake, use `--no-boltz` to skip Step 0.

### Background execution with logs

```bash
./launcher.sh -i ./input -o ./output -n myJob
# prints PID and log path; then:
tail -f logs/myJob.log
```

---

## Repository layout

```
bioinf-farma-pipeline/
├── README.md
├── LICENSE
├── .gitignore
├── launcher.sh                        # nohup wrapper for background runs
├── script/
│   ├── config.sh                      # ⚙️ all paths and conda env names
│   ├── 0_run_pipeline.sh              # entry point
│   ├── 0a_structure_prediction.sh     # step 0 — Boltz-2 FASTA→PDB (opt.)
│   ├── 1_pdb_to_fasta.sh              # step 1
│   ├── 2_epitope_prediction.sh        # step 2 (orchestrator)
│   ├── 2a_structure_epitope_prediction.sh
│   ├── 2b_sequence_epitope_prediction.sh
│   ├── 3_feature_prediction.sh        # step 3 (orchestrator)
│   ├── 3a_solubility_prediction.sh
│   ├── 3b_stability_prediction.sh
│   ├── 3c_combine_scores.sh           # (not invoked, kept for manual use)
│   ├── ag_score.py                    # antigenicity scoring
│   ├── solubility_prediction.py       # RF aggregator for solubility
│   └── stability_prediction.py        # RF aggregator for stability
├── models/
│   ├── best_rf_model.pkl              # solubility RF meta-learner (~20 MB)
│   ├── best_rf_model_3tools.pkl       # stability RF meta-learner (~164 KB)
│   └── README.md
├── envs/                              # conda environment.yml specs
│   ├── boltz.yml
│   ├── vs_immunohub.yml
│   └── ... (9 envs total + AmberTools23.yml)
├── examples/                          # example input files (.pdb, .fasta)
│   ├── example_input_1.pdb
│   ├── example_input_1.fasta
│   ├── example_input_2.pdb
│   └── example_input_2.fasta
└── docs/
    └── INSTALL.md                     # detailed setup guide
```

---

## Configuration

All paths and conda environment names live in `script/config.sh`. You should
not need to edit that file: every variable is overridable through the
environment.

```bash
# Custom installation prefix
export PIPELINE_BASE_DIR=/opt/bioinf-farma
export CONDA_ROOT=/opt/miniconda3
./script/0_run_pipeline.sh

# Move the ML models elsewhere
export SOLUBILITY_MODEL=/data/models/rf_sol.pkl
export STABILITY_MODEL=/data/models/rf_stab.pkl
./script/0_run_pipeline.sh

# Rename conda envs (e.g. for a production deployment)
export CONDA_ENV_MAIN=prod_main
export CONDA_ENV_REBELOT=prod_rebelot
./script/0_run_pipeline.sh

# Reduce REBELOT MPI core count on small machines
export REBELOT_MPI_CORES=8
./script/0_run_pipeline.sh
```

Full list in `script/config.sh`. Each variable is defined as
`export VAR="${VAR:-default}"`.

---

## Output

For each `<n>.pdb` in the input folder, a subfolder `output/<n>/` is
created containing:

- `<n>.fasta` — extracted sequence
- `<n>_corrected.pdb` — PDB cleaned up by `pdb4amber`
- `beppe_snapshot.AMBER.log/.pml` — REBELOT output
- `raw_output.csv` — BepiPred3 raw output
- `<n>_final_results.csv` — per-residue antigenicity scoring
- `solubility_scores.csv` + `solubility_scores.csv_predicted_scores.csv`
- `stability_scores.csv` + `stability_scores.csv_predicted_scores.csv`

Two summary TSV files land in `output/`:

- `epitope_scores.tsv` — antigenicity per PDB
- `combined_scores.tsv` — solubility / stability / combined score per PDB

---

## Known limitations

- **Step 0 (Boltz-2) requires internet access.** Boltz calls ColabFold
  remotely to generate MSAs. Without a connection, Step 0 fails. Workaround:
  pre-compute the `.pdb` files and skip with `--no-boltz`, or feed them
  directly as input.
- **REBELOT is not thread-safe across concurrent jobs.** Step 2a uses a
  shared working directory (`tools/epitope_tools/MLCE/rebelot_output/`)
  that gets wiped on every run. Running two pipelines in parallel against
  the same installation will corrupt results. For parallel jobs, duplicate
  the whole `MLCE/` folder.
- **REBELOT uses `--mpi 32` by default.** On smaller machines, reduce this
  with `export REBELOT_MPI_CORES=8` before launching the pipeline.
- **No bit-for-bit reproducibility guarantee.** Boltz-2 has stochastic
  components; the RF models are deterministic but depend on the scikit-learn
  version. Pin versions with `environment.yml` files if exact reproducibility
  is critical.

---

## License

This project is licensed under the **GNU Affero General Public License v3.0
or later** (AGPL-3.0-or-later). See [`LICENSE`](LICENSE) for the full terms.

In short: you are free to use, study, modify and redistribute this software,
but any modified version — including versions exposed as a network service —
must be distributed under the same license, with full source code available
to its users.

If you deploy this pipeline as a web service, you **must** make the complete
source code (including any modifications) available to users of that service.
See section 13 of the AGPL-3.0 for the exact requirements.
