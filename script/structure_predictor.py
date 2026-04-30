#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
structure_predictor.py - Step 0 of the BIOINF-farma pipeline.

Hierarchical 3D structure retrieval and de novo prediction with Boltz-2.

For each input FASTA, the script tries the following strategies in order:

  1. MMseqs2 search against a local PDB database
       -> if a match passes the identity/coverage thresholds, the matching
          structure is downloaded from RCSB, aligned, and truncated.
  2. MMseqs2 search against a local UniProtKB-TrEMBL database (skipped with
     --no_uniprot)
       -> if a match is found, the corresponding AlphaFold model is fetched
          from the AlphaFold DB API (pLDDT >= 75 required).
  3. De novo prediction with Boltz-2 (running natively in a conda env, MSA
     generated remotely via the ColabFold server). The model with the highest
     confidence_score (>= 0.8) is selected.

For PDB/CIF input, the first chain is extracted and saved as a PDB.

ARCHITECTURE
The script runs end-to-end in the main pipeline env (default: vs_immunohub),
which provides Biopython, requests, and Python. MMseqs2 is invoked as an
external command (must be in PATH). Boltz-2 is invoked as a subprocess in
its own conda env via 'conda run -n <env>'.

Originally based on 'structure_predictor.py' from
    https://github.com/biochorl/Structure_input_library
    Copyright (c) Marco Marchetti - Licensed under the MIT License.

