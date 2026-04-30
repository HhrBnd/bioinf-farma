# BIOINF-farma pipeline

**Computational pipeline to score protein antigens for vaccine development:
antigenicity, solubility, and thermal stability.**



**Part of the [![ImmunoHub](https://immunohub.it/wp-content/uploads/LogoImmunoHub-300x40.png)](https://immunohub.it/) consortium, 
[Bioinf-farma lab network](https://immunohub.it/bioinf-farma-lab-network/).**

>A web interface is publicly available at
[bioinf-farma.uninsubria.it](https://www.bioinf-farma.uninsubria.it).
> No installation required
> just upload your PDB or FASTA file.


## Pipeline overview

The pipeline accepts protein sequences (FASTA) or 3D structures (PDB)
and produces, for each input antigen, three machine-learning derived
scores:

| Score | Range | Tools combined |
|---|---|---|
| **Antigenicity** | 0 - 1 | MLCE / REBELOT / BEPPE + BepiPred-3.0 |
| **Solubility** | 0 - 1 | DeepSoluE + SoluProt + Protein-Sol -> RandomForest |
| **Thermal stability** | 0 - 1 | BertThermo + TemStaPro + ProLaTherm -> RandomForest |

### Steps

0. **Structure prediction (FASTA -> PDB).** Optional, only when the
   input is a sequence. Implemented as a **hierarchical retrieval**
   strategy by `script/structure_predictor.py`:
   1. MMseqs2 search against a **local PDB database** -> if a match
      passes identity/coverage thresholds, the matching structure is
      downloaded from RCSB.
   2. (Optional) MMseqs2 search against a **local UniProtKB database**
      (SwissProt or TrEMBL) -> on match, the corresponding **AlphaFold
      DB** model is fetched (pLDDT >= 75 required).
   3. Otherwise, **Boltz-2** predicts the structure de novo (MSA via the
      ColabFold remote server; confidence_score >= 0.8 required).

   **No Docker is required.** Boltz-2 runs natively in a conda env.
   See [`docs/INSTALL.md`](docs/INSTALL.md) section 5 for details.

1. **Structure preprocessing.** Remove hetero atoms, fix protonation,
   strip alternate locations (AmberTools' `pdb4amber`).

2. **Antigenicity prediction.**
   - **2a. Conformational epitopes** (structure-based) via MLCE/REBELOT
     and the BEPPE post-processor.
   - **2b. Linear epitopes** (sequence-based) via BepiPred-3.0.
   - The two scores are normalized and combined in `ag_score.py`.

3. **Solubility / Stability prediction.**
   - **3a. Solubility**: DeepSoluE + SoluProt + Protein-Sol; outputs
     aggregated by a pre-trained RandomForest.
   - **3b. Stability**: BertThermo + TemStaPro + ProLaTherm; outputs
     aggregated by a pre-trained RandomForest.

A final summary `combined_scores.tsv` reports the three scores per antigen.

## Requirements

- Linux (tested on Ubuntu 22.04+)
- Miniconda/Anaconda
- AMBER 24 / AmberTools 23+
- ~30 GB disk for tools and conda envs
- Optional: GPU (CUDA-capable) for faster Boltz-2 inference
- Optional: ~430 MB for the local PDB database; ~500 MB for the
  optional UniProtKB-SwissProt database (for the AlphaFold lookup path)

See [`docs/INSTALL.md`](docs/INSTALL.md) for the full setup guide.

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/HeatherBondi/bioinf-farma.git
cd bioinf-farma

# 2. Read the install guide and follow steps 1-5
less docs/INSTALL.md

# 3. Once installed, run on the provided examples (PDB inputs only)
./script/0_run_pipeline.sh -i examples -o output_test --no-boltz -y

# 4. Inspect results
cat output_test/combined_scores.tsv
```

## Repository layout

```
bioinf-farma/
├── README.md                   # this file
├── LICENSE                     # AGPL-3.0-or-later
├── launcher.sh                 # one-liner to run the pipeline interactively
├── script/                     # pipeline scripts
│   ├── config.sh               # central configuration (paths, conda envs)
│   ├── 0_run_pipeline.sh       # main orchestrator
│   ├── 0a_structure_prediction.sh
│   ├── structure_predictor.py  # hierarchical structure retrieval (Step 0)
│   ├── 1_pdb_to_fasta.sh       # AMBER preprocessing
│   ├── 2a_epitope_prediction.sh
│   ├── 2b_bepipred_prediction.sh
│   ├── 2c_ag_score.sh
│   ├── ag_score.py
│   ├── 3a_solubility_prediction.sh
│   ├── solubility_prediction.py
│   ├── 3b_stability_prediction.sh
│   ├── stability_prediction.py
│   └── 3_feature_prediction.sh # combined_score aggregator
├── envs/                       # conda env specifications (.yml)
├── models/                     # pre-trained RandomForest models
├── examples/                   # example inputs (PDB and FASTA)
└── docs/                       # documentation
    └── INSTALL.md              # detailed installation guide
```

## Third-party tools

The pipeline integrates several third-party scientific tools, each
distributed under its own license. See [`docs/INSTALL.md`](docs/INSTALL.md)
for the full list, sources, and citations.

For Step 0 (structure prediction), this pipeline uses an adapted
version of `structure_predictor.py` from the
[`biochorl/Structure_input_library`](https://github.com/biochorl/Structure_input_library)
repository (MIT licensed). The adapted version, distributed in this
repository under `script/structure_predictor.py`, removes hardcoded
paths, adds an `--no_uniprot` flag, and refactors execution so that
Boltz-2 is invoked as a subprocess (no Docker required).

The optional **UniProtKB** database used by the AlphaFold lookup path
is **not bundled** with this repository. Users who want to enable that
path must download and index it themselves; see
[`docs/INSTALL.md`](docs/INSTALL.md) section 5.d.

## Known limitations

- **Boltz-2 requires internet** to query the ColabFold MSA server, the
  AlphaFold DB API, and the RCSB Protein Data Bank. The pipeline cannot
  predict structures fully offline. If you have all your structures as
  PDB files already, run the pipeline with `--no-boltz` to skip Step 0
  entirely.
- **Some third-party tools are licensed for academic use only.** See
  [`docs/INSTALL.md`](docs/INSTALL.md) for details.
- **Only single-chain proteins are supported** in the current release.
  Multimers, post-translational modifications and ligands are not
  modeled.

## License

This pipeline is distributed under the
[AGPL-3.0-or-later](LICENSE) license.

The third-party tools integrated by the pipeline retain their original
licenses; users are responsible for complying with each.

## Contact

- **Heather Bondi** - heather.bondi@uninsubria.it - Department of Science and High Technology, University of Insubria, Como, Italy
- **Gianluca Molla** - gianluca.molla@uninsubria.it - Department of Biotechnology and Life Sciences, University of Insubria, Varese, Italy 




## Acknowledgments

This work has been carried out within the [ImmunoHUB](https://immunohub.it)
consortium, funded by the European Union - NextGenerationEU through the
Italian Ministry of University and Research (MUR) under the National
Recovery and Resilience Plan (PNRR).