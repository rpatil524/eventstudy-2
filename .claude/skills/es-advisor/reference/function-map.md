# EventStudy Advisor — Exported Function Map

All functions in this table are real exports verified against `NAMESPACE`.
Do NOT invent function names or arguments not listed here.

---

## Pipeline Functions

| Function | Purpose | Key Args |
|----------|---------|----------|
| `prepare_event_study(task, parameter_set)` | Compute returns, attach event windows, join factor data | `task` (EventStudyTask), `parameter_set` (ParameterSet) |
| `run_event_study(task, parameter_set)` | Full pipeline convenience: prepare → fit → calculate | `task`, `parameter_set` |
| `fit_model(task, parameter_set)` | Fit the return model and compute abnormal returns | `task`, `parameter_set` |
| `calculate_statistics(task, parameter_set)` | Compute all configured test statistics | `task`, `parameter_set` |

---

## Diagnostics Functions

| Function | Purpose | Key Args |
|----------|---------|----------|
| `es_diagnostics(task, max_events = 20L)` | Extract structured diagnostics from a fitted task | `task` (fitted EventStudyTask), `max_events` (integer cap) |
| `model_diagnostics(task)` | Model-fit summary (R-squared, residual tests) | `task` |
| `plot_diagnostics(task)` | Residual diagnostic plots (normality, autocorrelation) | `task` |

---

## Advisor Functions

| Function | Purpose | Key Args |
|----------|---------|----------|
| `es_advise(diagnostics, task_type, provider = NULL, model = NULL, ...)` | Grounded AI advice for a specific task type | `diagnostics` (from `es_diagnostics()`), `task_type` (one of: `"interpret"`, `"recommend_stat"`, `"recommend_model"`, `"flag_robustness"`, `"design_discussion"`, `"report_writing"`), `provider` (from `provider()`) |
| `recommend_stat(x, provider = NULL, ...)` | Offline KB-based test-statistic recommendation | `x` (EventStudyTask or es_diagnostics), `provider` (optional) |
| `flag_robustness(x, provider = NULL, ...)` | Offline KB-based robustness-concern flags | `x` (EventStudyTask or es_diagnostics), `provider` (optional) |
| `provider(type = NULL, fn = NULL, model = NULL, base_url = NULL, ...)` | Build a provider config object (3-tier: arg → env → default) | `type` (e.g. `"anthropic"`, `"openai"`), `model`, `base_url` |
| `es_kb()` | Return the full KB rule list (for inspection/debugging) | none |

---

## Report and Export

| Function | Purpose | Key Args |
|----------|---------|----------|
| `generate_report(task, ..., advice = NULL)` | Generate RMarkdown report, optionally embedding advice | `task`, `advice` (Advice/es_advice object or NULL) |

---

## Provider Environment Variables

These env vars are read by `provider()` when no arg is supplied:

| Variable | Purpose |
|----------|---------|
| `EVENTSTUDY_ADVISOR_PROVIDER` | Provider type (`"anthropic"`, `"openai"`, etc.) |
| `EVENTSTUDY_ADVISOR_MODEL` | Model name |
| `EVENTSTUDY_ADVISOR_BASE_URL` | Base URL (for OpenAI-compatible endpoints) |

---

## Notes

- `recommend_stat()` and `flag_robustness()` dispatch on class: works on both
  `EventStudyTask` and `es_diagnostics` objects.
- All advisor functions are grounded — they never fabricate numbers. The LLM
  path is grounded by `es_diagnostics()` output + KB rules. The offline path
  uses KB rules only.
- The `provider()` function resolves in three tiers: explicit arg > env var > package default.
