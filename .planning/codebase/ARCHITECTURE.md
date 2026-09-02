<!-- refreshed: 2026-09-02 -->
# Architecture

**Analysis Date:** 2026-09-02

## System Overview

EventStudy is a comprehensive R package for financial event study analysis. It implements a modular, extensible pipeline architecture with R6 OOP for composable models, test statistics, and specialized task types.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                          User API Layer                              │
│  run_event_study() | EventStudyTask | PanelEventStudyTask           │
│  IntradayEventStudyTask | SyntheticControlTask                       │
│  `R/execute.R`, `R/task.R`, `R/panel_event_study.R`                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Pipeline Orchestration Layer                     │
│  prepare_event_study() → fit_model() → calculate_statistics()        │
│  `R/prepare_event_study.R`, `R/execute.R`                            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                ┌──────────────┼──────────────┐
                ▼              ▼              ▼
        ┌────────────────┐ ┌────────────┐ ┌──────────────┐
        │ Return Models  │ │ Test Stats │ │ Window/Prep  │
        │ (ModelBase)    │ │ (TestStat) │ │ Calculations │
        └────────────────┘ └────────────┘ └──────────────┘
        `R/models.R`       `R/*_test_st..` `R/return_cal.`
        `R/models_time..`  `R/test_stat.`  `R/prepare_...`
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Results Container & Output                        │
│  EventStudyTask.data_tbl (nested) | aar_caar_tbl                    │
│  Plotting | Export (CSV/Excel/LaTeX) | Cross-sectional Regression   │
│  `R/plotting.R`, `R/export.R`, `R/cross_sectional.R`                │
└─────────────────────────────────────────────────────────────────────┘

