# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 [Your Name / Organization]
import pandas as pd
import numpy as np
import os
import sys

WINDOW_SIZE = 7 

def compute_density_scores(df, window_size):
    """Calcola due score di densità per ogni residuo."""
    scores = ['BEPPE', 'BepiPred']
    #kernel = np.exp(-np.linspace(-1.5, 1.5, 2 * window_size + 1)**2)  # Kernel gaussiano
    kernel = np.exp(-np.linspace(-2, 2, 2 * window_size + 1))  # kernel esponenziale
    kernel /= kernel.sum()  # Normalizzazione
    
    for score in scores:
        df[f'{score}_Density'] = df[score].rolling(window=2 * window_size + 1, center=True, min_periods=1).mean()
        df[f'{score}_KernelDensity'] = (
            df[score].rolling(window=2 * window_size + 1, center=True, min_periods=1)
            .apply(lambda x: np.sum(x * kernel[:len(x)]), raw=True)
        )
    
    return df

def adjust_non_epitope_scores(df, window_size):
    """Evita che un residuo non epitopico abbia un punteggio maggiore di un epitopo vicino, separatamente per BEPPE e BepiPred."""
    scores = ["density_based_antigenicity_score", "kernel_based_antigenicity_score"]
    
    for predictor in ["BEPPE", "BepiPred"]:  # Cicla separatamente su BEPPE e BepiPred
        for score in scores:
            if score in df.columns:  # **Verifica che la colonna esista**
                # Trova il massimo score antigenico locale SOLO per i residui con BEPPE = 1 o BepiPred = 1 (separatamente)
                max_epitope_score = df[score].where(df[predictor] > 0).rolling(window=2 * window_size + 1, center=True).max()
                max_epitope_score = max_epitope_score.fillna(0)  

                # Applica la correzione SOLO ai residui non epitopici per il predittore corrente
                df[score] = np.where(
                    (df[predictor] == 0),  # Ora correggiamo BEPPE e BepiPred separatamente
                    np.minimum(df[score], max_epitope_score),  # Limita il valore massimo al massimo vicino
                    df[score]  # Mantieni il valore originale se è epitopo
                )
    
    return df


def process_data(csv_path, log_path, output_dir, pdb_name, output_tsv, window_size):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)
    
    output_intermediate_path = os.path.join(output_dir, f"{pdb_name}_intermediate_results.csv")
    output_final_path = os.path.join(output_dir, f"{pdb_name}_final_results.csv")

    # **Controllo dei file di input**
    bepi_df = pd.read_csv(csv_path)
    if bepi_df.empty:
        print("Errore: Il file CSV è vuoto. Interruzione dello script.")
        return
    
       
    if "BepiPred-3.0 score" not in bepi_df.columns:
        print("Errore: La colonna 'BepiPred-3.0 score' non è presente nel CSV. Interruzione dello script.")
        return

    bepi_df["POS"] = range(1, len(bepi_df) + 1)

    # **Controllo del file log**
    beppe_positions = set()
    with open(log_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0].isdigit():
                beppe_positions.add(int(parts[0]))

    bepi_df["BEPPE"] = bepi_df["POS"].apply(lambda x: 1 if x in beppe_positions else 0)
    bepi_df["BepiPred"] = bepi_df["BepiPred-3.0 score"].apply(lambda x: 1 if x > 0.15 else 0)
    
    bepi_df = bepi_df.loc[:, ["POS", "Residue", "BEPPE", "BepiPred"]]
    
    # Calcola gli score di densità
    bepi_df = compute_density_scores(bepi_df, window_size)
    
    # **Forza i NaN a 0 prima di calcolare gli score antigenici**
    bepi_df.fillna(0, inplace=True)

    # Calcola gli score e aggiungili al DataFrame
    bepi_df["original_antigenicity_score"] = (bepi_df["BEPPE"] * 0.5 + bepi_df["BepiPred"] * 0.5)
    #bepi_df["density_based_antigenicity_score"] = ((bepi_df["BEPPE_Density"]** 2) * 0.5 + (bepi_df["BepiPred_Density"]** 2) * 0.5)
    #bepi_df["kernel_based_antigenicity_score"] = ((bepi_df["BEPPE_KernelDensity"]** 2) * 0.5 + (bepi_df["BepiPred_KernelDensity"]** 2) * 0.5)
    
    bepi_df["density_based_antigenicity_score"] = (bepi_df["BEPPE_Density"] * 0.5 + bepi_df["BepiPred_Density"] * 0.5)
    bepi_df["kernel_based_antigenicity_score"] = (bepi_df["BEPPE_KernelDensity"] * 0.5 + bepi_df["BepiPred_KernelDensity"] * 0.5)

    # **Ora possiamo riempire i NaN senza errori**
    bepi_df.fillna(0, inplace=True)

    # Estrai gli score per la scrittura nel file TSV
    original_antigenicity_score = bepi_df["original_antigenicity_score"].mean()
    density_based_score = bepi_df["density_based_antigenicity_score"].mean()
    kernel_based_score = bepi_df["kernel_based_antigenicity_score"].mean()

    # Applica la correzione per evitare che non-epitopi abbiano punteggi troppo alti
    #bepi_df = adjust_non_epitope_scores(bepi_df, window_size)

    # Salva la tabella finale
    bepi_df.to_csv(output_final_path, index=False)

    # Calcola la lunghezza della sequenza di amminoacidi
    sequence_length = len(bepi_df)

    # Scrivi i risultati nel file TSV, includendo la lunghezza della sequenza
    with open(output_tsv, 'a') as tsv_file:
        tsv_file.write(f"{pdb_name}\t{sequence_length}\t{original_antigenicity_score}\t{density_based_score}\t{kernel_based_score}\n")

    return sequence_length, original_antigenicity_score, density_based_score, kernel_based_score

if __name__ == "__main__":
    csv_path = sys.argv[1]
    log_path = sys.argv[2]
    output_dir = sys.argv[3]
    pdb_name = sys.argv[4]
    output_tsv = sys.argv[5]  
    
    process_data(csv_path, log_path, output_dir, pdb_name, output_tsv, WINDOW_SIZE)
