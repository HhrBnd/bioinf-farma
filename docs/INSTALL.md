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

Follow each tool's upstream install instructions. If you install them
elsewhere, export the corresponding variables (see `script/config.sh`).

### Official sources and citations

**Preprocessing (Step 1)**

- **AmberTools / pdb4amber** — https://ambermd.org/
  Case et al., *J. Chem. Inf. Model.* 2023, doi:10.1021/acs.jcim.3c01153

**Epitope prediction (Step 2)**

- **MLCE / REBELOT / BEPPE** — structure-based B-cell epitope prediction
  https://github.com/colombolab/MLCE
  Scarabelli, Morra, Colombo, "Predicting Interaction Sites from the
  Energetics of Isolated Proteins: A New Approach to Epitope Mapping",
  Istituto di Chimica del Riconoscimento Molecolare (CNR), Milan.
  Capelli, Serapian, Colombo (2023), "Computational Epitope Prediction and
  Design for Antibody Development and Detection", in *Computer-Aided Antibody
  Design*, Methods in Molecular Biology vol. 2552, doi:10.1007/978-1-0716-2609-2_13
- **BepiPred-3.0** — sequence-based B-cell epitope prediction
  https://github.com/UberClifford/BepiPred-3.0 (also at
  https://services.healthtech.dtu.dk/services/BepiPred-3.0/)
  Clifford et al., *Protein Science* 2022, doi:10.1002/pro.4497

**Solubility prediction (Step 3a)**

- **DeepSoluE** — https://github.com/wangchao-malab/DeepSoluE
  Wang et al., *BMC Biology* 2023, doi:10.1186/s12915-023-01510-8
- **SoluProt** — https://loschmidt.chemi.muni.cz/soluprot/?page=download
  Hon et al., *Bioinformatics* 2021, doi:10.1093/bioinformatics/btaa1102
- **Protein-Sol** — https://protein-sol.manchester.ac.uk/software
  Hebditch et al., *Bioinformatics* 2017, doi:10.1093/bioinformatics/btx345
- **USEARCH** — https://www.drive5.com/usearch/
  Edgar, *Bioinformatics* 2010, doi:10.1093/bioinformatics/btq461
- **TMHMM 2.0c** — https://services.healthtech.dtu.dk/services/TMHMM-2.0/
  Krogh et al., *J. Mol. Biol.* 2001, doi:10.1006/jmbi.2000.4315

**Stability prediction (Step 3b)**

- **BertThermo** — https://github.com/zhibinlv/BertThermo
  doi:10.3390/app13052858
- **TemStaPro** — https://github.com/ievapudz/TemStaPro
  Pudžiuvelytė et al., *Bioinformatics* 2024, doi:10.1093/bioinformatics/btae157
- **ProLaTherm** — https://github.com/grimmlab/ProLaTherm
  doi:10.1093/nargab/lqad087

> Several tools above (MLCE/REBELOT, BepiPred-3.0, SoluProt, TMHMM) are
> free for academic use but distributed under non-commercial academic
> licenses. If you plan to use this pipeline for for-profit applications,
> check each tool's license individually.

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

1. Clone the wrapper repository to get `structure_predictor_docker.py`:
   https://github.com/biochorl/Structure_input_library
2. Create the `boltz` conda env following the Boltz-2 official docs:
   https://github.com/jwohlwend/boltz
3. Install MMseqs2 under `Structure_input_library/mmseqs/`:
   https://github.com/soedinglab/MMseqs2
   (Steinegger & Söding, *Nat. Biotechnol.* 2017, doi:10.1038/nbt.3988)
4. Download and index the local PDB database (~500 MB).

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
