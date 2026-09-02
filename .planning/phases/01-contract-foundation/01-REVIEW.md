---
phase: 01-contract-foundation
reviewed: 2026-09-02T00:00:00Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - R/contract.R
  - R/models.R
  - R/parameter_set.R
  - R/execute.R
  - tests/testthat/test_contract.R
  - tests/testthat/test_parameter_set.R
  - tests/testthat/helper-mock-data.R
  - tests/testthat/test_edge_cases.R
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-09-02
**Depth:** deep
**Files Reviewed:** 8
**Status:** issues_found

## Summary

The Phase 1 contract implementation is structurally sound. The core degenerate-input guards in `MarketModel` are logically correct: the insufficient-observations guard (`n_valid < 2`) correctly counts joint non-NA pairs matching what `lm()` sees via `na.omit`; the zero-variance guard (`sd < .Machine$double.eps`) with `na.rm=TRUE` fires correctly for constant series and is pre-empted by the `n_valid` guard for all-NA inputs; and the safe `purrr::safely` path for lm() failures uses `.handle_degenerate` correctly with `stop()` sitting outside the `safely` wrapper so it propagates correctly.

The mode-resolution logic is clean: NULL ParameterSet field → option → default "lenient" works correctly. The `seq_len(nrow(...))` threading in `execute.R` is correct and deterministic. CONTRACT-05 baseline test design (no hard-coded numerics) is correct.

Three warnings and three info items require attention. The highest-severity concern is a behavioral gap: the degenerate contract is only wired to `MarketModel` — the six other OLS-family models (`LinearFactorModel`, `FamaFrench3FactorModel`, `FamaFrench5FactorModel`, `Carhart4FactorModel`, `MarketAdjustedModel`, `ComparisonPeriodMeanAdjustedModel`) bypass it entirely. `strict` mode silently has no effect on these models.

---

## Warnings

### WR-01: Strict mode silently ignored for LinearFactorModel family and other models

**Files:** `R/models.R:531-553` (LinearFactorModel), `R/models.R:352-364` (MarketAdjustedModel), `R/models.R:425-435` (ComparisonPeriodMeanAdjustedModel), `R/models.R:984-993` (BHARModel)

**Issue:** `LinearFactorModel$fit()` (and all subclasses: FF3, FF5, Carhart4) does not call `.resolve_degenerate_mode()` or `.handle_degenerate()`. When `degenerate_handling = "strict"` is set on the `ParameterSet`, users expect a `stop()` on degenerate inputs for all models. Instead these models always emit a plain `warning()` regardless of mode, and the `event_id`/`firm_symbol` context fields (injected by `execute.R` into the clone) are never read. This is a silent contract violation: a user who sets strict mode to fail fast on any degenerate input will miss degenerate FF3/FF5/Carhart events entirely.

Additionally, `VolumeModel`, `VolatilityModel`, `GARCHModel`, and `BHARModel` also bypass the contract (they use direct `warning()` calls that ignore `self$degenerate_mode` and omit `event_id`/`firm_symbol` from messages).

The phase plan explicitly describes this as "Phase 2 models" for the contract extension, so this is a known gap. The risk is that no user-visible notice exists that strict mode is silently partial — users will set strict mode believing it covers all model types.

**Fix:** For Phase 2, wire each model through `.handle_degenerate()`. For Phase 1 as-shipped, at minimum document the limitation in `?degenerate-input-contract` with an explicit list of which models honor the contract.

```r
# In contract.R documentation, add:
# \strong{Models covered in Phase 1:} \code{MarketModel} only.
# \code{LinearFactorModel}-based models (\code{FamaFrench3FactorModel},
# \code{FamaFrench5FactorModel}, \code{Carhart4FactorModel}) and
# \code{MarketAdjustedModel}, \code{ComparisonPeriodMeanAdjustedModel},
# \code{BHARModel}, \code{VolumeModel}, \code{VolatilityModel},
# and \code{GARCHModel} use direct \code{warning()} and are not
# yet covered by \code{strict} mode. Phase 2 will extend the contract.
```

---

### WR-02: Second "not fitted" warning emitted by `abnormal_returns()` after degenerate `fit()`

**File:** `R/models.R:254`

**Issue:** The lenient-mode contract emits exactly one contract-formatted warning from `fit()` per degenerate `(event_id, firm_symbol)`. However, `MarketModel$abnormal_returns()` at line 254 unconditionally emits a second unformatted warning (`"MarketModel is not fitted. Returning NA abnormal returns."`) when `is_fitted = FALSE`. In the pipeline, `fit_model()` immediately calls `abnormal_returns()` for every model after fitting (line 52-55 of `execute.R`), so every degenerate event generates two warnings in the user's session — one contract-formatted, one not.

