# Codebase Structure

**Analysis Date:** 2026-09-02

## Directory Layout

```
/home/simonm/projects/datascience/eventstudy/
├── R/                          # Core R package source code (23 files)
│   ├── task.R                  # EventStudyTask R6 class (core container)
│   ├── task_intraday.R         # IntradayEventStudyTask for POSIXct timestamps
│   ├── panel_event_study.R     # PanelEventStudyTask for DiD analyses
│   ├── task_validation.R       # Input validation helpers
│   ├── execute.R               # Pipeline orchestration (run_event_study, fit_model, calculate_statistics)
│   ├── prepare_event_study.R   # Data preparation (returns, windows, factor joins)
│   ├── parameter_set.R         # ParameterSet configuration container
│   ├── models.R                # Return models (Market Model, Fama-French, Carhart, BHAR, Volume, Volatility)
│   ├── models_time_varying.R   # Time-varying models (GARCH, Rolling-window, DCC-GARCH)
│   ├── return_calculation.R    # Return calculation strategies (SimpleReturn, LogReturn)
│   ├── single_event_test_statistics.R  # ARTTest, CARTTest test statistics
│   ├── multi_event_test_statistics.R   # CSectTTest, PatellZTest, SignTest, BMPTest, KP test, CalendarTime
│   ├── test_statistics_set.R   # StatisticsSetBase, SingleEventStatisticsSet, MultiEventStatisticsSet
│   ├── plotting.R              # Visualization (plot_stocks, plot_event_study, diagnostic plots)
│   ├── export.R                # Result export (CSV, Excel, LaTeX)
│   ├── cross_sectional.R       # Cross-sectional CAR regression analysis
│   ├── diagnostics.R           # Diagnostic tests (Shapiro-Wilk, Durbin-Watson, Ljung-Box)
│   ├── bootstrap.R             # Wild bootstrap inference
│   ├── p_adjustment.R          # Multiple testing corrections (BH, Bonferroni, Holm)
│   ├── synthetic_control.R     # Synthetic control method implementation
│   ├── simulation.R            # Monte Carlo power analysis
│   ├── data_download.R         # Stock/factor data download helpers
│   ├── report.R                # Automated RMarkdown report generation
│   └── EventStudy-package.R    # Package documentation and NSE variable declarations
│
├── tests/                      # Test suite
│   ├── testthat.R              # testthat configuration
│   └── testthat/               # Test files (28 test scripts)
│       ├── helper-mock-data.R  # Mock data factory for tests
│       ├── test_task.R         # EventStudyTask tests
│       ├── test_models.R       # Model fitting tests
│       ├── test_models_time_varying.R  # GARCH/rolling-window model tests
│       ├── test_return_calculation.R   # Return calculation tests
│       ├── test_parameter_set.R        # ParameterSet tests
│       ├── test_ar_car_test_statistics.R    # AR/CAR t-test tests
│       ├── test_aar_test_statistics.R       # AAR/CAAR tests
│       ├── test_multi_event_statistics.R    # Patell, BMP, Sign test tests
│       ├── test_caar_test_statistics.R      # CAAR t-test tests
│       ├── test_bhar_test_statistics.R      # BHAR tests
│       ├── test_bootstrap.R         # Bootstrap inference tests
│       ├── test_diagnostics.R       # Diagnostic test tests
│       ├── test_p_adjustment.R      # Multiple testing correction tests
│       ├── test_plotting.R          # Visualization tests
│       ├── test_export.R            # Export function tests
│       ├── test_cross_sectional.R   # Cross-sectional regression tests
│       ├── test_panel.R             # Panel event study tests
│       ├── test_intraday.R          # Intraday event study tests
│       ├── test_synthetic_control.R # Synthetic control tests
│       ├── test_simulation.R        # Power simulation tests
│       ├── test_data_download.R     # Data download tests
│       ├── test_report.R            # Report generation tests
│       ├── test_test_statistics_set.R  # Statistics container tests
│       ├── test_execute.R           # Pipeline execution tests
│       ├── test_validation.R        # Input validation tests
│       └── test_edge_cases.R        # Edge case regression tests
│
├── man/                        # Roxygen-generated documentation (auto-generated)
│
├── vignettes/                  # Package vignettes (17 RMarkdown tutorials)
│   ├── introduction.Rmd        # Quick start guide
│   ├── custom-models.Rmd       # How to create custom models
│   ├── custom-test-statistics.Rmd    # How to create custom test statistics
│   ├── factor-models-bhar.Rmd  # Fama-French, Carhart, BHAR examples
│   ├── time-varying-models.Rmd # GARCH, rolling-window, DCC-GARCH
│   ├── volume-volatility-event-study.Rmd  # Volume/volatility models
│   ├── cross-sectional-analysis.Rmd # CAR regression on firm characteristics
│   ├── intraday-event-study.Rmd     # POSIXct timestamps and minute/second windows
│   ├── panel-event-study.Rmd        # DiD panel event studies
│   ├── modern-did-estimators.Rmd    # Sun-Abraham, Callaway-Sant'Anna, etc.
│   ├── inference-robustness.Rmd     # Bootstrap, HAC SEs, multiple testing
│   ├── diagnostics-validation.Rmd   # Pre-trend tests, diagnostic plots
│   ├── simulation-power-analysis.Rmd # Monte Carlo power simulations
│   ├── result-extraction.Rmd        # get_ar(), get_car(), get_aar(), tidy()
│   ├── automated-reports.Rmd        # generate_report() for publication
│   ├── synthetic-control.Rmd        # Synthetic control methods
│   └── data-download.Rmd            # download_stock_data(), download_factor_data()
│
├── inst/
│   └── rmarkdown/
│       └── templates/
│           └── event_study_report/
│               └── template.yaml    # RMarkdown template for reports
│
├── .planning/
│   └── codebase/                    # GSD codebase analysis (this directory)
│       ├── ARCHITECTURE.md
│       └── STRUCTURE.md
│
├── .github/
│   └── workflows/
│       └── R-CMD-check.yaml         # CI/CD workflow
│
├── NAMESPACE                   # R package namespace (roxygen-generated)
├── DESCRIPTION                 # Package metadata
├── NEWS.md                      # Release notes and changelog
├── README.md                    # Package overview and quick start
├── LICENSE                      # AGPL-3 license
├── .gitignore                   # Git ignore rules
├── .Rbuildignore                # Build ignore rules
├── EventStudy.Rproj             # RStudio project file
└── cran-comments.md             # CRAN submission notes
```

