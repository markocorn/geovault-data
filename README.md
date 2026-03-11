# GeoVault Paper Data + Scripts (Public)

This folder is prepared as a standalone public repository package for the GeoVault paper.

## Contents

- `data/` — CSV datasets used in the paper
  - `data/argon2_*` summary and raw sweep files
  - `data/experiments/bip39/` raw BIP-39 benchmark outputs
  - `data/experiments/w3w_nokdf/` raw no-KDF benchmark outputs
  - `data/experiments/w3w_argon2/` raw Argon2 benchmark outputs
- `scripts/` — reproducibility scripts
  - `scripts/shell/` benchmark runners (`.sh`)
  - `scripts/matlab/` analysis/plot scripts (`.m`)
  - `scripts/README_source.md` original benchmark environment notes

## Scope

- Includes CSV data and scripts required to reproduce benchmark processing and figures.
- Excludes manuscript/build artifacts and unrelated workspace files.

## Quick Start

1. Ensure required tools are installed (`bash`, `hashcat`, MATLAB/Octave as needed).
2. Run shell benchmarks from `scripts/shell/`.
3. Run analysis/plot scripts from `scripts/matlab/`.
4. Compare generated outputs to CSV files in `data/`.

## Publish

1. Create a new public Git repository.
2. Copy this folder’s contents into that repo root.
3. Commit and push.
4. Add `LICENSE` and `CITATION.cff` (recommended).
