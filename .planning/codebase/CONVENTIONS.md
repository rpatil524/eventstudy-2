# Coding Conventions

**Analysis Date:** 2026-09-02

## Naming Patterns

**Files:**
- R source files in `R/` directory use snake_case (e.g., `models.R`, `bootstrap.R`, `multi_event_test_statistics.R`)
- Test files in `tests/testthat/` use `test_*.R` naming (e.g., `test_models.R`, `test_bootstrap.R`)
- Helper test files use `helper-*.R` (e.g., `helper-mock-data.R`)

**Functions:**
- Public functions use snake_case (e.g., `run_event_study()`, `bootstrap_test()`, `calculate_statistics()`, `fit_model()`)
- Private/internal functions (decorated with `@noRd`) use leading dot + snake_case (e.g., `.initialize_and_fit_model()`, `.calculate_abnormal_returns()`, `.check_data_input()`)
- S3 methods follow R convention (e.g., `print.EventStudyTask`, `tidy.EventStudyTask`)

**Variables:**
- Local variables and parameters use snake_case (e.g., `estimation_window`, `abnormal_returns`, `firm_symbol`, `event_id`)
- Temporary variables in data pipelines often abbreviated (e.g., `data`, `tbl`, `result`)
- Configuration/option variables use snake_case (e.g., `use_hac`, `weight_type`, `n_boot`)

**Types/Classes:**
- R6 classes use PascalCase (e.g., `MarketModel`, `EventStudyTask`, `ParameterSet`, `CSectTTest`, `KolariPynnonenTest`)
- Class names are descriptive and domain-specific (statistical test names match academic literature)
- Inheritance follows `ClassName <- R6Class("ClassName", inherit = ParentClass, ...)`

**Constants:**
- Global variables (in `globalVariables()`) use snake_case (e.g., `aar`, `car`, `caar`, `abnormal_returns`)
- These are declared in `EventStudy-package.R` to suppress R CMD check NSE warnings

## Code Style

**Formatting:**
- No explicit linting config file detected (`.lintr`, `.Rprofile` not found)
- Uses roxygen2 for documentation (RoxygenNote: 7.3.3)
- Indentation follows base R convention (2-space standard)
- Long lines present in code, no strict line-length enforcement observed

**Linting:**
- No configuration for lintr, styler, or similar tools
- Package uses base R + tidyverse style informally

## Import Organization

**Order in files:**
1. roxygen2 tags (`#' @import`, `#' @importFrom`)
2. Internal library loads (e.g., `library(R6)`, `library(dplyr)`)
3. Function definitions (public then private)

**Roxygen imports (EventStudy-package.R):**
```R
#' @import R6
#' @importFrom dplyr %>% mutate filter select n ...
#' @importFrom tibble as_tibble
#' @importFrom rlang .data %||%
#' @importFrom stats sd lm na.omit shapiro.test ...
```

**Style:**
- Heavy use of tidyverse (`dplyr`, `tidyr`, `purrr`)
- Pipe operator `%>%` used throughout for data transformations
- NSE (non-standard evaluation) used extensively with `dplyr` verbs

**Path Aliases:**
- No explicit path aliases configured
- Relative imports use `library()` for attached packages

## Error Handling

**Patterns:**
- `stop()` for fatal errors with descriptive messages (e.g., `stop("task must be an EventStudyTask.")`)
- Error messages typically include the context and what went wrong
- `inherits()` for type checking before operations (e.g., `if (!inherits(task, "EventStudyTask"))`)
- `match.arg()` for parameter validation (e.g., `weight_type <- match.arg(weight_type, c("rademacher", "mammen"))`)
- `warning()` for non-fatal issues (e.g., in model fitting when data is not fitted)

**Examples from `task.R`:**
```R
stop("Abnormal returns have not been calculated yet. Run fit_model() first.")
stop("Event ID '", event_id, "' not found.")
stop("Request file missing columns: ", paste(missing_cols, collapse = ", "))
```

**Examples from `bootstrap.R`:**
```R
if (!inherits(task, "EventStudyTask")) {
  stop("task must be an EventStudyTask.")
}
weight_type <- match.arg(weight_type, c("rademacher", "mammen"))
```