Adapted for the BIOINF-farma pipeline (Universita degli Studi dell'Insubria,
ImmunoHUB consortium, 2026): removed hardcoded paths, added --no_uniprot,
refactored so Biopython is only needed in the main env.
"""

import os
import sys
import argparse
import subprocess
import shutil
import requests
import json
import datetime
import gzip
from glob import glob

try:
    from Bio import SeqIO, Align
    from Bio.PDB import PDBParser, PDBIO, Select
    from Bio.PDB.MMCIFParser import MMCIFParser
except ImportError:
    print("ERROR: Biopython is not installed in the current Python env.\n"
          "       Run this script from a conda env that provides Biopython "
          "(e.g. vs_immunohub).",
          file=sys.stderr)
    sys.exit(1)

BOLTZ_CONDA_ENV = os.environ.get("BOLTZ_CONDA_ENV", "boltz")

RESIDUE_MAP = {
    "ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D", "CYS": "C", "GLN": "Q",
    "GLU": "E", "GLY": "G", "HIS": "H", "ILE": "I", "LEU": "L", "LYS": "K",
    "MET": "M", "PHE": "F", "PRO": "P", "SER": "S", "THR": "T", "TRP": "W",
    "TYR": "Y", "VAL": "V",
}


class Logger:
    def __init__(self, log_file_path):
        self.terminal = sys.stdout
        self.log_file = open(log_file_path, "w")

    def write(self, message):
        self.terminal.write(message)
        if message.strip():
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            self.log_file.write("[{}] {}\n".format(timestamp, message.rstrip()))

    def flush(self):
        self.terminal.flush()
        self.log_file.flush()

    def __del__(self):
        if not self.log_file.closed:
            self.log_file.close()
        sys.stdout = self.terminal


class ChainSelect(Select):
    def __init__(self, chain_id):
        self.chain_id = chain_id

    def accept_chain(self, chain):
        return chain.get_id() == self.chain_id


class ResidueSelect(Select):
    def __init__(self, chain_id, start, end):
        self.chain_id = chain_id
        self.start = start
        self.end = end

    def accept_chain(self, chain):
        return chain.get_id() == self.chain_id

    def accept_residue(self, residue):
        if residue.get_id()[0] != " ":
            return False
        return self.start <= residue.get_id()[1] <= self.end


def _get_parser(pdb_path):
    if pdb_path.endswith((".cif", ".mmcif")):
        return MMCIFParser(QUIET=True)
    return PDBParser(QUIET=True)


def extract_seq_from_pdb(pdb_path, chain_id):
    print("[INFO] Extracting sequence from chain '{}' of structure file...".format(chain_id))
    parser = _get_parser(pdb_path)
    try:
        try:
            structure = parser.get_structure("s", pdb_path)
        except (UnicodeDecodeError, IsADirectoryError):
            with gzip.open(pdb_path, "rt") as f:
                gz_parser = _get_parser(pdb_path)
                structure = gz_parser.get_structure("s", f)

        chain = structure[0][chain_id]
        seq = [
            RESIDUE_MAP.get(r.get_resname().strip().upper(), "X")
            for r in chain.get_residues()
            if r.get_id()[0] == " "
        ]
        return "".join(seq)
    except Exception as e:
        print("ERROR while extracting sequence from PDB: {}".format(e))
        return None


def align_and_verify(query_seq, target_seq, min_identity, min_coverage):
    print("\n" + "=" * 35)
    print("  STARTING PAIRWISE ALIGNMENT")
    print("=" * 35)
    aligner = Align.PairwiseAligner()
    aligner.mode = "local"
    aligner.match_score = 2
    aligner.mismatch_score = -1
    aligner.open_gap_score = -0.5
    aligner.extend_gap_score = -0.1

    alignments = aligner.align(query_seq, target_seq)
    if not alignments:
        return False, 0, 0, None, None

    best_alignment = alignments[0]
    print("\n[Best alignment]:\n" + str(best_alignment))

    aligned_q, aligned_t = best_alignment
    matches, alignment_len_no_gaps, query_aligned_len = 0, 0, 0
    t_start_index, t_end_index, t_res_count = -1, -1, 0

    for q_char, t_char in zip(aligned_q, aligned_t):
        if q_char != "-":
            query_aligned_len += 1
        if t_char != "-":
            if t_start_index == -1:
                t_start_index = t_res_count
            t_end_index = t_res_count
            t_res_count += 1
        if q_char != "-" and t_char != "-":
            alignment_len_no_gaps += 1
            if q_char == t_char:
                matches += 1

    identity = (matches / alignment_len_no_gaps) * 100 if alignment_len_no_gaps > 0 else 0
    coverage = (query_aligned_len / len(query_seq)) * 100

    t_start_pdb, t_end_pdb = (
        (t_start_index + 1, t_end_index + 1) if t_start_index != -1 else (None, None)
    )

    print("\n" + "-" * 35)
    print("[Alignment results]")
    print("   - Identity: {:.2f}%".format(identity))
    print("   - Coverage: {:.2f}%".format(coverage))
    print("   - Aligned region in target PDB: residues {} - {}".format(t_start_pdb, t_end_pdb))
    print("-" * 35 + "\n")

    is_match = identity >= min_identity and coverage >= min_coverage
    if is_match:
        return True, identity, coverage, t_start_pdb, t_end_pdb
    return False, identity, coverage, None, None


def truncate_and_save_pdb(input_pdb_path, output_pdb_path, chain_id, start, end):
    print("[INFO] Truncating model (residues: {}-{}, chain: {})...".format(start, end, chain_id))
    parser = _get_parser(input_pdb_path)
    try:
        try:
            structure = parser.get_structure("full_model", input_pdb_path)
        except (UnicodeDecodeError, IsADirectoryError):
            with gzip.open(input_pdb_path, "rt") as f:
                gz_parser = _get_parser(input_pdb_path)
                structure = gz_parser.get_structure("full_model", f)
        io = PDBIO()
        io.set_structure(structure)
        io.save(output_pdb_path, ResidueSelect(chain_id, start, end))
        print("[OK] Truncated model saved: {}".format(output_pdb_path))
        return True
    except Exception as e:
        print("ERROR while truncating: {}".format(e), file=sys.stderr)
        shutil.copy(input_pdb_path, output_pdb_path)
        return False


def cif_to_pdb(cif_path, pdb_path, chain_id=None):
    parser = MMCIFParser(QUIET=True)
    try:
        structure = parser.get_structure("s", cif_path)
        if chain_id is None:
            chain_id = next(structure[0].get_chains()).id
        io = PDBIO()
        io.set_structure(structure)
        io.save(pdb_path, ChainSelect(chain_id))
        print("[OK] Chain '{}' saved to: {}".format(chain_id, pdb_path))
        return True
    except Exception as e:
        print("ERROR while converting CIF to PDB: {}".format(e), file=sys.stderr)
        return False


def process_pdb_file(pdb_path, output_path):
    print("[INFO] Processing structure file: {}".format(pdb_path))
    parser = _get_parser(pdb_path)
    try:
        structure = parser.get_structure("s", pdb_path)
        chain = next(structure[0].get_chains())
        io = PDBIO()
        io.set_structure(structure)
        io.save(output_path, ChainSelect(chain.id))
        print("[OK] Chain '{}' saved to: {}".format(chain.id, output_path))
        return True
    except Exception as e:
        print("ERROR while processing PDB/CIF: {}".format(e), file=sys.stderr)
        return False


def check_mmseqs_availability():
    if not shutil.which("mmseqs"):
        sys.exit("ERROR: 'mmseqs' not found. Please install MMseqs2 and add "
                 "its 'bin' directory to PATH.")
    print("[OK] Command 'mmseqs' found.")


def build_uniprot_search_params(sensitivity):
    sensitivity = max(1.0, min(8.5, float(sensitivity)))
    if sensitivity <= 2.0:
        kmer, max_seqs, max_accept, max_rejected = 7, 10, 1, 10
    elif sensitivity <= 4.0:
        kmer, max_seqs, max_accept, max_rejected = 6, 50, 5, 50
    elif sensitivity <= 6.0:
        kmer, max_seqs, max_accept, max_rejected = 6, 150, 10, 100
    else:
        kmer, max_seqs, max_accept, max_rejected = 6, 300, 50, 300
    return [
        "-s", str(sensitivity),
        "-k", str(kmer),
        "--max-seqs", str(max_seqs),
        "--max-accept", str(max_accept),
        "--max-rejected", str(max_rejected),
    ]


def parse_fasta(fasta_path):
    try:
        record = next(SeqIO.parse(fasta_path, "fasta"))
        return str(record.seq).upper(), len(record.seq)
    except Exception as e:
        sys.exit("ERROR while reading FASTA: {}".format(e))


def run_mmseqs_search(temp_fasta, query_len, db_path, temp_dir,
                     min_identity, min_coverage, extra_params=None):
    db_name = os.path.basename(db_path)
    print("\n[INFO] Running MMseqs2 search against '{}'...".format(db_name))
    out_m8 = os.path.join(temp_dir, "search_{}.m8".format(db_name))
    tmp_mmseqs = os.path.join(temp_dir, "mmseqs_tmp_{}".format(db_name))
    os.makedirs(tmp_mmseqs, exist_ok=True)
    command = [
        "mmseqs", "easy-search", temp_fasta, db_path, out_m8, tmp_mmseqs,
        "--format-output", "target,pident,alnlen,qlen,tlen,tstart,tend",
    ]
    if extra_params:
        command.extend(extra_params)
    try:
        subprocess.run(command, capture_output=True, text=True, check=True)
        if not os.path.exists(out_m8):
            print("MMseqs2 produced no results.")
            return None
        with open(out_m8) as f:
            hits = f.read().strip().split("\n")
        if not hits or not hits[0]:
            print("MMseqs2 produced no results.")
            return None
        for line in hits:
            parts = line.split("\t")
            if len(parts) < 7:
                continue
            sseqid, pident, align_len, qlen, slen, sstart, send = parts
            coverage = (int(align_len) / query_len) * 100
            if float(pident) >= min_identity and coverage >= min_coverage:
                print("[OK] Match found in {}: {}".format(db_name, sseqid.strip()))
                return (sseqid.strip(), int(sstart), int(send))
        print("\n[X] No match in {} passed the thresholds.".format(db_name))
        return None
    except subprocess.CalledProcessError as e:
        print("ERROR MMseqs2 (exit code {})".format(e.returncode), file=sys.stderr)
        if e.stderr:
            print("  stderr: {}".format(e.stderr.strip()), file=sys.stderr)
        return None
    except Exception as e:
        print("ERROR MMseqs2: {}".format(e), file=sys.stderr)
        return None


def download_pdb_file(pdb_id, output_path, source="rcsb"):
    url = {
        "rcsb": "https://files.rcsb.org/download/{}.pdb".format(pdb_id),
        "alphafold": "https://alphafold.ebi.ac.uk/files/AF-{}-F1-model_v4.pdb".format(pdb_id),
    }.get(source)
    print("[INFO] Downloading PDB from {}...".format(url))
    try:
        with requests.get(url, stream=True, timeout=60) as r:
            r.raise_for_status()
            with open(output_path, "wb") as f:
                shutil.copyfileobj(r.raw, f)
            print("[OK] File saved to: {}".format(output_path))
            return True
    except requests.exceptions.RequestException as e:
        print("ERROR: download failed. {}".format(e), file=sys.stderr)
        return False


def get_alphafold_structure(uniprot_id, output_path):
    api_url = "https://alphafold.ebi.ac.uk/api/prediction/{}".format(uniprot_id)
    print("\n[INFO] Querying AlphaFold DB: {}...".format(api_url))
    try:
        res = requests.get(api_url, timeout=60)
        if res.status_code != 200:
            print("[X] API request failed (status: {})".format(res.status_code), file=sys.stderr)
            return False
        try:
            prediction_data = res.json()
        except requests.exceptions.JSONDecodeError:
            print("[X] API response is not valid JSON.", file=sys.stderr)
            return False
        if not prediction_data:
            print("[X] API returned an empty response.", file=sys.stderr)
            return False
        entry_data = prediction_data[0]
        model_url = entry_data.get("pdbUrl") or entry_data.get("cifUrl")
        avg_plddt = entry_data.get("globalMetricValue")
        if not model_url or avg_plddt is None:
            print("[X] API response missing model URL or pLDDT score.", file=sys.stderr)
            return False
        print("[INFO] AlphaFold DB pLDDT: {:.2f}".format(avg_plddt))
        if avg_plddt >= 75:
            print("[OK] Model meets quality criteria (pLDDT >= 75).")
            with requests.get(model_url, stream=True, timeout=60) as r:
                r.raise_for_status()
                with open(output_path, "wb") as f:
                    shutil.copyfileobj(r.raw, f)
                print("[OK] File saved to: {}".format(output_path))
                return True
        print("[X] Model below pLDDT threshold.")
        return False
    except Exception as e:
        print("ERROR during AlphaFold DB API call: {}".format(e), file=sys.stderr)
        return False


def run_boltz(fasta_path, final_output_path, boltz_output_dir,
              boltz_conda_env, diffusion_samples=5):
    print("\n[INFO] Starting Boltz-2 prediction (conda env: {}, MSA via ColabFold)...".format(boltz_conda_env))
    if os.path.exists(boltz_output_dir):
        shutil.rmtree(boltz_output_dir)
    os.makedirs(boltz_output_dir, exist_ok=True)
    try:
        record = next(SeqIO.parse(fasta_path, "fasta"))
        temp_fasta_path = os.path.join(boltz_output_dir, "temp_input.fasta")
        with open(temp_fasta_path, "w") as temp_f:
            temp_f.write(">A|protein\n{}\n".format(record.seq))

        command = [
            "conda", "run", "-n", boltz_conda_env, "--no-capture-output",
            "boltz", "predict", os.path.abspath(temp_fasta_path),
            "--use_potentials",
            "--diffusion_samples", str(diffusion_samples),
            "--use_msa_server",
        ]
        result = subprocess.run(command, check=False, capture_output=True,
                                text=True, timeout=3600, cwd=boltz_output_dir)
        if result.returncode != 0:
            print("ERROR Boltz: subprocess returned non-zero exit code.", file=sys.stderr)
            print("  stdout (last lines): {}".format(result.stdout[-500:]), file=sys.stderr)
            print("  stderr (last lines): {}".format(result.stderr[-500:]), file=sys.stderr)
            return False

        prediction_base_dir = os.path.join(
            boltz_output_dir,
            "boltz_results_{}".format(os.path.splitext(os.path.basename(temp_fasta_path))[0]),
            "predictions",
            os.path.splitext(os.path.basename(temp_fasta_path))[0],
        )
        score_files = glob(os.path.join(prediction_base_dir, "confidence_*.json"))
        if not score_files:
            print("ERROR Boltz: no confidence files produced.", file=sys.stderr)
            return False
        ranked_models = sorted(
            [
                (json.load(open(f)).get("confidence_score"),
                 f.replace("confidence_", "").replace(".json", ".cif"))
                for f in score_files
            ],
            reverse=True,
        )
        best_score, best_model_file = ranked_models[0]
        print("\n[INFO] Best confidence score: {:.4f}".format(best_score))
        if best_score >= 0.8:
            print("[OK] Model meets quality criteria.")
            return cif_to_pdb(best_model_file, final_output_path)
        print("[X] INSUFFICIENT QUALITY (confidence < 0.8).")
        return False
    except Exception as e:
        print("ERROR Boltz: {}".format(e), file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Hierarchical 3D structure retrieval and de novo prediction.",
    )
    parser.add_argument("input_file",
                        help="Input file (.fasta, .fa, .pdb, .cif).")
    parser.add_argument("--min_identity", type=float, default=99.0)
    parser.add_argument("--min_coverage", type=float, default=99.0)
    parser.add_argument("--pdb_db", type=str, default=None)
    parser.add_argument("--uniprot_db", type=str, default=None)
    parser.add_argument("--no_uniprot", action="store_true")
    parser.add_argument("--uniprot_sensitivity", type=float, default=1.0)
    parser.add_argument("--boltz_env", type=str, default=BOLTZ_CONDA_ENV)
    parser.add_argument("--diffusion_samples", type=int, default=5)
    args = parser.parse_args()

    input_path = os.path.abspath(args.input_file)
    base_name = os.path.splitext(os.path.basename(input_path))[0]
    output_dir = os.path.dirname(input_path)
    output_pdb_path = os.path.join(output_dir, "{}.pdb".format(base_name))
    log_file = os.path.join(output_dir, "{}_report.log".format(base_name))

    sys.stdout = Logger(log_file)

    print("[OK] Running in env: {}".format(os.environ.get("CONDA_DEFAULT_ENV", "system")))

    temp_dir = os.path.join(output_dir, "{}_temp_files".format(base_name))
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir, exist_ok=True)

    print("Processing: {}".format(os.path.basename(input_path)))

    if input_path.endswith((".pdb", ".cif")):
        process_pdb_file(input_path,
                         os.path.join(output_dir, "{}_chain1.pdb".format(base_name)))
        try:
            shutil.rmtree(temp_dir)
        except FileNotFoundError:
            pass
        return

    if not input_path.endswith((".fasta", ".fa")):
        sys.exit("ERROR: unsupported input format: {}".format(input_path))

    check_mmseqs_availability()
    sequence, seq_len = parse_fasta(input_path)
    print("Sequence read: {} aa.".format(seq_len))

    temp_query_fasta = os.path.join(temp_dir, "query.fasta")
    with open(temp_query_fasta, "w") as f_out:
        f_out.write(">query\n{}\n".format(sequence))

    if args.pdb_db:
        pdb_db = os.path.abspath(args.pdb_db)
        pdb_hit = run_mmseqs_search(temp_query_fasta, seq_len, pdb_db,
                                    temp_dir, args.min_identity,
                                    args.min_coverage)
        if pdb_hit:
            sseqid, _, _ = pdb_hit
            parts = sseqid.replace("_", "|").split("|")
            if len(parts) >= 2:
                pdb_code, chain_id = parts[-2][:4].lower(), parts[-1]
                if len(pdb_code) == 4:
                    temp_pdb_path = os.path.join(temp_dir, "{}.pdb".format(pdb_code))
                    if download_pdb_file(pdb_code, temp_pdb_path, source="rcsb"):
                        pdb_seq = extract_seq_from_pdb(temp_pdb_path, chain_id)
                        if pdb_seq:
                            is_match, identity, coverage, start, end = align_and_verify(
                                sequence, pdb_seq, args.min_identity, args.min_coverage)
                            if is_match:
                                truncate_and_save_pdb(temp_pdb_path, output_pdb_path,
                                                      chain_id, start, end)
                                print("\n[DONE]")
                                shutil.rmtree(temp_dir)
                                sys.exit(0)
    else:
        print("\n(--pdb_db not provided: skipping PDB local search.)")

    if not args.no_uniprot and args.uniprot_db:
        uniprot_db = os.path.abspath(args.uniprot_db)
        uniprot_params = build_uniprot_search_params(args.uniprot_sensitivity)
        uniprot_hit = run_mmseqs_search(temp_query_fasta, seq_len, uniprot_db,
                                        temp_dir, args.min_identity,
                                        args.min_coverage,
                                        extra_params=uniprot_params)
        if uniprot_hit:
            uniprot_id, _, _ = uniprot_hit
            uniprot_acc = uniprot_id.split("|")[1] if "|" in uniprot_id else uniprot_id
            temp_pdb_path = os.path.join(temp_dir, "AF-{}.pdb".format(uniprot_acc))
            if get_alphafold_structure(uniprot_acc, temp_pdb_path):
                alphafold_seq = extract_seq_from_pdb(temp_pdb_path, "A")
                if alphafold_seq:
                    is_match, identity, coverage, start, end = align_and_verify(
                        sequence, alphafold_seq, args.min_identity, args.min_coverage)
                    if is_match:
                        truncate_and_save_pdb(temp_pdb_path, output_pdb_path,
                                              "A", start, end)
                        print("\n[DONE]")
                        shutil.rmtree(temp_dir)
                        sys.exit(0)
    else:
        if args.no_uniprot:
            print("\n(--no_uniprot: skipping UniProt/AlphaFold lookup.)")
        else:
            print("\n(--uniprot_db not provided: skipping UniProt/AlphaFold lookup.)")

    boltz_results_dir = os.path.join(output_dir, "{}_boltz_results".format(base_name))
    if run_boltz(input_path, output_pdb_path, boltz_results_dir,
                 boltz_conda_env=args.boltz_env,
                 diffusion_samples=args.diffusion_samples):
        print("\n[DONE]")
        try:
            shutil.rmtree(temp_dir)
        except FileNotFoundError:
            pass
        sys.exit(0)

    print("\n[FAIL] Operation failed.", file=sys.stderr)
    try:
        shutil.rmtree(temp_dir)
    except FileNotFoundError:
        pass
    sys.exit(1)


if __name__ == "__main__":
    main()