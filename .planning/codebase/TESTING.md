# Testing Patterns

**Analysis Date:** 2026-09-02

## Test Framework

**Runner:**
- `testthat` (>= 3.0.0) - as per `DESCRIPTION` file
- Config: `Config/testthat/edition: 3` in `DESCRIPTION`
- Main test entry: `tests/testthat.R` (loads testthat and runs tests)

**Assertion Library:**
- `testthat` built-in expectations: `expect_*()` family of functions
- Common assertions: `expect_true()`, `expect_false()`, `expect_equal()`, `expect_lt()`, `expect_gt()`, `expect_error()`, `expect_warning()`, `expect_output()`, `expect_no_error()`

**Run Commands:**
```bash
# Run all tests
R CMD check .

# Run tests in R session
devtools::test()
testthat::test_dir("tests/testthat/")

# Watch mode (interactive development)
testthat::test_file("tests/testthat/test_*.R")

# Coverage
covr::package_coverage()
```

## Test File Organization

**Location:**
- All test files in `tests/testthat/` directory
- Helper files like `helper-mock-data.R` automatically loaded by testthat before tests
- Tests use co-located organization: `test_models.R` for `R/models.R`, etc.

**Naming:**
- Test files: `test_*.R` (e.g., `test_models.R`, `test_bootstrap.R`)
- Helper files: `helper-*.R` (e.g., `helper-mock-data.R`)
- Each test file contains 1+ `test_that()` blocks covering a related functionality

**Structure:**
```
tests/
├── testthat.R                           # Entry point
└── testthat/
    ├── helper-mock-data.R               # Shared mock data generators
    ├── test_models.R                    # Tests for R/models.R
    ├── test_bootstrap.R                 # Tests for R/bootstrap.R
    ├── test_edge_cases.R                # Edge case and error handling tests
    ├── test_task.R                      # Tests for EventStudyTask
    └── ... (27 test files total)
```

## Test Structure

**Suite Organization:**
```R
test_that("MarketModel fits correctly", {
  data = create_mock_model_data()
  mm = MarketModel$new()

  mm$fit(data)
  expect_true(mm$is_fitted)
  expect_equal(mm$model_name, "MarketModel")

  stats = mm$statistics
  expect_false(is.null(stats$alpha))
  expect_false(is.null(stats$beta))
  expect_false(is.null(stats$sigma))
})
```

**Patterns:**

1. **Setup Pattern:**
   - Tests typically create mock data using helper functions (e.g., `create_mock_model_data()`, `create_mock_task()`)
   - Create R6 object instances with `$new()` constructor
   - Call methods on the initialized objects

2. **Teardown Pattern:**
   - No explicit teardown needed (garbage collection handles R6 objects)
   - Mocked data is local to each test function scope
   - Tests are idempotent and independent

3. **Assertion Pattern:**
   - Multiple sequential assertions per test
   - Early assertions check preconditions (e.g., `expect_true(mm$is_fitted)`)
   - Later assertions check results against expected values
   - Use `expect_*` family: boolean, equality, numeric bounds, error/warning, type checks

**Example test with multiple assertions (from `test_models.R`):**
```R
test_that("MarketModel fits correctly", {
  data = create_mock_model_data()
  mm = MarketModel$new()

  mm$fit(data)
  expect_true(mm$is_fitted)
  expect_equal(mm$model_name, "MarketModel")

  stats = mm$statistics
  expect_false(is.null(stats$alpha))
  expect_false(is.null(stats$beta))
  expect_lt(abs(stats$beta - 1.2), 0.3)  # Beta close to true value
  expect_gt(stats$r2, 0)                 # R2 positive
})
```

## Mocking

**Framework:** Custom mock helper functions in `helper-mock-data.R`

