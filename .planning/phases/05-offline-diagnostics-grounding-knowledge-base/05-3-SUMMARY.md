---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: "03"
subsystem: advice-layer
tags: [offline-advice, kb-matching, es_advice, recommend_stat, flag_robustness, CRAN]
status: complete

dependency_graph:
  requires:
    - "05-1 (es_diagnostics S3 object)"
    - "05-2 (EVENTSTUDY_KB rules + es_kb())"
  provides:
    - "recommend_stat() S3 generic + .EventStudyTask/.es_diagnostics methods"
    - "flag_robustness() S3 generic + .EventStudyTask/.es_diagnostics methods"
    - "es_advice S3 object (Phase 7 Advice contract)"
    - "print.es_advice()"
  affects:
    - "NAMESPACE (6 new exports)"

tech_stack:
  added: []
  patterns:
    - "S3 dispatch (UseMethod) with .EventStudyTask and .es_diagnostics methods"
    - "tryCatch guard on each rule predicate (ADV-08 never-error guarantee)"
    - "Severity ranking: error > warning > info"
    - "Phase 7-compatible Advice contract (source, is_deterministic, rules_matched, diagnostics_ref)"

key_files:
  created:
    - R/advise_offline.R
    - tests/testthat/test_advise_offline.R
    - man/recommend_stat.Rd
    - man/flag_robustness.Rd
    - man/print.es_advice.Rd
  modified:
    - NAMESPACE

decisions:
  - "Accept-and-ignore provider=NULL argument on both generics so Phase 7 call shape is forward-compatible without breaking offline path"
  - "Strip condition function from matched rule records in rules_matched — only scalar/list fields exposed, ensuring JSON serializability (T-05-07, T-05-09)"
  - "Use all-match (not first-match) semantics per locked 05-CONTEXT.md decision"
  - "Severity ranks: error=1, warning=2, info=3; stable sort via order()"

metrics:
  duration_minutes: 18
  completed: "2026-09-03"
  tasks_completed: 2
  tasks_total: 2
  commits: 1

actuals:
  tokens: 8200
  tasks: 2
  commits: 1
---

# Phase 05 Plan 03: Offline Advice Layer Summary

**One-liner:** Offline KB-matching advice engine — `recommend_stat()`/`flag_robustness()` deliver severity-ranked `es_advice` objects from any fitted task or diagnostics, with zero dependencies and no-provider guarantee (ADV-08).

## What Was Built

`R/advise_offline.R` implements the offline advice surface:

- **`recommend_stat(x, provider=NULL, ...)`** — S3 generic with `.EventStudyTask` and `.es_diagnostics` methods. Filters KB to `category=="stat_choice"` rules and runs `.build_offline_advice()`.
- **`flag_robustness(x, provider=NULL, ...)`** — same pattern for `category=="robustness"` rules.
- **`.build_offline_advice(diag, rules)`** — internal engine: evaluates each rule's `condition(diag)` inside `tryCatch(..., error=function(e) FALSE)` (bad predicate degrades to no-fire, never crashes), keeps all matches, severity-ranks `error>warning>info`, returns a plain list classed `"es_advice"`.
- **`print.es_advice(x, ...)`** — cat-based print: header, source, deterministic flag, then each matched rule's bracket `[SEVERITY] rule-id (citation: key)` + recommendation text. Returns `invisible(x)`.

The **`es_advice`** S3 object shape (Phase 7-compatible Advice contract):
```
list(
  source           = "offline_kb",
  is_deterministic = TRUE,
  rules_matched    = list(  # severity-ranked; each entry has id/category/recommendation/citation/severity
    list(id, category, recommendation, citation=list(author,year,key,venue), severity),
    ...
  ),
  diagnostics_ref  = <es_diagnostics>
)
```

## Test Coverage (44 tests)

**Task 1 — structure, dispatch, category filtering, no-provider:**
- `recommend_stat(task)` returns `es_advice` with `source="offline_kb"`, `is_deterministic=TRUE`
- task-input and diagnostics-input paths return identical shape
- `flag_robustness` returns only `category=="robustness"` rules; `recommend_stat` only `"stat_choice"`
- No error with `provider=NULL` (explicit offline guarantee)
- `print.es_advice` produces non-empty output with header and severity brackets
- Each matched rule has all required fields; citation list has `key`
- Severity order is non-decreasing in matched rules

**Task 2 — grounded-steering + degenerate safety + JSON:**
- Synthetic diagnostics with all Shapiro-Wilk p < 0.05 fire `KB-NONNORM-NONPAR`; recommendation names Sign/Rank/Corrado
- Synthetic diagnostics with `n_overlap_pairs=3` fire `KB-OVERLAP-KP` with `citation$key="KolariPynnonen2010"`
- Degenerate diagnostics (1 of 3 events fitted) fire `KB-DEGEN-EVENTS` without error and with no API key
- `rules_matched` serializes cleanly via `jsonlite::toJSON` (guarded by `skip_if_not_installed`)

## Verification Results

- `testthat::test_file("tests/testthat/test_advise_offline.R")` → PASS 44, FAIL 0
- `devtools::test()` → PASS 1664, FAIL 0, WARN 1 (pre-existing), SKIP 31 (optional deps)
- `git diff DESCRIPTION` → empty (zero new hard deps — CRAN-01)

## Deviations from Plan

None — plan executed exactly as written. Tests were authored first (RED) then implementation matched (GREEN); both tasks committed together in a single atomic commit as their implementations are tightly coupled.

## Threat Mitigations Applied

| Threat | Mitigation |
|--------|------------|
| T-05-07 (information disclosure) | `rules_matched` exposes only plain scalar/list fields; `condition` function object stripped — no Sys.getenv, no secrets, no environment references |
| T-05-08 (malformed predicate DoS) | Each `rule$condition(diag)` wrapped in `tryCatch(..., error=function(e) FALSE)` |
| T-05-09 (new hard dep) | Pure base R; `git diff DESCRIPTION` empty; jsonlite used only in Suggests-guarded test |

## Self-Check: PASSED

- R/advise_offline.R: FOUND
- tests/testthat/test_advise_offline.R: FOUND
- 05-3-SUMMARY.md: FOUND
- commit ffd9214: FOUND
