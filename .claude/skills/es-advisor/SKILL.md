---
name: es-advisor
description: |
  Run the EventStudy AI advisor loop: load data, run the event study pipeline,
  diagnose results, get grounded advice (AI-backed or offline), revise model
  choices, re-run, and compare outcomes. Trigger this skill whenever a user
  asks to analyze, diagnose, interpret, or get recommendations for an event
  study using the EventStudy R package.
---

# EventStudy AI Advisor Skill

This skill drives a complete **load → run → diagnose → advise → re-run → compare**
advisory loop using only already-exported functions from the EventStudy package.
It adds NO new R code — every step calls a real exported symbol from `NAMESPACE`.

## Overview

The advisor loop has six stages:

| Stage | What happens | Key function |
|-------|-------------|--------------|
| 1. Load | Build a task and parameter set | `EventStudyTask$new()`, `ParameterSet$new()` |
| 2. Run | Execute the full pipeline | `run_event_study()` |
| 3. Diagnose | Extract structured diagnostics | `es_diagnostics()` |
| 4. Advise | Get grounded recommendations | `es_advise()` / `recommend_stat()` / `flag_robustness()` |
| 5. Re-run | Apply advice, repeat pipeline | `run_event_study()` again |
| 6. Compare | Contrast before/after diagnostics | side-by-side `es_diagnostics()` |

## Reference Files

- **`reference/workflow.md`** — concrete Rscript one-liners for each stage
- **`reference/function-map.md`** — exported function reference (name, purpose, key args)
- **`reference/interpreting-diagnostics.md`** — how to read `es_diagnostics()` output and the no-API-key offline degrade path

## Quick Entry Points

**Full pipeline (most common):**
```r
Rscript -e '
  library(EventStudy)
  task   <- EventStudyTask$new(firm_tbl, index_tbl, request_tbl)
  ps     <- ParameterSet$new()
  task   <- run_event_study(task, ps)
  diag   <- es_diagnostics(task)
  advice <- es_advise(diag, task_type = "interpret", provider = provider())
  print(advice)
'
```

**Offline (no API key required):**
```r
Rscript -e '
  library(EventStudy)
  diag  <- es_diagnostics(task)   # task already fitted
  stat  <- recommend_stat(diag)
  flags <- flag_robustness(diag)
  print(stat); print(flags)
'
```

## No-Key Degrade Path

When no LLM provider is configured, the skill uses the always-available offline
functions (`recommend_stat()`, `flag_robustness()`) that match KB rules against
diagnostics without any network call. See `reference/interpreting-diagnostics.md`
for the full degrade decision tree.

## Provider Selection

Configure an LLM provider via `provider()` or environment variables. The skill
never fabricates a number — all recommendations are grounded in `es_diagnostics()`
output and KB rules. See `reference/workflow.md` Stage 4 for provider setup.