## Directory Purposes

**R/:**
- Purpose: All source code for the EventStudy package
- Contains: R6 class definitions, functions, helper utilities
- Key files: task.R (EventStudyTask), execute.R (pipeline), models.R (return models), multi_event_test_statistics.R (test statistics)

**tests/testthat/:**
- Purpose: Comprehensive unit and integration test suite using testthat framework
- Contains: 28 test scripts covering all major components, data patterns, edge cases
- Key files: helper-mock-data.R (test fixtures), test_edge_cases.R (regression tests for bug fixes)

**man/:**
- Purpose: Roxygen-generated R documentation for all exported functions and classes
- Generated from: Roxygen comments in R/ files
- Auto-managed: Do not edit manually

**vignettes/:**
- Purpose: Comprehensive user tutorials and examples
- Contains: 17 RMarkdown vignettes covering all features (models, statistics, extensions, workflows)
- Key files: introduction.Rmd (quick start), custom-models.Rmd (extensibility), panel-event-study.Rmd (DiD methods)

**inst/rmarkdown/templates/:**
- Purpose: Template for automated report generation
- Contains: event_study_report/template.yaml (RMarkdown template)

**.planning/codebase/:**
- Purpose: GSD codebase analysis and architecture documentation
- Contains: ARCHITECTURE.md (system design), STRUCTURE.md (this file)

## Key File Locations

**Entry Points:**
- `R/execute.R`: run_event_study() — main pipeline orchestrator
- `R/task.R`: EventStudyTask$new() — core data container
- `R/panel_event_study.R`: PanelEventStudyTask$new() — panel/DiD entry point
- `R/task_intraday.R`: IntradayEventStudyTask$new() — intraday analysis entry point

**Configuration:**
- `R/parameter_set.R`: ParameterSet$new() — defines models, tests, return calculation
- `DESCRIPTION`: Package metadata, dependencies, version