```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| **EventStudyTask** | Core container for single/multi-event data; manages nested tibble structure with stock prices, returns, event windows | `R/task.R` |
| **ParameterSet** | Configuration object defining model choices, test statistics, return calculation method | `R/parameter_set.R` |
| **PanelEventStudyTask** | Long-format panel (DiD-style) event study container for staggered treatment designs | `R/panel_event_study.R` |
| **IntradayEventStudyTask** | Intraday event study task for POSIXct timestamps with minute/second windows | `R/task_intraday.R` |
| **SyntheticControlTask** | Synthetic control method implementation for causal inference | `R/synthetic_control.R` |
| **Return Calculators** | SimpleReturn, LogReturn — R6 classes for computing firm/index returns | `R/return_calculation.R` |
| **Return Models** | MarketModel, Fama-French 3/5-factor, Carhart 4-factor, GARCH, Rolling-window, DCC-GARCH, BHAR, Volume, Volatility models | `R/models.R`, `R/models_time_varying.R` |
| **ModelBase** | Abstract R6 base class defining fit() and abnormal_returns() interface | `R/models.R` |
| **Test Statistics** | ARTTest, CARTTest, CSectTTest, PatellZTest, SignTest, BMPTest, KolariPynnonenTest, CalendarTimePortfolioTest | `R/single_event_test_statistics.R`, `R/multi_event_test_statistics.R` |
| **TestStatisticBase** | Abstract R6 base class for all test statistics compute() method | `R/single_event_test_statistics.R` |
| **Plot Functions** | plot_stocks(), plot_event_study(), plot_diagnostic() — Plotly-based visualization | `R/plotting.R` |
| **Export Functions** | export_results() → CSV/Excel/LaTeX, broom-compatible tidy() method | `R/export.R` |
| **Cross-Sectional Analysis** | cross_sectional_regression() — Regress CARs on firm characteristics | `R/cross_sectional.R` |
| **Diagnostics** | Shapiro-Wilk, Durbin-Watson, Ljung-Box, pre-trend testing | `R/diagnostics.R` |
| **Bootstrap Inference** | bootstrap_test() — Wild bootstrap for robust inference | `R/bootstrap.R` |
| **Multiple Testing** | adjust_p_values() — BH, Bonferroni, Holm corrections | `R/p_adjustment.R` |
| **Simulation** | simulate_event_study() — Monte Carlo power analysis | `R/simulation.R` |
| **Data Download** | download_stock_data(), download_factor_data() — Fetch from web sources | `R/data_download.R` |
| **Report Generation** | generate_report() — Automated RMarkdown reporting | `R/report.R` |

## Pattern Overview

**Overall:** Composable R6 OOP pipeline with strategy pattern for pluggable models and test statistics.

**Key Characteristics:**
- **Modular:** Each return model, test statistic, and task type is independently pluggable via R6 inheritance
- **Functional Pipeline:** prepare_event_study() → fit_model() → calculate_statistics() orchestrates the flow
- **Nested Data Structure:** EventStudyTask$data_tbl groups by (event_id, group, firm_symbol) with nested stock price/return tibbles
- **Strategy Pattern:** Models and test statistics inherit from ModelBase and TestStatisticBase, enabling easy extension
- **Intraday Support:** POSIXct timestamps and minute/second-level windows handled natively
- **Panel Methods:** Modern DiD estimators (Sun-Abraham, Callaway-Sant'Anna, de Chaisemartin-D'Haultfoeuille, Borusyak-Jaravel-Spiess)

## Layers

**User-Facing API Layer:**
- Purpose: Convenience functions for creating tasks and running complete pipelines
- Location: `R/execute.R`, `R/task.R`, `R/panel_event_study.R`, `R/task_intraday.R`, `R/synthetic_control.R`
- Contains: EventStudyTask$new(), run_event_study(), PanelEventStudyTask$new()
- Depends on: All downstream layers
- Used by: End users, vignettes, tests

**Data Preparation Layer:**
- Purpose: Transform raw stock price data into structured event study format with returns, windows, factor data
- Location: `R/prepare_event_study.R`, `R/return_calculation.R`, `R/task_validation.R`
- Contains: prepare_event_study(), .append_returns(), .append_windows()
- Depends on: ReturnCalculation classes
- Used by: Pipeline orchestration, test frameworks

**Model Fitting Layer:**
- Purpose: Estimate return models (simple OLS, GARCH, rolling-window, multi-factor) and calculate abnormal returns
- Location: `R/models.R`, `R/models_time_varying.R`
- Contains: MarketModel, FamaFrench3FactorModel, GARCHModel, RollingWindowModel, etc. (all inherit ModelBase)
- Depends on: Data with firm/index returns, optional factor data
- Used by: fit_model() orchestration

**Test Statistics Layer:**
- Purpose: Compute single-event (AR/CAR) and multi-event (AAR/CAAR, Patell, BMP, Sign) test statistics
- Location: `R/single_event_test_statistics.R`, `R/multi_event_test_statistics.R`, `R/test_statistics_set.R`
- Contains: TestStatisticBase subclasses; SingleEventStatisticsSet, MultiEventStatisticsSet containers
- Depends on: Model statistics (sigma, df, residuals), fitted abnormal returns
- Used by: calculate_statistics() orchestration, results aggregation

**Results & Output Layer:**
- Purpose: Aggregate, transform, visualize, and export results
- Location: `R/plotting.R`, `R/export.R`, `R/cross_sectional.R`, `R/report.R`, `R/diagnostics.R`
- Contains: plot_event_study(), export_results(), cross_sectional_regression(), diagnostic plots
- Depends on: EventStudyTask with computed statistics
- Used by: End users for reporting and publication

**Extensions Layer:**
- Purpose: Specialized features (panel DiD, intraday, synthetic control, bootstrap, power simulation)
- Location: `R/panel_event_study.R`, `R/task_intraday.R`, `R/synthetic_control.R`, `R/bootstrap.R`, `R/simulation.R`
- Contains: PanelEventStudyTask, IntradayEventStudyTask, SyntheticControlTask, bootstrap_test(), simulate_event_study()
- Depends on: Core pipeline components
- Used by: Advanced users, specialized analyses

## Data Flow

### Primary Request Path (run_event_study)

1. **User calls run_event_study(task, parameter_set)** (`R/execute.R:13`)
   - task: EventStudyTask with firm stock data, index data, event request specs
   - parameter_set: ParameterSet defining model, return calc, test statistics

2. **prepare_event_study(task, parameter_set)** (`R/execute.R:14`, `R/prepare_event_study.R:12`)
   - Calls .append_returns() for each nested data_tbl row (uses parameter_set$return_calculation)
   - Calls .append_windows() to mark event/estimation windows relative to event_date
   - Joins factor data if provided (Fama-French, Carhart factors)
   - Computes excess returns if risk_free_rate available
   - Returns task with returns and windows calculated

3. **fit_model(task, parameter_set)** (`R/execute.R:15`, `R/execute.R:29`)
   - Maps .initialize_and_fit_model() over each row of task$data_tbl
   - Deep-clones parameter_set$return_model for each event (each gets its own model instance)
   - Calls model$fit(data_tbl) on estimation_window data
   - Calls .calculate_abnormal_returns() to compute AR during event window
   - Attaches model and abnormal_returns to task$data_tbl

4. **calculate_statistics(task, parameter_set)** (`R/execute.R:17`, `R/execute.R:68`)
   - **Single-event statistics:** Maps each test in parameter_set$single_event_statistics over (data, model) pairs
   - Each test computes AR/CAR t-stats and appends as columns to task$data_tbl
   - **Multi-event statistics:** Groups task$data_tbl by group, calls each test in parameter_set$multi_event_statistics
   - Produces task$aar_caar_tbl with AAR/CAAR cross-sectional t-stats

### Data Structure Throughout Flow

**EventStudyTask.data_tbl:**
```
  event_id  group  firm_symbol  data (nested)  request (nested)  model  statistics columns...
