---
plan: 02-02
phase: 2
title: Factor-model family onto the degenerate-input contract
status: complete
requirements: [MODELS-01, MODELS-02, MODELS-03, MODELS-04]
completed: 2026-09-02
---

# Plan 02-02 Summary — Factor Models

## What was built

Migrated the factor-model family onto the Phase 1 degenerate-input contract, mirroring the MarketModel/MarketAdjusted exemplar established in Wave 1 (02-01).

- **LinearFactorModel$fit()** — added the insufficient-obs and zero/near-zero variance guards routed through `.handle_degenerate()`, with finite-only df via `.finite_residual_df()`. Because FF3/FF5/Carhart4 inherit `fit()` from LinearFactorModel, the fit-side guard is fixed once and inherited.
- **abnormal_returns() `.degenerate_handled` suppression** — added individually to each of the four overrides (LinearFactorModel, FamaFrench3FactorModel, FamaFrench5FactorModel, Carhart4FactorModel) so a degenerate event emits exactly one warning across the pipeline (no redundant "not fitted" warning).
- **Factor-data degenerate factory** — added to `helper-mock-data.R` for insufficient-obs and zero-variance factor inputs.
- **CONTRACT-05 baselines** — captured valid-input baselines for LinearFactorModel, FF3, FF5, Carhart4 (`tests/testthat/fixtures/contract05_{linearfactor,ff3,ff5,carhart4}_baseline.rds`) and asserted byte/near-identical (~1e-8) after migration.

## Tasks

| Task | Status | Commit |
|------|--------|--------|
| 1 — LinearFactorModel fit guard + FF3 branch + factory | complete | 7e7dc4f |
| 2 — FF5 + Carhart4 branches + per-model baselines | complete | cb01368 |

## Verification

- `test_models.R`: 278 pass, 0 fail, 0 error.
- `test_contract.R`: 0 fail, 0 error (Phase 1 contract behavior preserved).
- Per-model valid-input baselines match within 1e-8 — valid-input numerics unchanged (CONTRACT-05).

## Requirements

- MODELS-01 (guard insufficient obs): LinearFactorModel + inheritance ✓
- MODELS-02 (zero/near-zero variance → NA, not Inf/NaN): ✓
- MODELS-03 (finite-only df): `.finite_residual_df()` applied ✓
- MODELS-04 (FEC only where supported): factor models keep existing FEC path; math unchanged ✓

## Notes / Deviations

- The prior executor hit a session limit after completing task 2's code changes in the worktree but before committing them or writing this SUMMARY. The orchestrator verified the uncommitted work (test_models 278 pass / 0 fail), then committed it (`cb01368`) and authored this SUMMARY. No behavioral change was introduced beyond what the plan specified.
- ModelBase's `ss_market < .Machine$double.eps` FEC branch left untouched.
