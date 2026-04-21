# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 [Your Name / Organization]
# -*- coding: utf-8 -*-

import sys
import joblib
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import MinMaxScaler

# Verifica che siano stati passati due argomenti
if len(sys.argv) != 3:
    print("Usage: python solubility_prediction.py <path_to_solubility_scores.csv> <path_to_model.pkl>")
    sys.exit(1)

# Leggi gli argomenti da riga di comando
dataset_path = sys.argv[1]  # Percorso del file solubility_scores.csv
model_path = sys.argv[2]   # Percorso del modello (best_rf_model.pkl)

# 1. Carica il modello e lo scaler
solubility_model, scaler = joblib.load(model_path)

# 2. Carica il nuovo dataset
data = pd.read_csv(dataset_path)

# Seleziona solo le colonne di caratteristiche necessarie
feature_indices = [1, 2, 3]  # Assicurati che questi siano gli indici corretti
X = data.iloc[:, feature_indices]

# 3. Preprocessing dei dati: applica lo scaler
X_scaled = scaler.transform(X)
X_scaled = pd.DataFrame(X_scaled, columns=X.columns)

# 4. Effettua le previsioni utilizzando il modello
predictions = solubility_model.predict(X_scaled)
new_probabilities = solubility_model.predict_proba(X_scaled)[:, 1]

# 5. Crea un DataFrame per i punteggi predetti
results = pd.DataFrame({
    'sequence': data.iloc[:, 0],  # Sequenza
    'predicted_solubility_score': new_probabilities  # Punteggio di solubilità predetto
})

# Salva i risultati in un CSV
results.to_csv(f"{dataset_path}_predicted_scores.csv", index=False)