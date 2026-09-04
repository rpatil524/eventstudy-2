# Interpreting `es_diagnostics()` Output

`es_diagnostics(task, max_events = 20L)` returns a named list describing the
health of your event study. This file explains what each field means and how
to act on it.

---

## Top-Level Fields

| Field | Type | What it tells you |
|-------|------|-------------------|
| `n_events` | integer | Number of events in the task |
| `estimation_window` | list | Fit quality over the estimation period |
| `event_window` | list | AR/CAR signal in the event window |
| `cross_sectional` | list | Cross-event aggregation (AAR/CAAR) signals |
| `per_event` | list (max `max_events` entries) | Per-event contract state |

---

## Estimation-Window Signals (`estimation_window`)

| Sub-field | Concern if… | Action |
|-----------|-------------|--------|
| `mean_r_squared` | < 0.1 — model explains little variance | Switch to multi-factor model (FF3, FF5, Carhart4) |
| `autocorrelation_pct` | > 20% of events flagged | Use HAC or GARCH model |
| `normality_pct` | > 30% of events fail Shapiro-Wilk | Prefer non-parametric statistics (Sign, Rank, BMP) |
| `thin_trading_pct` | > 10% | Adjust estimation window; use volume-weighted model |

---

## Event-Window Signals (`event_window`)

| Sub-field | Concern if… | Action |
|-----------|-------------|--------|
| `mean_abs_ar` | Very small (< 0.001) | Verify event dates are correct |
| `car_sign_consistency` | Near 0.5 — no directional pattern | Check event selection / confounding events |
| `outlier_pct` | > 15% | Winsorize or use rank-based statistics |

---

## Cross-Sectional Signals (`cross_sectional`)

| Sub-field | What it means |
|-----------|---------------|
| `aar_t_stat` | t-statistic for average abnormal return |
| `caar_t_stat` | t-statistic for cumulative AAR across event window |
| `patell_z` | Patell Z statistic (standardized, handles variance heterogeneity) |
| `bmp_stat` | BMP statistic (adjusts for event-induced variance) |

A significant `caar_t_stat` with non-significant `patell_z` often indicates
variance heterogeneity — BMP or Boehmer-standardized methods are more appropriate.

---

## Per-Event Contract State (`per_event`)

Each entry covers one `event_id` and includes:
- `event_id` — identifier
- `r_squared` — estimation-window model fit
- `sigma` — residual standard deviation (used in test statistics)
- `autocorrelation_flag` — TRUE if Ljung-Box rejects at 5%
- `normality_flag` — TRUE if Shapiro-Wilk rejects at 5%
- `n_estimation_obs` — effective estimation window length

---

## Degrade Path — No API Key

When `provider()` resolves to no configured LLM:

```
es_diagnostics(task)       ← always available, no network
       |
       v
recommend_stat(diag)       ← offline KB rules, no network
flag_robustness(diag)      ← offline KB rules, no network
```

**Decision tree:**

```
Do you have an LLM API key?
  YES → es_advise(diag, task_type = "interpret", provider = provider(...))
  NO  → recommend_stat(diag) + flag_robustness(diag)   [offline KB path]
```

The offline path:
- Never errors for lack of a key
- Never fabricates a number — only fires rules that match observed diagnostic values
- Returns an `es_advice` S3 object with matched KB rules, severity, and citations
- Source field is `"offline_kb"` — always declared so callers know it is rule-based

---

## Common Patterns and Recommended Actions

| Diagnostic pattern | Recommended action |
|-------------------|--------------------|
| Low R-squared + normality failures | Use non-parametric stats: `SignTest`, `RankTest`, `BMPTest` |
| High autocorrelation | Use `GARCHModel` or HAC-corrected inference |
| Small n_events (< 30) | Avoid cross-sectional t; prefer Patell or BMP |
| Many outlier ARs | Use `KolariPynnonenTest` or bootstrap inference |
| Event clustering (many same-day events) | Use `CalendarTimePortfolioTest` |
| Variance increase around event | BMP test corrects for event-induced variance |

---

## Example: Reading a Diagnostic Output

```r
diag <- es_diagnostics(task)

# Check estimation-window health
diag$estimation_window$mean_r_squared
# If < 0.1 → consider multi-factor model

# Check for normality violations
diag$estimation_window$normality_pct
# If > 0.3 → non-parametric statistics recommended

# Get offline KB advice without any API key
recommend_stat(diag)    # fires stat_choice KB rules
flag_robustness(diag)   # fires robustness KB rules
```