**Core Logic:**
- `R/models.R`: Return models (1161 lines) — MarketModel, FamaFrench3/5FactorModel, Carhart4FactorModel, BHAR, Volume, Volatility
- `R/models_time_varying.R`: Time-varying models (347 lines) — GARCHModel, RollingWindowModel, DCCGARCHModel
- `R/single_event_test_statistics.R`: AR/CAR test statistics (197 lines) — ARTTest, CARTTest, BHARTTest
- `R/multi_event_test_statistics.R`: AAR/CAAR test statistics (668 lines) — CSectTTest, PatellZTest, SignTest, BMPTest, KolariPynnonenTest, CalendarTimePortfolioTest
- `R/prepare_event_study.R`: Data prep (122 lines) — returns, windows, factor joining
- `R/execute.R`: Pipeline orchestration (163 lines) — fit_model, calculate_statistics

**Output/Analysis:**
- `R/plotting.R`: Visualization (348 lines) — plot_stocks, plot_event_study, diagnostic plots
- `R/export.R`: Result export (425 lines) — CSV, Excel, LaTeX
- `R/cross_sectional.R`: Cross-sectional analysis (262 lines) — regress CARs on characteristics
- `R/report.R`: Report generation (auto-generated from template)

**Extensions:**
- `R/panel_event_study.R`: Panel DiD methods (636 lines)
- `R/task_intraday.R`: Intraday event studies (411 lines)
- `R/synthetic_control.R`: Synthetic control (411 lines)
- `R/bootstrap.R`: Wild bootstrap (166 lines)
- `R/simulation.R`: Power analysis (262 lines)

**Testing:**
- `tests/testthat/helper-mock-data.R`: Mock data factory and fixtures
- `tests/testthat/test_edge_cases.R`: Regression tests (latest bug fixes)
- `tests/testthat/test_models.R`: Model fitting tests
- `tests/testthat/test_multi_event_statistics.R`: Multi-event statistic tests

## Naming Conventions

**Files:**
- Pattern: `snake_case.R` (e.g., `multi_event_test_statistics.R`)
- Rationale: R package convention; matches function/class names defined within

**Functions:**
- Public functions: `snake_case()` (e.g., `run_event_study()`, `plot_event_study()`, `export_results()`)
- Private/helpers: `.snake_case()` (leading dot, e.g., `.append_returns()`, `.initialize_and_fit_model()`)
- Rationale: dot prefix clearly signals internal use

**R6 Classes:**
- Pattern: `PascalCase` (e.g., EventStudyTask, MarketModel, CSectTTest)
- Rationale: R6 convention; distinguishes from function names

**Variables:**
- Local: `snake_case` (e.g., `firm_stock_data_tbl`, `event_window_start`)
- Private fields: `.snake_case` (leading dot, e.g., `.statistics`, `.fitted_model`)
- Rationale: dot prefix signals internal/private; tbl suffix for tibble/dataframe variables

**Test files:**
- Pattern: `test_<component>.R` (e.g., `test_models.R`, `test_multi_event_statistics.R`)
- Rationale: testthat convention; maps to source file names

## Where to Add New Code

**New Return Model:**
- Primary code: `R/models.R` or `R/models_time_varying.R` (if time-varying)
- Step 1: Create R6Class inheriting from ModelBase
- Step 2: Implement fit(data_tbl) and abnormal_returns(data_tbl) methods
- Step 3: Populate private$.statistics (sigma, degree_of_freedom, residuals, etc.)
- Example: See MarketModel (lines 112-200 of `R/models.R`) for simple template
- Tests: `tests/testthat/test_models.R` or `tests/testthat/test_models_time_varying.R`

**New Test Statistic:**
- Primary code: `R/single_event_test_statistics.R` (per-event) or `R/multi_event_test_statistics.R` (multi-event)
- Step 1: Create R6Class inheriting from TestStatisticBase
- Step 2: Implement compute(data_tbl, model) method
- Step 3: Return tibble with test results
- Example: See ARTTest (lines 41-77 of `R/single_event_test_statistics.R`) or CSectTTest (lines 1-62 of `R/multi_event_test_statistics.R`)
- Tests: `tests/testthat/test_ar_car_test_statistics.R`, `tests/testthat/test_multi_event_statistics.R`, or new `test_<new_test>.R`

**New Return Calculation Strategy:**
- Primary code: `R/return_calculation.R`
- Step 1: Create R6Class inheriting from ReturnCalculation
- Step 2: Implement calculate_return(tbl, in_column, out_column) method
- Example: See SimpleReturn and LogReturn (lines 24-78 of `R/return_calculation.R`)
- Tests: `tests/testthat/test_return_calculation.R`

