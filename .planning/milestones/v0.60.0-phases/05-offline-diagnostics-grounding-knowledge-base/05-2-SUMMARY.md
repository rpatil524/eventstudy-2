---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: "02"
subsystem: knowledge-base
tags: [knowledge-base, grounding, citations, rule-engine, pure-r]
status: complete

dependency_graph:
  requires: ["05-01"]
  provides: ["es_kb", "EVENTSTUDY_KB", "knowledge_base.R"]
  affects: ["05-03", "Phase 7 LLM layer"]

tech_stack:
  added: []
  patterns:
    - Pure-R package-level list built at load time (zero new dependencies)
    - .kb_rule() constructor/validator pattern for type-safe rule construction
    - NA-safe condition predicates (all return FALSE on NA inputs, never error)
    - Structured citation list (author/year/key/venue) for Phase 7 prompt injection

key_files:
  created:
    - R/knowledge_base.R
    - tests/testthat/test_knowledge_base.R
    - man/es_kb.Rd
    - man/EVENTSTUDY_KB.Rd
  modified:
    - NAMESPACE

decisions:
  - "Added category field (stat_choice | robustness) to distinguish test-steering rules from data-quality rules — this enables recommend_stat() and flag_robustness() (Plan 05-3) to filter the KB by category without re-classifying rules at call time"
  - "KB-PRETREND omitted: no pretrend signal is available in the es_diagnostics list from Plan 05-1 (pretrend_test() requires separate call and is not harvested by es_diagnostics); noted in roxygen"
  - "KB-VAR-INCREASE-BMP operationalized via CAR IQR > 0.10 or SD > 0.15 (assumed thresholds): the diagnostic list provides car_iqr and car_sd from the cross_sectional section; BMP-vs-Patell divergence cannot be computed offline without both statistics being run"
  - "All condition predicates use isTRUE() wrapping to ensure length-1 logical output even if the inner expression returns NA"

metrics:
  duration_seconds: 277
  completed: "2026-09-03"
  tasks_completed: 2
  commits: 2

actuals:
  tokens: 15000
  tasks: 2
  commits: 2
---

# Phase 05 Plan 02: Grounding Knowledge Base Summary

Pure-R EVENTSTUDY_KB with 8 validated, cited rule records mapping es_diagnostics conditions to methodology recommendations, exported via es_kb() accessor, with 143 passing unit tests covering structural integrity and per-rule firing.

## What Was Built

### R/knowledge_base.R

- **`.kb_rule()`** — `@noRd` constructor that validates all required fields (id, category, condition, recommendation, citation, severity) and stops with a clear message on malformed input.
- **`EVENTSTUDY_KB`** — package-level list of 8 rule records built at load time via `.kb_rule()`. Each rule:
  - reads only fields documented in the `es_diagnostics` `@return`
  - guards NA with `is.na()` / `isTRUE()` so NA signals never fire a rule
  - carries a structured `citation` list (`author`, `year`, `key`, `venue`)
  - is assigned a `category` (`stat_choice` or `robustness`) enabling `recommend_stat()` / `flag_robustness()` filtering in Plan 05-3
- **`es_kb()`** — exported accessor returning `EVENTSTUDY_KB`; roxygen notes KB-04 injection is Phase 7.

### Rules implemented

| Rule ID | Category | Condition | Severity | Citations |
|---------|----------|-----------|----------|-----------|
| KB-NORM-PATELL | stat_choice | Shapiro-Wilk p > 0.05 in >= 70% events | info | Patell 1976 |
| KB-NONNORM-NONPAR | stat_choice | Shapiro-Wilk p < 0.05 in >= 50% events | warning | Brown & Warner 1985 |
| KB-VAR-INCREASE-BMP | stat_choice | CAR IQR > 0.10 or CAR SD > 0.15 | warning | BMP 1991 |
| KB-OVERLAP-KP | stat_choice | n_overlap_pairs > 0 | warning | Kolari & Pynnonen 2010 |
| KB-AC-WARN | robustness | DW outside [1.5, 2.5] in >= 50% events | warning | Brown & Warner 1985 |
| KB-LOWFIT-WARN | robustness | R2 < 0.05 in >= 50% events | warning | MacKinlay 1997 |
| KB-DEGEN-EVENTS | robustness | n_valid / n_total < 0.8 | error | MacKinlay 1997 |
| KB-SMALL-N | robustness | n_valid_events < 10 | warning | Brown & Warner 1985 |

All 5 required academic authorities appear: MacKinlay (KB-LOWFIT-WARN, KB-DEGEN-EVENTS), Brown & Warner (KB-NONNORM-NONPAR, KB-AC-WARN, KB-SMALL-N), Patell (KB-NORM-PATELL), BMP/Boehmer (KB-VAR-INCREASE-BMP), Kolari & Pynnonen (KB-OVERLAP-KP).

### tests/testthat/test_knowledge_base.R

143 tests covering:
- Structural: `es_kb()` returns list of >= 8 rules; all required fields present
- Citation integrity: all 5 required authorities present; author/year/key non-empty
- Condition safety: every condition is a function returning length-1 logical on NA fixture without error
- Id/severity/category uniqueness and validity
- Per-rule positive firing (8 positive tests)
- Per-rule negative non-firing (8 negative tests)
- KB-NONNORM-NONPAR recommendation mentions non-parametric alternative (Sign/Rank/Corrado)
- KB-OVERLAP-KP recommendation mentions Kolari-Pynnonen
- NA-guard: all robustness rules return FALSE on all-NA fixture
- Integration: every rule condition runs without error on real `es_diagnostics(create_fitted_mock_task())` output

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Omissions (documented)

**KB-PRETREND omitted.** The plan notes "include KB-PRETREND if pretrend signal is available in the diagnostics, else omit and note why." The `es_diagnostics` harvester from Plan 05-1 does not capture `pretrend_test()` output (that requires a separate call not in the harvester). KB-PRETREND is omitted per the plan's conditional instruction; it can be added in a future plan that extends `es_diagnostics` to include pretrend signals.

## Verification Results

- `testthat::test_file("tests/testthat/test_knowledge_base.R")`: FAIL 0 | WARN 0 | SKIP 0 | PASS 143
- `devtools::test()` (full suite): FAIL 0 | WARN 1 | SKIP 31 | PASS 1620 (1 pre-existing warning in test_data_download.R, 31 pre-existing skips)
- `git diff DESCRIPTION`: empty (KB is pure base R, zero new dependencies)
- `NAMESPACE` contains `export(es_kb)`

## Known Stubs

None.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. The KB reads only in-memory lists; it calls no `Sys.getenv()`, no file reads, no network. T-05-04 (citation correctness) is mitigated by the per-rule test net. T-05-05 (new deps) confirmed mitigated — `git diff DESCRIPTION` empty.

## Self-Check: PASSED

- `R/knowledge_base.R` exists: FOUND
- `tests/testthat/test_knowledge_base.R` exists: FOUND
- `man/es_kb.Rd` exists: FOUND
- Commits f429e15 and b3adf14 exist in git log: FOUND
- `export(es_kb)` in NAMESPACE: FOUND
- `git diff DESCRIPTION` empty: CONFIRMED
- All 143 new tests + 1620 full suite tests: PASS