```

- **data:** tibble with columns: date, firm_adjusted, firm_returns, index_adjusted, index_returns, 
           event_window (0/1), estimation_window (0/1), relative_index, abnormal_returns
- **request:** tibble with event_date, event_window_start, event_window_end, estimation_window_length, shift_estimation_window
- **model:** Fitted R6 model object (MarketModel, etc.) with statistics accessible via model$statistics
- **statistics columns:** ar_t, car_t (or other test statistic names) for each event

**EventStudyTask.aar_caar_tbl (after multi-event stats):**
```
  group  CSectT (or other stat name)  
```

- **CSectT:** tibble with relative_index, aar, caar, aar_t, caar_t, n_events, car_window

### Secondary Flow: Panel Event Study

1. User creates PanelEventStudyTask with long-format panel data
2. Calls estimate_panel_event_study(task, method, leads, lags, dynamic=TRUE/FALSE)
3. Internally calls panel_twfe() or panel_dynamic_twfe() or panel_sun_abraham() depending on method
4. Returns event-time coefficients suitable for event study plots

### Tertiary Flow: Intraday Event Study

1. User creates IntradayEventStudyTask with POSIXct timestamps
2. Specifies windows at minute or second level (e.g., -60 to +120 minutes)
3. Pipeline proceeds as normal with POSIXct-aware window marking
4. Results preserve intraday temporal precision

## Key Abstractions

**ModelBase:**
- Purpose: Abstract interface for return models
- Examples: `R/models.R` (MarketModel, FamaFrench3FactorModel), `R/models_time_varying.R` (GARCHModel, RollingWindowModel)
- Pattern: fit(data_tbl) and abnormal_returns(data_tbl) methods; statistics object populated with sigma, df, residuals, autocorrelation

**TestStatisticBase:**
- Purpose: Abstract interface for test statistics
- Examples: `R/single_event_test_statistics.R` (ARTTest, CARTTest), `R/multi_event_test_statistics.R` (CSectTTest, PatellZTest, BMPTest)
- Pattern: compute(data_tbl, model) returns test statistic tibble with results

**ReturnCalculation:**
- Purpose: Abstract interface for return calculation strategies
- Examples: SimpleReturn, LogReturn in `R/return_calculation.R`
- Pattern: calculate_return(tbl, in_column, out_column) for flexible return type

**StatisticsSetBase:**
- Purpose: Container for multiple test statistics
- Subclasses: SingleEventStatisticsSet, MultiEventStatisticsSet in `R/test_statistics_set.R`
- Pattern: tests field holds list of TestStatisticBase objects, add_test() for dynamic configuration

**ParameterSet:**
- Purpose: Configuration container for event study definition
- Location: `R/parameter_set.R`
- Fields: return_calculation, return_model, single_event_statistics, multi_event_statistics
- Pattern: Centralized composition of all strategy choices

## Entry Points

**run_event_study():**
- Location: `R/execute.R:13`
- Triggers: User calls with prepared EventStudyTask and ParameterSet
- Responsibilities: Orchestrates prepare_event_study() → fit_model() → calculate_statistics()

**prepare_event_study():**
- Location: `R/prepare_event_study.R:12`
- Triggers: First step of pipeline or called directly for data prep only
- Responsibilities: Returns transformation, window creation, factor data joining

**fit_model():**
- Location: `R/execute.R:29`
- Triggers: After prepare_event_study() or direct call
- Responsibilities: Model cloning and fitting, abnormal return calculation

**calculate_statistics():**
- Location: `R/execute.R:68`
- Triggers: After fit_model() or direct call
- Responsibilities: Single-event and multi-event test statistic computation

**EventStudyTask$new():**
- Location: `R/task.R:8`
- Triggers: User creates new event study task
- Responsibilities: Validates input data, nests by (event_id, group, firm_symbol), joins request specs

**PanelEventStudyTask$new():**
- Location: `R/panel_event_study.R:15`
- Triggers: User creates panel (DiD) event study
- Responsibilities: Stores panel data and column names, validates columns exist

**IntradayEventStudyTask$new():**
- Location: `R/task_intraday.R:...`
- Triggers: User creates intraday event study
- Responsibilities: Handles POSIXct timestamps, minute/second windows

## Architectural Constraints

- **Threading:** Single-threaded R event loop. purrr::map() operations are sequential (no parallelization built-in; users must use future/furrr for parallel models).
- **Global state:** Minimal; ParameterSet defines choices, models are deep-cloned per-event to avoid shared mutable state.
- **Circular imports:** None detected; R6 inheritance hierarchy is linear.
- **Nested tibble depth:** task$data_tbl nests stock price data; results stay in nested structure until export/plotting unnest.
- **Return calculations:** Both log and simple return supported; chosen via ParameterSet$return_calculation strategy.
- **Factor data joins:** Optional; joined by date column if provided; required for multi-factor models (FF3, FF5, Carhart4).
- **Window definitions:** Relative to event_date using estimation_window_start/end and event_window_start/end; shift_estimation_window allows pre-event offset.

## Anti-Patterns

### Circular Join Inflation (many-to-many)

**What happens:** When joining firm stock data to index data via event_id alone (without date match), many-to-many join creates inflated row counts and duplicate statistics calculations.

**Why it's wrong:** Statistics (Patell Z, BMP) depend on unique event observations; many-to-many join multiplies rows per event-firm combo, biasing counts in denominators.

**Do this instead:** In `R/task.R` private$append_index_tbl() (line ~55-67), always join firm_stock_data_tbl to reference_tbl by **both event_id AND date** in a proper inner_join. Example:
```r
firm_stock_data_tbl %>%
  dplyr::inner_join(reference_tbl, by = c("event_id", "date"))
