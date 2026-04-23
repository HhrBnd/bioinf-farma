# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2023-2026 Heather Bondi, Gianluca Molla, Università degli Studi dell'Insubria
# -*- coding: utf-8 -*-

import sys
import joblib
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler

# Definizione dei colori
RED = '\033[91m'
GREEN = '\033[92m'
RESET = '\033[0m'

# Verifica che siano stati passati due argomenti
if len(sys.argv) != 3:
    print("Usage: python stability_prediction.py <path_to_stability_scores.csv> <path_to_model.pkl>")
    sys.exit(1)

# Leggi gli argomenti da riga di comando
dataset_path = sys.argv[1]  # Percorso del file stability_scores.csv
model_path = sys.argv[2]   # Percorso del modello (best_rf_model_3tools.pkl)

# 1. Carica il modello e lo scaler
stability_model, scaler = joblib.load(model_path)

# 2. Carica il nuovo dataset (stability_scores.csv) con i punteggi dei tre tool
data = pd.read_csv(dataset_path)

# Seleziona solo le colonne di caratteristiche necessarie
# In questo caso, si presume che le colonne 1, 2, 3 siano i punteggi di TemStaPro, ProLaTherm, e BertThermo
feature_indices = [1, 2, 3]  # Assicurati che questi siano gli indici corretti
X = data.iloc[:, feature_indices]

# 3. Preprocessing dei dati: applica lo scaler
X_scaled = scaler.transform(X)
X_scaled = pd.DataFrame(X_scaled, columns=X.columns)

# 4. Effettua le previsioni utilizzando il modello di Random Forest
predictions = stability_model.predict(X_scaled)
new_probabilities = stability_model.predict_proba(X_scaled)[:, 1]

# 5. Stampa i risultati delle predizioni (commentato per evitare output eccessivo)
# for idx, (prediction, probability) in enumerate(zip(predictions, new_probabilities)):
#     sequence = data.iloc[idx, 0]  # Supponiamo che la sequenza proteica sia nella prima colonna
#     if prediction == 1:
#         print(f"{GREEN}Sequence: Thermophilic (Score: {probability:.2f}){RESET}")
#     else:
#         print(f"{RED}Sequence: Not Thermophilic (Score: {probability:.2f}){RESET}")

# 6. Crea un DataFrame per i punteggi predetti
results = pd.DataFrame({
    'sequence': data.iloc[:, 0],  # Sequenza
    'predicted_stability_score': new_probabilities  # Punteggio di stabilità predetto
})

# Salva i risultati in un CSV
results.to_csv(f"{dataset_path}_predicted_scores.csv", index=False)