**New Task Type (specialized event study):**
- Primary code: Create new file `R/task_<type>.R` (e.g., `R/task_intraday.R` already exists)
- Step 1: Create R6Class with initialize(), print() methods
- Step 2: Store required input columns and validation
- Step 3: Create estimation function (e.g., estimate_<type>_event_study())
- Example: See IntradayEventStudyTask (lines ~1-80 of `R/task_intraday.R`) or PanelEventStudyTask (lines 15-87 of `R/panel_event_study.R`)
- Tests: `tests/testthat/test_<type>.R`

**New Plotting Function:**
- Primary code: `R/plotting.R`
- Step 1: Create function using ggplot2 or plotly
- Step 2: Extract data from EventStudyTask using getters (get_ar(), get_car(), get_aar())
- Example: See plot_event_study() (lines 89-150 of `R/plotting.R`)
- Tests: `tests/testthat/test_plotting.R`

**New Export Format:**
- Primary code: `R/export.R`
- Step 1: Add format-specific private helper function `.export_<format>(tables, file, ...)`
- Step 2: Update export_results() switch statement to route to new format
- Example: See .export_csv(), .export_xlsx(), .export_latex() (lines ~80-150 of `R/export.R`)
- Tests: `tests/testthat/test_export.R`

**Utilities/Helpers:**
- Shared validation: `R/task_validation.R`
- Cross-sectional analysis: `R/cross_sectional.R`
- Inference robustness: `R/bootstrap.R`, `R/p_adjustment.R`
- Data helpers: `R/data_download.R`

**Vignettes:**
- Purpose: User-facing tutorials
- Location: `vignettes/<feature-name>.Rmd`
- Template: See introduction.Rmd (quick start); custom-models.Rmd (how to extend)
- Convention: One vignette per major feature or workflow

## Special Directories

**R/:**
- Generated: No
- Committed: Yes
- Read-only: No (source code; edit freely)
- Key constraint: Public functions/classes must be exported via @export roxygen comment

**man/:**
- Generated: Yes (via roxygen2 from R/ comments)
- Committed: Yes
- Read-only: Yes (regenerate with roxygen2::roxygenise())
- Process: Edit roxygen comments in R/ files, then run roxygen2::roxygenise()

**tests/testthat/:**
- Generated: No
- Committed: Yes
- Read-only: No (edit to add tests)
- Run: testthat::test_dir("tests/testthat") or devtools::test()

**vignettes/:**
- Generated: No (source RMarkdown; knitted HTML auto-generated)
- Committed: Yes (source .Rmd only; .html generated in build)
- Read-only: No (edit to update tutorials)

**.planning/codebase/:**
- Generated: Yes (by GSD mapper)
- Committed: Yes (tracks architecture decisions)
- Read-only: No (refresh regularly as codebase evolves)
- Process: Run /gsd-map-codebase periodically to update

**NAMESPACE:**
- Generated: Yes (via roxygen2)
- Committed: Yes
- Read-only: Yes (regenerate with roxygen2::roxygenise())

## Quick Reference: Adding Common Features

**To add a new Fama-French factor:**
1. Add column to factor_tbl with new factor returns
2. Update FamaFrench3FactorModel/FamaFrench5FactorModel formula in `R/models.R`
3. Update vignette `vignettes/factor-models-bhar.Rmd`

**To add a new test statistic to default set:**
1. Create test class in `R/single_event_test_statistics.R` or `R/multi_event_test_statistics.R`
2. Update SingleEventStatisticsSet or MultiEventStatisticsSet (line 60 or 78 of `R/test_statistics_set.R`)
3. Add test to `tests/testthat/test_<type>_test_statistics.R`

**To fix a bug in model fitting:**
1. Locate bug in `R/models.R` or `R/models_time_varying.R`
2. Add regression test to `tests/testthat/test_edge_cases.R` (example: line 1 verifies many-to-many join fix from GH #7)
3. Fix model code
4. Run full test suite: `devtools::test()`

**To export to a new format:**
1. Add `.export_<format>()` private function to `R/export.R`
2. Update export_results() switch (around line 45)
3. Add format-specific tests to `tests/testthat/test_export.R`

---

*Structure analysis: 2026-09-02*