The CONTRACT-04 pipeline test at line 249 of `test_contract.R` only counts warnings matching `"[firm=FIRM_B]"` (the contract-formatted one), so it passes, but a user will see two warnings instead of one. This contradicts the contract's stated goal of "exactly one `warning()` per `(event_id, firm_symbol)` per fit call" when interpreted across the full `fit_model()` call.

**Fix:** Guard `abnormal_returns()` to suppress the secondary warning if a contract-formatted warning was already emitted. The simplest approach is to check `is_fitted` silently without warning when called from the pipeline:

```r
# Option A: Remove the secondary warning from abnormal_returns() since
# the contract warning from fit() already informed the user.
abnormal_returns = function(data_tbl) {
  if (private$.is_fitted) {
    alpha = private$.statistics$alpha
    beta  = private$.statistics$beta
    data_tbl %>%
      mutate(abnormal_returns = firm_returns - (alpha + beta * index_returns))
  } else {
    # Silent NA propagation; fit() already emitted the contract warning.
    data_tbl %>%
      mutate(abnormal_returns = NA_real_)
  }
}
```

---

### WR-03: `match.arg()` return value discarded in `ParameterSet$initialize()`

**File:** `R/parameter_set.R:66`

**Issue:** The validation call `match.arg(degenerate_handling, c("lenient", "strict"))` at line 66 is used only for its error-throwing side effect — its normalized return value is discarded. The raw user-supplied string (which may be a partial match like `"s"` or `"len"`) is then stored in `self$degenerate_handling`. While `.resolve_degenerate_mode()` applies `match.arg()` again at resolution time and handles partial matching correctly, storing the un-normalized value is surprising and could confuse downstream code that inspects `ps$degenerate_handling` directly (e.g., it would see `"s"` instead of `"strict"`).

**Fix:** Store the normalized value:

```r
if (!is.null(degenerate_handling)) {
  degenerate_handling <- match.arg(degenerate_handling, c("lenient", "strict"))
}
self$degenerate_handling <- degenerate_handling
```

---

## Info

### IN-01: `degenerate_mode`/`event_id`/`firm_symbol` fields re-declared in `MarketModel` — redundant with `ModelBase`

**File:** `R/models.R:149-155`

**Issue:** `ModelBase` declares `degenerate_mode`, `event_id`, and `firm_symbol` as public fields at lines 17-23. `MarketModel` re-declares the same three fields at lines 149-155 with identical initial values (`NULL`). In R6, a subclass field declaration with the same name shadows the parent's slot, resulting in effectively one slot (not two). There is no runtime bug: `execute.R`'s injection and `MarketModel$fit()`'s reads all operate on the same slot. However, the redundant declarations create misleading documentation (both `ModelBase` and `MarketModel` roxygen docs describe the same conceptual field), increase surface area for drift, and could confuse future contributors extending `ModelBase`.

**Fix:** Remove the three re-declarations from `MarketModel`. The fields are already available via inheritance from `ModelBase`.

```r
# Remove from MarketModel's public list:
# degenerate_mode = NULL,   # inherited from ModelBase
# event_id = NULL,          # inherited from ModelBase
# firm_symbol = NULL,       # inherited from ModelBase
```

---

### IN-02: Package option name `"eventstudy.degenerate_handling"` uses lowercase while package is `EventStudy`

**File:** `R/contract.R:23,56`

**Issue:** The package is named `EventStudy` (PascalCase per DESCRIPTION). The package option uses `eventstudy.` (all-lowercase prefix). R option names are case-sensitive; a user who guesses `options(EventStudy.degenerate_handling = "strict")` will be silently ignored. This inconsistency increases discoverability friction. Common R conventions for package options use either the exact package name or all-lowercase — the inconsistency here is that neither convention is followed consistently (package = `EventStudy`, option prefix = `eventstudy`).

**Fix:** Standardize to `EventStudy.degenerate_handling` or document the lowercase form explicitly in the help page. If changing, update both occurrences in `contract.R` and all test uses of `eventstudy.degenerate_handling` in `test_contract.R`.

---

### IN-03: `withr` not declared in `DESCRIPTION Suggests`

**File:** `tests/testthat/test_contract.R:16,28,36,57,60`; `DESCRIPTION:45-62`

**Issue:** `test_contract.R` uses `withr::with_options()` in five tests. `withr` is not listed in `DESCRIPTION`'s `Suggests` section. In practice this is safe because `withr` is in `testthat`'s `Imports` (transitively available during testing), and `R CMD check` typically does not flag transitive test dependencies. However, best CRAN practice is to declare all directly-called packages in `Suggests`.

**Fix:** Add `withr` to `DESCRIPTION Suggests`:

```
Suggests:
    testthat (>= 3.0.0),
    withr,
    ...
```

---

_Reviewed: 2026-09-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
