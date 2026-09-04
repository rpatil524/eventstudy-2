# EventStudy Advisor Workflow — Step-by-Step Recipe

Each stage is a self-contained Rscript one-liner (or short block). Run from the
project root. Every function named here is a real export in `NAMESPACE`.

---

## Stage 1: Load — Build Task and Parameters

```r
library(EventStudy)

# firm_tbl: tibble with columns date, firm_symbol, firm_adjusted
# index_tbl: tibble with columns date, index_adjusted
# request_tbl: tibble with event_date, event_window_start, event_window_end,
#              estimation_window_length, firm_symbol, event_id
task <- EventStudyTask$new(firm_tbl, index_tbl, request_tbl)

# ParameterSet selects model + return type + statistics
ps <- ParameterSet$new()
ps$return_model <- MarketModel$new()
```

---

## Stage 2: Run — Execute the Pipeline

**Option A (convenience):**
```r
task <- run_event_study(task, ps)
```

**Option B (explicit steps):**
```r
task <- prepare_event_study(task, ps)
task <- fit_model(task, ps)
task <- calculate_statistics(task, ps)
```

---

## Stage 3: Diagnose — Extract Structured Diagnostics

```r
diag <- es_diagnostics(task, max_events = 20L)
print(diag)
```

`es_diagnostics()` returns a named list with estimation-window fit signals,
event-window results, cross-sectional signals, and per-event contract state.
See `interpreting-diagnostics.md` for field-by-field guidance.

---

## Stage 4: Advise — Get Grounded Recommendations

### With an LLM provider

**3-tier provider resolution** (arg → env → default):
```r
# Arg-level: pass a configured provider object
prov <- provider(type = "anthropic", model = "claude-opus-4-5",
                 base_url = NULL)

# Env-level (set in shell or .Renviron):
# EVENTSTUDY_ADVISOR_PROVIDER=anthropic
# EVENTSTUDY_ADVISOR_MODEL=claude-opus-4-5
# EVENTSTUDY_ADVISOR_BASE_URL=https://api.anthropic.com

# Default: provider() with no args uses env vars or package default
prov <- provider()
```

**task_type values** (pass exactly one):
- `"interpret"` — interpret the overall results
- `"recommend_stat"` — which test statistic to use
- `"recommend_model"` — which return model to use
- `"flag_robustness"` — robustness concerns
- `"design_discussion"` — event study design choices
- `"report_writing"` — narrate results for a report

```r
advice <- es_advise(diag, task_type = "interpret", provider = prov)
print(advice)
```

### Offline (no API key — always available)

```r
# Recommend a test statistic based on KB rules
stat_advice  <- recommend_stat(diag)
print(stat_advice)

# Flag robustness concerns based on KB rules
flag_advice  <- flag_robustness(diag)
print(flag_advice)
```

The offline path never errors for lack of a key and never fabricates a number.

---

## Stage 5: Re-Run — Apply Advice

Change the model or statistic based on advice, then re-run:

```r
ps2 <- ParameterSet$new()
ps2$return_model <- FamaFrench3FactorModel$new()   # changed per advice
ps2$multi_event_statistics <- MultiEventStatisticsSet$new()
ps2$multi_event_statistics$add_test(PatellZTest$new())

task2 <- run_event_study(task_raw, ps2)   # task_raw = original unfitted task
diag2 <- es_diagnostics(task2)
```

---

## Stage 6: Compare — Contrast Results

```r
# Side-by-side diagnostics
print(diag)
print(diag2)

# Optionally generate a full report with advice embedded
generate_report(task2, advice = advice)
```

---

## Optional: Visual Diagnostics

```r
plot_diagnostics(task)   # residual plots, normality, autocorrelation
model_diagnostics(task)  # model-fit summary table
```
