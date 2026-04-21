# Installation guide

Detailed guide to set up a machine from scratch for the BIOINF-farma
pipeline.

## 1. Conda / Miniconda

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
# follow the prompts; then, if not default:
export CONDA_ROOT=$HOME/miniconda3
```

## 2. Conda environments

The pipeline uses 9 isolated environments. Exact specifications (with pinned
versions) are provided as `environment.yml` files in the `envs/` folder.

To create all environments at once:

```bash
for env in envs/*.yml; do
    conda env create -f "$env"
done
```

Or create them one at a time:

```bash
conda env create -f envs/boltz.yml
conda env create -f envs/vs_immunohub.yml
conda env create -f envs/rebelot.yml
conda env create -f envs/bepipred.yml
conda env create -f envs/deepsolue_env.yml
conda env create -f envs/soluprot.yml
conda env create -f envs/BertThermo.yml
conda env create -f envs/temstapro_env.yml
conda env create -f envs/prolatherm.yml
```

To rename an environment at creation time, override the `name:` field:

```bash
conda env create -f envs/boltz.yml -n my_boltz_env
# then export CONDA_ENV_BOLTZ=my_boltz_env before running the pipeline
```

An extra file `envs/AmberTools23.yml` is also provided. The pipeline calls
AMBER's `pdb4amber` directly via its binary path (see `config.sh`) rather
than through a conda env, so strictly speaking this env is not required.
It is included in case you prefer to use the conda-managed AmberTools23
installation.

## 4. Third-party tools

Each tool must be installed under its own sub-folder below `$TOOLS_DIR`
(default: `tools/`). Expected paths:

```
tools/
├── epitope_tools/
│   ├── MLCE/                          # contains amber24/, bin/, input_pdb/, rebelot_output/
│   └── BepiPred3_src/
├── solubility_tools/
│   ├── DeepSoluE/DeepSoluE-master_source_code/
│   ├── protein_sol/
│   └── soluprot/
│       ├── soluprot-1.0.1.0/
│       ├── soluprot-1.0.1.0/tmhmm-2.0c/bin/tmhmm
│       └── usearch11.0.667_i86linux32
└── stability_tools/
    ├── BertThermo/
    ├── TemStaPro/
    └── ProLaTherm/prolatherm/
```

For each tool, follow the upstream installation instructions. If you install
them elsewhere, export the corresponding variables (see `script/config.sh`).

## 5. Boltz-2 module (optional, for Step 0)

Only required if you want to start from `.fasta` rather than `.pdb`. If you
already have all your structures as PDB files, skip this section and use
`--no-boltz`.

Expected layout (renamable via `STRUCTURE_DIR`):

```
Structure_input_library/
├── structure_predictor_docker.py   # Boltz-2 wrapper (not shipped with the repo)
├── mmseqs/bin/mmseqs               # MMseqs2 binary
└── PDB/                            # PDB database indexed with MMseqs2
```

Setup steps:

1. Create the `boltz` conda env following the Boltz-2 official docs.
2. Install MMseqs2 under `Structure_input_library/mmseqs/`.
3. Download and index the local PDB database (~500 MB).
4. Place `structure_predictor_docker.py` in `Structure_input_library/`.

> **Internet required at runtime**: Boltz-2 calls ColabFold remotely for
> MSA generation. Without a connection, Step 0 fails. If you are packaging
> the pipeline into a Docker container, document this external dependency
> clearly.

If you install everything elsewhere, export:

```bash
export STRUCTURE_DIR=/opt/Structure_input_library
```

## 6. RF models

See [`../models/README.md`](../models/README.md).

## 7. Sanity checks

```bash
# Syntax check across all scripts
bash -n script/*.sh launcher.sh
python3 -c "import ast; [ast.parse(open(f).read()) for f in [
    'script/ag_score.py',
    'script/solubility_prediction.py',
    'script/stability_prediction.py'
]]"

# Inspect how the config resolves paths on your machine
bash -c 'source script/config.sh && env | grep -E "^(PIPELINE|CONDA|AMBER|MLCE|BEPIPRED|DEEPSOLUE|SOLUPROT|PROTEINSOL|BERTTHERMO|TEMSTAPRO|PROLATHERM|SOLUBILITY|STABILITY|STRUCTURE|REBELOT|BOLTZ)_" | sort'
```