**Patterns:**
```R
# Basic mock generator
create_mock_model_data <- function(n_estimation = 120, n_event = 11) {
  set.seed(42)
  n_total = n_estimation + n_event
  index_returns = rnorm(n_total, mean = 0.0003, sd = 0.015)
  firm_returns = 0.001 + 1.2 * index_returns + rnorm(n_total, sd = 0.01)

  tibble::tibble(
    firm_returns = firm_returns,
    index_returns = index_returns,
    estimation_window = c(rep(1, n_estimation), rep(0, n_event)),
    event_window = c(rep(0, n_estimation), rep(1, n_event)),
    relative_index = c(seq(-n_estimation, -1), seq(0, n_event - 1)),
    event_date = c(rep(0, n_estimation), 1, rep(0, n_event - 1))
  )
}
```

**Available Mock Functions in `helper-mock-data.R`:**
- `create_mock_firm_data()` - Synthetic stock price data with random walk
- `create_mock_index_data()` - Index/reference data
- `create_mock_request()` - Event specification tibble
- `create_mock_task()` - Complete EventStudyTask with n firms
- `create_mock_task_with_factors()` - EventStudyTask with Fama-French factors
- `create_fitted_mock_task()` - Pre-fitted task (convenience for integration tests)
- `create_mock_model_data()` - Pure model-fitting test data (no event structure)

**What to Mock:**
- External data sources (stock prices, indices, factors) → use synthetic data generators
- Time series data with known properties (e.g., seed-based reproducibility)
- Event specifications (dates, windows, firms)

**What NOT to Mock:**
- Core R6 objects (MarketModel, EventStudyTask) → instantiate directly
- Statistical calculations → use real implementations
- Assertions on computed values → use actual statistical tests

## Fixtures and Factories

**Test Data:**
```R
# Fixture factory pattern: function returns complete test object
create_mock_task <- function(n_firms = 2, group = "TestGroup") {
  symbols = paste0("FIRM_", LETTERS[1:n_firms])
  firm_data = create_mock_firm_data(symbols = symbols)
  index_data = create_mock_index_data()
  request = create_mock_request(firm_symbols = symbols, group = group)
  EventStudyTask$new(firm_data, index_data, request)
}

# Used in tests:
test_that("EventStudyTask initializes correctly", {
  task = create_mock_task()
  expect_true(inherits(task, "EventStudyTask"))
  expect_equal(nrow(task$data_tbl), 2)
})
```

**Location:**
- All fixtures in `tests/testthat/helper-mock-data.R`
- Automatically loaded by testthat before running test files
- Organized by logical groups (firm data, index data, tasks, models)

**Reproducibility:**
- Fixtures use `set.seed()` at definition for consistent random data
- Deterministic sequences for dates and event specifications
- No randomness in fixture construction (only in bootstrap tests with explicit seeds)

## Coverage

**Requirements:** 
- No explicit coverage target configured in DESCRIPTION
- `covr` package listed in Suggests for coverage analysis
- Recent commits indicate extensive testing (e.g., "Fix 18 edge case bugs from round 12 audit, add 10 regression tests")

**View Coverage:**
```bash
# In R session
covr::package_coverage()
covr::report()

# With traceback to see untested lines
covr::to_cobertura()
```

## Test Types

**Unit Tests:**
- Scope: Individual model classes, test statistics, utility functions
- Location: `test_models.R`, `test_bootstrap.R`, `test_single_event_statistics.R`, etc.
- Approach: Create mock data → initialize object → call method → assert result
- Example: Test that `MarketModel$fit()` computes beta close to known value

**Integration Tests:**
- Scope: Full EventStudyTask pipeline (prepare → fit → calculate)
- Location: `test_task.R`, `test_execute.R`, broader functionality tests
- Approach: Use `create_fitted_mock_task()` → run full workflow → extract/assert results
- Example: Test that `run_event_study()` produces all expected output columns

**E2E Tests:**
- Not explicitly named/separated
- Vignettes in `vignettes/` serve as end-to-end examples
- Comprehensive test coverage of real workflows via integration tests
- No formal E2E test framework detected

## Common Patterns

**Async Testing:**
Not applicable (R is single-threaded by default)

