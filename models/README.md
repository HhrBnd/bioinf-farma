# Random Forest models

Pre-trained meta-learner models that aggregate the raw scores of the
individual solubility/stability predictors.

| File                       | Used by                     | Input                                                       | Output                       |
|----------------------------|-----------------------------|-------------------------------------------------------------|------------------------------|
| `best_rf_model.pkl`        | `solubility_prediction.py`  | 3 probabilities (DeepSoluE, SoluProt, ProteinSol)           | `predicted_solubility_score` |
| `best_rf_model_3tools.pkl` | `stability_prediction.py`   | 3 scores (TemStaPro, ProLaTherm, BertThermo)                | `predicted_stability_score`  |

Each `.pkl` contains a `(RandomForestClassifier, MinMaxScaler)` tuple
serialised with `joblib`.

## Usage

The models are included in the repository and are loaded automatically by
the pipeline. No action required.

## Configurable path

By default, `script/config.sh` looks for the models in this folder. If you
want to move them elsewhere (e.g. onto a shared filesystem or a mounted
bucket), export:

```bash
export MODELS_DIR=/opt/shared/bioinf-farma-models
# or file-by-file:
export SOLUBILITY_MODEL=/opt/models/best_rf_model.pkl
export STABILITY_MODEL=/opt/models/best_rf_model_3tools.pkl
```

## Sizes

- `best_rf_model.pkl`: ~20 MB
- `best_rf_model_3tools.pkl`: ~164 KB

Both are well under the git single-file limit (100 MB), so they are
committed directly — no git-lfs required.