## Logging

**Framework:** `cat()` and `message()` for user-facing output

**Patterns:**
- `print()` methods defined for R6 classes to display summaries (e.g., `ParameterSet$new()$print()`)
- Print methods use `cat()` for formatted output
- `message()` used occasionally for informational output
- No structured logging framework; relies on base R output functions

**Example from `parameter_set.R`:**
```R
print = function(...) {
  cat("EventStudy ParameterSet\n")
  cat("  Return calculation:", self$return_calculation$name, "\n")
  cat("  Return model:     ", self$return_model$model_name, "\n")
}
```

## Comments

**When to Comment:**
- Roxygen2 `#'` tags used for all public functions (mandatory for documentation)
- Inline comments used for complex logic sections (e.g., statistical calculations)
- Comments explain WHY, not WHAT: avoid restating code
- Comments used for edge case handling or data transformations

**Example from `models.R`:**
```R
# Constant market returns: no OLS correction possible,
# fall back to constant-mean FEC
if (ss_market < .Machine$double.eps) {
  forecast_error_corrected_sigma <- ...
}
```

**JSDoc/Roxygen:**
- All exported functions (marked `@export`) have roxygen documentation
- Documentation includes:
  - `@title` - Short function description
  - `@description` - Detailed explanation
  - `@param` - Parameter documentation with types and meaning
  - `@return` - Return value description
  - References to academic papers where applicable

**Example from `bootstrap.R`:**
```R
#' @param task A fitted EventStudyTask with abnormal returns computed.
#' @param n_boot Number of bootstrap replications. Default 999.
#' @param weight_type Type of bootstrap weights: \code{"rademacher"} (default,
#'   +1/-1 with equal probability) or \code{"mammen"} (Mammen two-point
#'   distribution).
#' @return A tibble with columns: \code{relative_index}, \code{observed_aar},
#'   \code{observed_caar}, \code{boot_p_aar}, \code{boot_p_caar}.
```

## Function Design

**Size:**
- Functions range from small helpers (10-20 lines) to large implementations (100+ lines)
- Larger functions like `run_event_study()` in `execute.R` typically compose smaller steps
- No strict size limit enforced

**Parameters:**
- Functions typically have 2-5 parameters
- Complex workflows use R6 classes with initialized state rather than many parameters
- Optional parameters use `NULL` as default with type checking
- Named parameters preferred over positional in complex functions

**Return Values:**
- Public functions return the modified object or result tibble
- Void operations return `invisible(self)` for chaining or suppressing output
- Bootstrap functions return tibbles with standardized column names
- Model fitting returns R6 objects with updated internal state

**Example pattern (from `execute.R`):**
```R
run_event_study = function(task, parameter_set = ParameterSet$new()) {
  task = prepare_event_study(task, parameter_set)
  task = fit_model(task, parameter_set)
  task = calculate_statistics(task, parameter_set)
  task  # implicit return
}
```

## Module Design

**Exports:**
- All user-facing classes and functions marked with `@export`
- Internal utilities marked with `@noRd` (no Rd documentation generated)
- Private class methods use `private = list(...)` within R6 class definitions

**Barrel Files:**
- `EventStudy-package.R` serves as package documentation and imports declaration
- Contains `globalVariables()` to suppress NSE warnings for all dplyr/ggplot2 column usage
- No traditional barrel exports; namespace managed by NAMESPACE file (generated by roxygen2)

**R6 Class Pattern:**
All models and task objects follow R6 pattern with:
- `public` list containing user-facing methods and fields
- `private` list for internal state and helper methods
- `active` bindings for computed or read-only properties
- `initialize()` method for construction with validation

**Example (from `models.R`):**
```R
ModelBase <- R6Class("ModelBase",
  public = list(
    model_name = "",
    fit = function(data_tbl) { ... },
    abnormal_returns = function(data_tbl) { ... }
  ),
  active = list(
    statistics = function(value) {
      if (missing(value)) {
        private$.statistics
      } else {
        stop("`$statistics` is read only", call. = FALSE)
      }
    }
  ),
  private = list(
    .is_fitted = FALSE,
    .statistics = list(...)
  )
)
```

---

*Convention analysis: 2026-09-02*