**Error Testing:**
```R
# Expect errors with specific message patterns
test_that("MarketModel set_formula rejects non-formula", {
  mm = MarketModel$new()
  expect_error(mm$set_formula("not a formula"), "Input must be a formula")
})

# Expect warnings
test_that("MarketModel returns NA when not fitted", {
  mm = MarketModel$new()
  data = create_mock_model_data()

  expect_warning(
    result <- mm$abnormal_returns(data),
    "not fitted"
  )
  expect_true(all(is.na(result$abnormal_returns)))
})
```

**Edge Case Testing:**
- Dedicated file: `test_edge_cases.R`
- Tests include:
  - Single event in group (n=1 for sd-based stats)
  - NA propagation in abnormal returns
  - Zero variance scenarios
  - Division by zero guards
  - Degenerate inputs (constant values, all positive/negative)
  - Empty windows

**Example edge case test:**
```R
test_that("CSectTTest with single event produces NA for sd-based stats", {
  data = tibble::tibble(
    event_id = "E1",
    firm_symbol = "F1",
    relative_index = -5:5,
    abnormal_returns = rnorm(11, mean = 0.01, sd = 0.02),
    event_window = 1,
    estimation_window = 0
  )

  csect = CSectTTest$new()
  result = csect$compute(data, NULL)

  expect_equal(nrow(result), 11)
  # sd() of single value is NA, so aar_t should be NA/NaN
  expect_true(all(is.na(result$aar_t) | is.nan(result$aar_t)))
  expect_true(all(is.finite(result$aar)))
})
```

**Reproducibility Testing:**
```R
# Seed-based reproducibility for stochastic functions
test_that("bootstrap seed reproducibility", {
  task <- create_fitted_mock_task()
  r1 <- bootstrap_test(task, n_boot = 19, seed = 123)
  r2 <- bootstrap_test(task, n_boot = 19, seed = 123)

  expect_equal(r1$boot_p_aar, r2$boot_p_aar)
  expect_equal(r1$boot_p_caar, r2$boot_p_caar)
})
```

## Test File Locations

**Core Model Tests:**
- `tests/testthat/test_models.R` - R6 model classes (MarketModel, GARCH, etc.)
- `tests/testthat/test_models_time_varying.R` - Time-varying models (RollingWindow, DCC-GARCH)

**Statistical Test Coverage:**
- `tests/testthat/test_single_event_test_statistics.R` - AR, CAR, BHAR tests
- `tests/testthat/test_multi_event_statistics.R` - AAR, CAAR, CSect, Patell, BMP, KP tests
- `tests/testthat/test_ar_car_test_statistics.R` - Specific AR/CAR test implementations

**Task and Pipeline:**
- `tests/testthat/test_task.R` - EventStudyTask initialization, validation, data access
- `tests/testthat/test_execute.R` - Full pipeline execution
- `tests/testthat/test_prepare.R` - Data preparation step

**Advanced Features:**
- `tests/testthat/test_bootstrap.R` - Wild bootstrap inference
- `tests/testthat/test_panel.R` - Panel/DiD event studies
- `tests/testthat/test_synthetic_control.R` - Synthetic control methods
- `tests/testthat/test_intraday.R` - Intraday event studies

**Utilities and Edge Cases:**
- `tests/testthat/test_edge_cases.R` - Comprehensive edge case and error condition testing
- `tests/testthat/test_diagnostics.R` - Diagnostic functions
- `tests/testthat/test_export.R` - Export to CSV/Excel/LaTeX
- `tests/testthat/test_plotting.R` - Visualization functions
- `tests/testthat/test_data_download.R` - Data retrieval helpers

## Testing Statistics

- **Total test files:** 27
- **Total tests:** Approximately 400+ test cases (based on grep count)
- **Recent regression:** Tests added for discovered bugs (rounds 11-14 audits documented in recent commits)
- **Coverage:** Heavy coverage of edge cases and statistical correctness

---

*Testing analysis: 2026-09-02*
