# Installation Guide

Detailed guide to set up a machine from scratch for the BIOINF-farma
pipeline.

## 1. Conda / Miniconda

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
# follow the prompts; if not installed in default location:
export CONDA_ROOT=$HOME/miniconda3
```

## 2. Conda environments

The pipeline uses 9 isolated conda environments. Their exact specifications
(with pinned versions) are committed in `envs/`:

```bash
# Create all environments at once:
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

## 3. AMBER 24

Required for `pdb4amber` (Step 1, structure preprocessing). Install
AmberTools 24 following the official guide at https://ambermd.org/.

By default, the pipeline expects AMBER under
`tools/epitope_tools/MLCE/amber24/`. If installed elsewhere:

```bash
export AMBERHOME=/opt/amber24
export PDB4AMBER=$AMBERHOME/bin/pdb4amber
```

## 4. Third-party tools

Each tool must be installed under `$TOOLS_DIR` (default: `tools/`).
Expected paths:

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

If you install them elsewhere, override the corresponding variables (see
`script/config.sh`).

### Tool sources and citations

**Preprocessing (Step 1)**

- **AmberTools / pdb4amber** - https://ambermd.org/
  Case et al. (2023), *Journal of Chemical Information and Modeling* 63(20):6183-6191. doi:10.1021/acs.jcim.3c01153

**Epitope prediction (Step 2)**

- **MLCE / REBELOT / BEPPE** - structure-based B-cell epitope prediction
  https://github.com/colombolab/MLCE
  Capelli et al. (2023), *Methods in Molecular Biology* 2552:255-266. doi:10.1007/978-1-0716-2609-2_13
- **BepiPred-3.0** - sequence-based B-cell epitope prediction
  https://github.com/UberClifford/BepiPred-3.0 (also https://services.healthtech.dtu.dk/services/BepiPred-3.0/)
  Clifford et al. (2022), *Protein Science* 31(12):e4497. doi:10.1002/pro.4497

**Solubility prediction (Step 3a)**

- **DeepSoluE** - https://github.com/wangchao-malab/DeepSoluE
  Wang & Zou (2023), *BMC Biology* 21:12. doi:10.1186/s12915-023-01510-8
- **SoluProt** - https://loschmidt.chemi.muni.cz/soluprot/
  Hon et al. (2021), *Bioinformatics* 37(1):23-28. doi:10.1093/bioinformatics/btaa1102
- **Protein-Sol** - https://protein-sol.manchester.ac.uk/software
  Hebditch et al. (2017), *Bioinformatics* 33(19):3098-3100. doi:10.1093/bioinformatics/btx345
- **USEARCH** - https://www.drive5.com/usearch/
  Edgar (2010), *Bioinformatics* 26(19):2460-2461. doi:10.1093/bioinformatics/btq461
- **TMHMM 2.0c** - https://services.healthtech.dtu.dk/services/TMHMM-2.0/
  Krogh et al. (2001), *Journal of Molecular Biology* 305(3):567-580. doi:10.1006/jmbi.2000.4315

**Stability prediction (Step 3b)**

- **BertThermo** - https://github.com/zhibinlv/BertThermo
  Pei et al. (2023), *Applied Sciences* 13(5):2858. doi:10.3390/app13052858
- **TemStaPro** - https://github.com/ievapudz/TemStaPro
  Pudziuvelyte et al. (2024), *Bioinformatics* 40(4):btae157. doi:10.1093/bioinformatics/btae157
- **ProLaTherm** - https://github.com/grimmlab/ProLaTherm
  Haselbeck et al. (2023), *NAR Genomics and Bioinformatics* 5(4):lqad087. doi:10.1093/nargab/lqad087

> Several tools above (MLCE/REBELOT, BepiPred-3.0, SoluProt, TMHMM) are
> free for academic use but distributed under non-commercial academic
> licenses. If you plan to use this pipeline for for-profit applications,
> verify each tool's license individually.

