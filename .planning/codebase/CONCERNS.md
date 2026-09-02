# Codebase Concerns

<!-- refreshed: 2026-09-02 -->

**Analysis Date:** 2026-09-02

## Tech Debt

**Many-to-Many Join Bugs in Multi-Event Test Statistics (GH #7 - Recently Fixed):**
- Issue: `BMPTest`, `KolariPynnonenTest`, and `PatellZTest` joined per-event model tables on `firm_symbol` instead of `event_id`. When a firm appeared in multiple events, the join created many-to-many duplicates, inflating `n_events` and test statistics (`bmp_t`, `kp_t`, `aar_z`) by roughly sqrt(events-per-firm).
- Files: `R/multi_event_test_statistics.R` (lines 86-160 for PatellZTest, BMP/KP implementations)
- Fix Approach: Key all per-event aggregations on `event_id` (the unit of model fitting) rather than `firm_symbol`. Already applied in commit 63d67a1 but represents a pattern risk in other multi-event operations.
- Status: Fixed but similar pattern should be audited in other test statistics.

**High Frequency of Edge Case Bugs Across Multiple Audit Rounds:**
- Issue: 14 recent audit rounds (commits 97375f2 through 99b9518) have collectively fixed 100+ edge case bugs, indicating systemic issues with boundary condition handling.
- Files: Multiple - diagnostics, models, models_time_varying, panel_event_study, synthetic_control, export
- Categories of Bugs Fixed:
  - Insufficient estimation observations (<2 observations) in MarketAdjusted/ComparisonPeriodMeanAdjusted/BHAR/VolumeModel
  - Zero variance leading to infinite/NaN statistics (pretrend_test, division-by-zero guards missing)
  - NA propagation in cumsum operations (CSectTTest, export tidy methods)
  - Numerical overflow in softmax (synthetic_control.R)
  - Missing na.rm flags in aggregations
  - Incorrect degree_of_freedom counting (VolumeModel, VolatilityModel, RollingWindowModel)
- Impact: Users with edge case data (degenerate inputs, single events, zero variance) experience crashes or incorrect results.
- Fix Approach: Each model's fit/calculate_statistics must guard against:
  1. Insufficient observations (check nrow >= min_required)
  2. Zero variance (check sd > .Machine$double.eps before division)
  3. NA propagation (use coalesce() in cumsum chains)
  4. Correct df calculation (count only finite values)

## Known Bugs

**Degenerate Input Handling Inconsistency:**
- Symptoms: Some models set `is_fitted=FALSE` on degenerate input; others produce NaN/Inf values. Test suite has 110+ edge case tests (test_edge_cases.R) suggesting ongoing issues.
- Files: `R/models.R`, `R/models_time_varying.R`
- Trigger: Data with <2 observations in estimation window, zero variance, or single event
- Workaround: Pre-filter input data to ensure minimum observations; check for zero variance before model fit
- Root Cause: Inconsistent validation patterns across 13 model types (MarketModel, MarketAdjusted, FF3, FF5, Carhart4, GARCH, BHAR, Volume, Volatility, RollingWindow, DCC-GARCH, ComparisonPeriodMean, Custom)

**Panel Event Study Clustering/Standard Error Calculation:**
- Symptoms: Cluster-robust standard errors only computed if `sandwich` package installed; fallback to non-robust SEs without warning
- Files: `R/panel_event_study.R` (lines 164-172, 409-426 for Callaway-Sant'Anna)
- Trigger: Running panel estimator without `sandwich` installed
- Workaround: Install `sandwich` package
- Notes: Function warns about missing package but continues with non-robust inference, potentially misleading users about precision

**DIDmultiplegt Package Compatibility and Segfault Issues:**
- Symptoms: Segmentation faults on macOS arm64 when loading DIDmultiplegt; API varies across versions producing parsing failures
- Files: `R/panel_event_study.R` (lines 456-475), `tests/testthat/test_panel.R` (lines 217-251)
- Trigger: Running `estimate_panel_event_study(..., method='de_chaisemartin_dhaultfoeuille')` on macOS or with version mismatch
- Workaround: Test package load in subprocess before use (done in CI); wrap result parsing in tryCatch
- Risk Level: High - produces silent failures or runtime crashes during model estimation

**RollingWindowModel Degree of Freedom Calculation Bug (Recently Fixed):**
- Symptoms: degree_of_freedom sometimes incorrect when using rolling windows with NAs
- Files: `R/models_time_varying.R` (lines 124-148)
- Fix: Line 76 now counts only finite residuals instead of total length
- Impact: Affects statistical inference (standard errors, t-statistics) from rolling window models

**Pretrend Test Zero Variance Guard (Recently Fixed):**
- Symptoms: sd=0 in pre-trend test produces Inf t_stat instead of NA
- Files: `R/diagnostics.R` (line 138)
- Fix: Added `sd_ar < .Machine$double.eps` guard
- Impact: Diagnostics crash or produce invalid results for constant pre-event returns

## Security Considerations

**External Data Download Dependencies:**
- Risk: `download_stock_data()` and `download_factor_data()` rely on external services (Yahoo Finance, Kenneth French Data Library) with no retry logic or timeout controls
- Files: `R/data_download.R` (lines 23-74)
- Current Mitigation: Fallback from tidyquant to quantmod; error handling with warnings
- Recommendations:
  1. Add request timeouts and retry logic
  2. Validate downloaded data completeness before returning
  3. Cache factor data locally with version tracking
  4. Document data provider dependencies and potential outages

**Optional Package Dependencies Without Clear Guarantees:**
- Risk: Critical features require optional packages not installed (rugarch for GARCH, sandwich for robust SEs, did for Callaway-Sant'Anna)
- Files: `R/models_time_varying.R` (206-208), `R/cross_sectional.R` (60-75), `R/panel_event_study.R` (409-411)
- Current Mitigation: `requireNamespace()` checks with informative error messages
- Recommendations:
  1. Document required vs optional packages in function docstrings
  2. Add startup check to warn about missing optional dependencies
  3. Consider moving high-value packages to Imports

## Performance Bottlenecks

**Panel Event Study with Large N (Units) or T (Periods):**
- Problem: Fixed-effects estimation scales as O(N*T) in memory; absorbing fixed effects requires dense matrix operations
- Files: `R/panel_event_study.R` (entire file for TWFE/Sun-Abraham implementations)
- Current Capacity: Untested with N>100,000 or T>1000
- Scaling Path: Consider sparse matrix implementations or iterative algorithms (e.g., Frisch-Waugh-Lovell for demeaning)

**Synthetic Control Quadprog Optimization:**
- Problem: Quadratic programming solver scales poorly with large donor pools (n_donors^2 memory for Hessian)
- Files: `R/synthetic_control.R` (lines 144-200)
- Current Capacity: Untested with >1000 donors
- Scaling Path: Implement ridge regression alternative or incremental solver for large donor pools

**Multi-Event Test Statistics Aggregation:**
- Problem: CSectTTest, PatellZTest, BMP, KP group-by operations on large datasets (e.g., 10K events × 100K firms) create memory bloat
- Files: `R/multi_event_test_statistics.R` (dplyr group_by chains)
- Current Capacity: Likely O(N*M) memory for N events × M firms
- Scaling Path: Implement chunked computation or streaming aggregation

## Fragile Areas

**Complex Many-to-Many Join Logic in Test Statistics:**
- Files: `R/multi_event_test_statistics.R` (BMPTest, KolariPynnonenTest, PatellZTest compute methods)
- Why Fragile: Model tables keyed by event_id must join correctly on multi-field keys (event_id, event_window, relative_index). Many-to-many joins from ~GH #7 are error-prone.
- Safe Modification: Always verify join keys explicitly in tests; use `dplyr::anti_join()` to detect unmatched rows after joining
- Test Coverage: Edge cases partially covered in test_edge_cases.R; add regression tests for firms appearing in 2+ events

**Time-Varying Model Parameter Extraction:**
- Files: `R/models_time_varying.R` (entire RollingWindowModel, DCCGARCHModel classes)
- Why Fragile: Complex initialization and parameter extraction from rolling windows or rugarch models; sensitive to data ordering and NA handling
- Safe Modification: Add explicit length checks before tail()/head() operations; validate parameter matrices have correct dimensions
- Test Coverage: Minimal coverage for GARCH models; only basic tests in test_models_time_varying.R

**Panel Event Study Estimator Selection and Result Extraction:**
- Files: `R/panel_event_study.R` (lines 400-500 covering TWFE, Callaway-Sant'Anna, BJS, dCDH, DIDmultiplegt)
- Why Fragile: Each estimator has different output structure; API changes in external packages (did, DIDmultiplegt) break parsing logic
- Safe Modification: Wrap external package calls in tryCatch with informative error messages; maintain version-specific result extraction logic
- Test Coverage: Partial - CI skips DIDmultiplegt tests on macOS due to segfault; didimputation tests added recently

**Export and Tidy Methods with NA/Sigma Guarding:**
- Files: `R/export.R` (lines 246-315), `R/task_validation.R` (tidy methods)
- Why Fragile: Cumsum with coalesce() is correct pattern but must be applied consistently; if() statements crash on NA values
- Safe Modification: Always use is.na() guards before if() statements; prefer tidyverse verbs (replace_na, coalesce) over base if()
- Test Coverage: test_export.R has limited edge case tests; needs expansion for NA propagation scenarios

**Numerical Stability in Softmax and Matrix Operations:**
- Files: `R/synthetic_control.R` (softmax implementation, lines 136-150)
- Why Fragile: exp(theta) can overflow; sqrt() and log() operations require domain checks
- Safe Modification: Always subtract max(x) before exp(x); check denominators > .Machine$double.eps before division
- Test Coverage: Synthetic control tests limited; no stress tests with extreme parameter values

## Scaling Limits

**Memory Usage with Large Cross-Sectional Datasets:**
- Current Capacity: Untested with >1M firm-days of data; tibble operations assume data fits in RAM
- Limit: R tibbles loaded fully into memory; no lazy evaluation
- Scaling Path: Implement data.table backend for large datasets; add streaming computation for AAR/CAAR calculations

**Computational Complexity of Cross-Sectional Regression:**
- Current Capacity: Cross-sectional regression (cross_sectional.R) tested up to ~1K firms
- Limit: HC-robust covariance matrix computation O(N^2); scales poorly with many characteristics
- Scaling Path: Use sandwich::vcovHC sparse implementation; implement Cholesky decomposition caching

**Test Statistics Computation for Multi-Factor Models:**
- Current Capacity: Fama-French 5-factor models fit within reasonable time; untested with custom factor sets >10 factors
- Limit: QR decomposition for regression scales as O(N*K^2) where K=number of factors
- Scaling Path: Implement incremental QR updating; cache design matrices

## Dependencies at Risk

**rugarch Package Dependency for GARCH/DCC-GARCH Models:**
- Risk: rugarch is Suggests (optional) but essential for GARCH models; complex C++ code with compilation issues on some platforms
- Files: `R/models_time_varying.R` (lines 206-240)
- Impact: Users cannot fit GARCH models without successful rugarch install; compilation failures on rare architectures
- Migration Path: Consider pure-R GARCH implementation using optim(); trade compute time for portability

**did Package for Callaway-Sant'Anna Estimator:**
- Risk: did package API has changed; result structure parsing brittle
- Files: `R/panel_event_study.R` (lines 409-426)
- Impact: Estimator silently fails or returns malformed results when did package version changes
- Migration Path: Implement Callaway-Sant'Anna estimator natively in EventStudy to remove dependency

**DIDmultiplegt Package for de Chaisemartin-D'Haultfoeuille Estimator:**
- Risk: Segmentation faults on macOS arm64; API mismatch across versions; requires mode='old' parameter in recent versions
- Files: `R/panel_event_study.R` (lines 456-475), `tests/testthat/test_panel.R` (lines 217-251)
- Impact: Method unavailable or produces runtime crashes on affected platforms
- Migration Path: Implement dCDH estimator natively; use subprocess isolation for external package loads

**quantmod/tidyquant Data Download Dependency:**
- Risk: External service dependency (Yahoo Finance); no rate limiting or caching
- Files: `R/data_download.R`
- Impact: Download failures block analysis; no fallback to cached data
- Migration Path: Implement local cache with automatic updates; add fallback to alternative data sources

## Missing Critical Features

**No Streaming Computation for Large Datasets:**
- Problem: All aggregations (AAR, CAAR, test statistics) load full dataset into memory; no chunked processing
- Blocks: Users with >1M observation datasets cannot run analysis
- Approach: Implement Welford online algorithm for mean/variance; implement streaming quantile for quantile-based tests

**No Reproducible Result Serialization Format:**
- Problem: Results stored in S3/R6 objects; no standard format for sharing results between analyses or versions
- Blocks: Reproducibility across versions; sharing results between collaborators
- Approach: Implement JSON/HDF5 export format with schema versioning; add result metadata (package version, random seed, data hash)

**Limited Intraday Data Aggregation Support:**
- Problem: Intraday support exists but aggregation to daily/weekly/monthly not built-in
- Blocks: Users must manually aggregate before running analysis
- Approach: Add aggregate_intraday() function supporting multiple time resolutions

**No Simulation Power Analysis for Panel Estimators:**
- Problem: Power simulation exists for single-event tests but not for panel DiD estimators
- Blocks: Users cannot calculate required sample sizes for panel studies
- Approach: Extend simulate_event_study() to support panel designs with staggered treatment

## Test Coverage Gaps

**Edge Cases in NA Propagation:**
- What's Not Tested: Cumulative abnormal returns with alternating NAs (e.g., firm appears in event then drops out)
- Files: `R/multi_event_test_statistics.R` (CAR calculation in CSectTTest lines 40-46)
- Risk: Inconsistent NA behavior in cumsum chains; some test statistics may silently produce wrong CARs
- Priority: High - directly affects test statistic validity

**Panel Event Study with Unbalanced Panels:**
- What's Not Tested: Missing observations for some units in some periods; complex staggered treatment patterns with gaps
- Files: `R/panel_event_study.R`
- Risk: Estimators assume balanced data; gaps may produce incorrect within-transformation or treatment timing inference
- Priority: High - common in real data; users may not detect incorrect results

**GARCH Model with High-Volatility Periods:**
- What's Not Tested: Fitting GARCH during financial crises or high-volatility regimes; convergence failures
- Files: `R/models_time_varying.R`
- Risk: GARCH optimization may fail to converge; produces warning but continues with unfitted model
- Priority: Medium - affects subset of users; fallback to simpler models exists

**Cross-Sectional Regression with Collinearity:**
- What's Not Tested: Firm characteristics with perfect/near-perfect multicollinearity
- Files: `R/cross_sectional.R`
- Risk: lm() produces singular fit; robustness calculation may crash or produce Inf/NaN SEs
- Priority: Medium - defensive coding handles some cases but needs explicit tests

**Synthetic Control Donor Pool Composition Edge Cases:**
- What's Not Tested: Donors with identical or nearly-identical pre-treatment trajectories; donors with missing pre-treatment data
- Files: `R/synthetic_control.R`
- Risk: Quadprog fails or produces degenerate weights; optimization does not converge
- Priority: Low to Medium - affects specific use cases

---

*Concerns audit: 2026-09-02*