```
This ensures one index row per firm row, preventing cross-product duplication.

### Missing Forecast Error Correction

**What happens:** Test statistics (AR t-test, CAR t-test) report biased standard errors when the model is fit on estimation window but evaluated on event window.

**Why it's wrong:** Errors in predicting event-window returns introduce additional variance not captured by residual SD of estimation window.

**Do this instead:** Always call private$calculate_forecast_error_correction() in ModelBase (lines ~70-94 of `R/models.R`), which computes Newey-West style FEC as:
```r
fec_sigma = sigma * sqrt(1 + 1/est_length + (event_market_return - mean_est_market)^2 / ss_market)
```
Use fec_sigma for event-window test statistics, not raw model sigma.

### Hard-Coded Model Parameters

**What happens:** Model classes (e.g., MarketModel) define formula and parameters as public fields but don't validate on fit.

**Why it's wrong:** Users can assign invalid formula or parameters post-initialization, leading to fit() failures or silent incorrect results.

**Do this instead:** In model initialize(), enforce immutable formula via private field and public setter with validation:
```r
private$.formula <- as.formula("firm_returns ~ index_returns")
set_formula = function(formula) {
  if (!inherits(formula, "formula")) stop("formula must be class formula")
  private$.formula <- formula
}
```

## Error Handling

**Strategy:** Stop with descriptive message on invalid input (fail-fast); silent NA/NaN for computational issues (e.g., log(0) → NA, singular matrix → NA sigma).

**Patterns:**
- **Input validation:** task_validation.R checks required columns, data types early in EventStudyTask$initialize()
- **Computational errors:** Models trap lm() failures and return NA in statistics (e.g., MarketModel.fit() in models.R)
- **Window errors:** .append_windows() in prepare_event_study.R checks event_date exists; skips events with missing dates
- **Export errors:** export_results() validates task has computed statistics before building tables

## Cross-Cutting Concerns

**Logging:** No logging framework; use cat() or print() for debugging.

**Validation:** EventStudyTask$initialize() calls private$check_data_input(), private$check_request_input() for early validation. Models validate formula and data in fit().

**Authentication:** Data download functions (download_stock_data(), download_factor_data() in `R/data_download.R`) use tidyquant/quantmod backends; no auth tokens.

---

*Architecture analysis: 2026-09-02*