## 5. Boltz-2 module (optional, for Step 0)

Required only if you want to start from `.fasta` rather than `.pdb`.
If you already have all your structures as PDB files, skip this section
and run the pipeline with `--no-boltz`.

### Architecture

Step 0 is implemented by the Python script `script/structure_predictor.py`,
which performs a **hierarchical 3D structure retrieval**:

1. **Local PDB search.** MMseqs2 searches the input sequence against a
   local PDB database. If a match passes the identity/coverage thresholds,
   the corresponding structure is downloaded from RCSB and verified by
   pairwise alignment.
2. **(Optional) UniProt + AlphaFold lookup.** If the previous step fails
   and a UniProt MMseqs2-formatted database is available, the script
   searches there. On match, it queries the AlphaFold DB API to fetch the
   pre-computed model (pLDDT >= 75 required).
3. **De novo Boltz-2 prediction.** As a final fallback, Boltz-2 predicts
   the structure de novo using the ColabFold MSA server. The model with
   the highest `confidence_score` (>= 0.8) is selected.

The script `structure_predictor.py` is a derivative work based on
[`biochorl/Structure_input_library`](https://github.com/biochorl/Structure_input_library)
(MIT licensed), adapted for this pipeline.

The script runs natively in the `vs_immunohub` conda env (which provides
Biopython); Boltz-2 is invoked as a subprocess in its own `boltz` env via
`conda run -n boltz`. **No Docker is required.**

### Required dependencies

#### a. Conda env `boltz`

```bash
conda env create -f envs/boltz.yml
conda activate boltz
boltz --version       # verify
conda deactivate
```

Boltz-2 official documentation: https://github.com/jwohlwend/boltz
Passaro et al. (2025), *bioRxiv*. doi:10.1101/2025.06.14.659707

#### b. MMseqs2 binary

Used for local database searches. Recommended location:
`$STRUCTURE_DIR/mmseqs/bin/mmseqs`. To install MMseqs2:

```bash
cd $STRUCTURE_DIR
wget https://mmseqs.com/latest/mmseqs-linux-avx2.tar.gz
tar xzf mmseqs-linux-avx2.tar.gz
rm mmseqs-linux-avx2.tar.gz
```

If installed elsewhere, override:

```bash
export MMSEQS_BIN=/opt/mmseqs/bin
```

Citation: Steinegger & Soding (2017), *Nature Biotechnology* 35(11):1026-1028. doi:10.1038/nbt.3988

#### c. Local PDB database (required for PDB lookup)

MMseqs2-formatted PDB database (~430 MB indexed). Build it once:

```bash
cd $STRUCTURE_DIR
wget https://files.rcsb.org/pub/pdb/derived_data/pdb_seqres.txt.gz
gunzip pdb_seqres.txt.gz
$MMSEQS_BIN/mmseqs createdb pdb_seqres.txt PDB
rm pdb_seqres.txt
```

If `PDB_DB` is not set or the path does not exist, the PDB lookup is
skipped and the script proceeds directly to UniProt or Boltz.

#### d. (Optional) Local UniProt database

Required only if you want the AlphaFold lookup path. Two options:

- **UniProtKB-SwissProt** (~290 MB FASTA, ~500 MB indexed): the manually
  curated subset of UniProt. **Recommended for most users.**
  ```bash
  cd $STRUCTURE_DIR
  wget https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz
  gunzip uniprot_sprot.fasta.gz
  $MMSEQS_BIN/mmseqs createdb uniprot_sprot.fasta UniProtKB-SwissProt
  rm uniprot_sprot.fasta
  ```

- **UniProtKB-TrEMBL** (~250 GB indexed): the complete unreviewed subset.
  Far larger, only for maximum coverage.
  ```bash
  cd $STRUCTURE_DIR
  wget https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_trembl.fasta.gz
  gunzip uniprot_trembl.fasta.gz
  $MMSEQS_BIN/mmseqs createdb uniprot_trembl.fasta UniProtKB-TrEMBL
  rm uniprot_trembl.fasta
  ```

To enable the AlphaFold lookup, set `UNIPROT_DB` in `script/config.sh`:

```bash
export UNIPROT_DB=$STRUCTURE_DIR/UniProtKB-SwissProt
```

If `UNIPROT_DB` is not set or its path does not exist, the AlphaFold
lookup is **skipped** and the script proceeds directly from PDB lookup
to Boltz-2 fallback. This is the **default** behaviour.

### Default directory layout

```
$STRUCTURE_DIR/                              (default: ~/Structure_input_library/)
├── mmseqs/bin/mmseqs                        # MMseqs2 binary
├── PDB                                      # PDB database (MMseqs2-formatted, ~430 MB)
├── PDB.dbtype, PDB.index, ...               # MMseqs2 index files
├── PDB_h, PDB_h.dbtype, PDB_h.index         # MMseqs2 headers
├── PDB.lookup, PDB.source, PDB.version
├── UniProtKB-SwissProt                      # (optional, ~500 MB)
└── ... (other index files for UniProt DB)
```

### Runtime requirements

- **Internet connection.** The pipeline contacts:
  - `api.colabfold.com` (MSA generation, Boltz step)
  - `alphafold.ebi.ac.uk` (AlphaFold DB models)
  - `files.rcsb.org` (PDB structure download)

  Quick connectivity check:
  ```bash
  curl -sS --max-time 10 -o /dev/null -w "ColabFold:  HTTP %{http_code}\n" https://api.colabfold.com/
  curl -sS --max-time 10 -o /dev/null -w "AlphaFold:  HTTP %{http_code}\n" https://alphafold.ebi.ac.uk/
  curl -sS --max-time 10 -o /dev/null -w "RCSB:       HTTP %{http_code}\n" https://files.rcsb.org/
  ```

  Any non-zero HTTP response confirms the server is reachable.

- **CUDA-capable GPU (recommended).** Boltz-2 runs on CPU but is much
  faster on a GPU. The `boltz` env includes a CUDA-enabled PyTorch build.

### How Step 0 is invoked from the pipeline

`script/0a_structure_prediction.sh` activates the `vs_immunohub` env,
adds `$MMSEQS_BIN` to `PATH`, and for each `.fasta` in the input folder
calls:

```bash
python script/structure_predictor.py <fasta> \
    --pdb_db $PDB_DB \
    [--uniprot_db $UNIPROT_DB | --no_uniprot] \
    --boltz_env $CONDA_ENV_BOLTZ
```

The resulting `.pdb` is saved next to the original `.fasta`, so Step 1
picks it up as if provided by the user.

## 6. RF models

See [`../models/README.md`](../models/README.md).

## 7. Sanity checks

```bash
# Syntax check across all scripts
bash -n script/*.sh launcher.sh
python3 -c "import ast; [ast.parse(open(f).read()) for f in [
    'script/ag_score.py',
    'script/solubility_prediction.py',
    'script/stability_prediction.py',
    'script/structure_predictor.py'
]]"

# Inspect how the config resolves paths on your machine
bash -c 'source script/config.sh && env | grep -E "^(PIPELINE|CONDA|AMBER|MLCE|BEPIPRED|DEEPSOLUE|SOLUPROT|PROTEINSOL|BERTTHERMO|TEMSTAPRO|PROLATHERM|SOLUBILITY|STABILITY|REBELOT|STRUCTURE|MMSEQS|PDB_DB|UNIPROT)_" | sort'

# Verify Boltz is reachable from the boltz conda env (only for Step 0)
conda activate boltz
boltz --version
conda deactivate

# Verify Biopython is reachable from the main env
conda activate vs_immunohub
python -c "from Bio.PDB import PDBParser; print('Biopython OK')"
conda deactivate

# Try the pipeline end-to-end on the provided examples (skipping Boltz)
./script/0_run_pipeline.sh -i examples -o output_test --no-boltz -y
```