---
phase: 05-offline-diagnostics-grounding-knowledge-base
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/es_diagnostics.R
  - tests/testthat/test_es_diagnostics.R
  - NAMESPACE
autonomous: true
requirements: [DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, DIAG-06, DIAG-07, CRAN-01, CRAN-05]
estimate:
  tokens: 70000
  raw_tokens: 38000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "es_diagnostics(task) on a fitted task returns a serializable es_diagnostics named list carrying estimation-window fit signals (R2, Durbin-Watson, Ljung-Box, Shapiro-Wilk, ACF1), event-window results (AR/CAR, AAR/CAAR, per-statistic values and p-values), cross-sectional signals (n_events, n_valid, CAR dispersion, overlap), and per-event v0.50.0 contract state (is_fitted, NA counts, zero-variance/insufficient-obs flags) [DIAG-01..05]"
    - "es_diagnostics() runs without error on a task containing degenerate/NA events and with no API key present, and its per-event payload is size-capped (default max_events=20) to bound token cost [DIAG-06, DIAG-07]"
    - "R CMD check shows zero new hard dependencies from this phase and existing valid-input pipeline behavior is byte-identical (advisor is purely additive) [CRAN-01, CRAN-05]"
  artifacts:
    - "R/es_diagnostics.R — es_diagnostics(), print.es_diagnostics(), .rank_events_for_cap(), .extract_* helpers"
    - "tests/testthat/test_es_diagnostics.R — DIAG-01 through DIAG-07 coverage"
    - "NAMESPACE — exports es_diagnostics and print.es_diagnostics S3 method"
  key_links:
    - "es_diagnostics reads task$data_tbl$model[[i]]$statistics (estimation signals) and task$data_tbl$ART/CART (event window) and task$aar_caar_tbl$CSectT (multi-event) — the harvest boundary"
    - "distributional dist objects in ART/CART columns must be reduced to plain scalar p-values via stats::pt() before entering the list, or the list is not JSON-serializable"
---

<objective>
Deliver the deterministic, zero-dependency `es_diagnostics()` harvester: a single exported function that reads already-computed signals from a fitted `EventStudyTask` and returns a serializable, S3-classed `es_diagnostics` named list, plus its `print` method. This is the always-available grounding foundation the KB (Plan 05-2) and offline advice (Plan 05-3) consume, and that the Phase 7 LLM layer will later interpret.

Purpose: Every downstream advice function needs a flat, JSON-ready feature vector of the fitted study. This plan is a pure HARVESTER — it recomputes nothing; all signals already exist in the fitted task per 05-RESEARCH.md.
Output: `R/es_diagnostics.R`, `tests/testthat/test_es_diagnostics.R`, regenerated NAMESPACE.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-CONTEXT.md
@.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-RESEARCH.md
@./.claude/CLAUDE.md
</context>

<artifacts_this_phase_produces>
This plan (05-1) produces:
- `es_diagnostics(task, max_events = 20L)` — exported harvester returning an `es_diagnostics` S3 named list
- `print.es_diagnostics(x, ...)` — exported S3 print method (cat-based, package convention)
- `.rank_events_for_cap(task)` — `@noRd` internal anomaly-ranking helper
- `.extract_estimation_signals()`, `.extract_event_window_signals()`, `.extract_cross_sectional_signals()`, `.extract_contract_state()`, `.aggregate_remainder()` — `@noRd` internal harvest helpers
- New file `R/es_diagnostics.R`
- New test file `tests/testthat/test_es_diagnostics.R`

Downstream plans (05-2 KB decision table, 05-3 recommend_stat/flag_robustness + Advice) depend on the `es_diagnostics` list shape defined here. The exact field names within the list are at Claude's discretion (per CONTEXT.md) but MUST be documented in the roxygen `@return` so 05-2/05-3 can rely on them.
</artifacts_this_phase_produces>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: End-to-end es_diagnostics tracer — one fitted task through harvest to printed S3 object</name>
  <files>R/es_diagnostics.R, tests/testthat/test_es_diagnostics.R, NAMESPACE</files>
  <read_first>
    - R/simulation.R:125-157 (S3-classed list + print.es_simulation convention to COPY exactly)
    - R/cross_sectional.R:130-191 (second instance of the same S3 + print pattern)
    - R/diagnostics.R:1-88 (model_diagnostics() — how estimation-window signals are reached; harvest pattern via purrr::pmap over task$data_tbl)
    - R/models.R:57-63 (model$is_fitted active binding), R/models.R:75-118 (private$.statistics fields incl. first_order_auto_correlation), R/models.R:264-330 (sigma/r2/degree_of_freedom/residuals)
    - tests/testthat/helper-mock-data.R:129-134 (create_fitted_mock_task() — runs full pipeline, returns a task with data_tbl$model, ART, CART, and aar_caar_tbl populated)
    - tests/testthat/test_diagnostics.R:1-87 (existing testthat 3e diagnostic test conventions)
  </read_first>
  <behavior>
    - Test 1 (RED first): es_diagnostics(create_fitted_mock_task()) returns an object where inherits(result, "es_diagnostics") is TRUE.
    - Test 2: result$meta$n_events_total equals nrow(task$data_tbl).
    - Test 3: result$estimation_window carries a numeric r2 vector (one entry per shown event), each finite or NA (never NULL), sourced from model$statistics$r2 %||% NA_real_.
    - Test 4: capture.output(print(result)) is non-empty and contains the header line "Event Study Diagnostics".
  </behavior>
  <action>
    Create R/es_diagnostics.R. Write ONE thin end-to-end path FIRST: exported es_diagnostics(task, max_events = 20L) that (a) type-checks inherits(task, "EventStudyTask") and stops with "task must be an EventStudyTask." (call. = FALSE) matching the package error convention, (b) stops with a clear message if "model" is not in names(task$data_tbl), (c) harvests ONLY the estimation-window r2 vector for now via model$statistics$r2 guarded by rlang %||% NA_real_ across task$data_tbl$model, (d) assembles a list with meta (n_events_total, n_events_shown, n_events_summarized, event_ids_shown) and estimation_window sub-lists, (e) sets class(result) <- "es_diagnostics". Add the exported print.es_diagnostics(x, ...) using cat() per the es_simulation convention, printing the "Event Study Diagnostics" header plus n_events_total and median r2, returning invisible(x). Roxygen: @export on both, @return documenting the top-level list shape (meta, estimation_window, event_window, cross_sectional, contract_state, aggregate_summary) even though only meta+estimation_window are populated in this tracer — later tasks fill the rest. Regenerate NAMESPACE with roxygen2. Do NOT add any package to Imports/Suggests. Create tests/testthat/test_es_diagnostics.R with the four behavior tests above using create_fitted_mock_task().
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_es_diagnostics.R")'</automated>
    <fails_when>testthat run reports any FAIL > 0, or Rscript exits non-zero (e.g. es_diagnostics undefined, print method not registered, or $r2 access errors on the fitted task).</fails_when>
  </verify>
  <acceptance_criteria>
    - R/es_diagnostics.R defines es_diagnostics() and print.es_diagnostics(), both with @export roxygen.
    - NAMESPACE contains export(es_diagnostics) and S3method(print,es_diagnostics).
    - testthat::test_file("tests/testthat/test_es_diagnostics.R") exits 0 with 0 failures.
    - No new entry added to DESCRIPTION Imports or Suggests (git diff DESCRIPTION is empty).
    - inherits(es_diagnostics(create_fitted_mock_task()), "es_diagnostics") is TRUE and its estimation_window$r2 is a plain numeric vector.
  </acceptance_criteria>
  <reversibility rating="reversible">New additive export; no existing behavior touched, trivially removable.</reversibility>
  <done>The single happy path — fitted task in, es_diagnostics S3 object out, print works, one test file green — is committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Expand the harvester to the full signal set (estimation, event-window, cross-sectional, contract)</name>
  <files>R/es_diagnostics.R, tests/testthat/test_es_diagnostics.R</files>
  <read_first>
    - R/diagnostics.R:24-88 (model_diagnostics inline computation of shapiro_p, dw_stat, ljung_box_p, acf1 from model$statistics$residuals — copy the formulas, do NOT add lmtest)
    - R/execute.R:99-163 (calculate_statistics transpose that creates task$data_tbl$ART / $CART columns named by test_statistic$name)
    - R/single_event_test_statistics.R:1-213 (ART/CART tibble columns: ar_t, ar_t_dist, car, car_t, car_t_dist; and the %||% NA_real_ guard at :66)
    - R/multi_event_test_statistics.R:26-59 (CSectT columns: relative_index, aar, n_events, n_valid_events, aar_t, caar, caar_t, car_window), :152-186 (PatellZ), :449-487 (BMP), :603-691 (KP)
    - R/task.R:16 (aar_caar_tbl = NULL until calculate_statistics runs — must guard), R/task.R:64 (date column stored as "dd.mm.yyyy" string)
    - R/models.R:184-213 (the two degenerate guards in MarketModel$fit — insufficient obs and zero variance in index_returns — replicate to derive degenerate_type from data)
    - 05-RESEARCH.md "Accessor Paths" sections 1-5 and "Common Pitfalls" 1-6 (verified field names and guards)
  </read_first>
  <behavior>
    - Test: estimation_window carries shapiro_p, dw_stat, ljung_box_p, acf1, sigma, degree_of_freedom vectors (all plain numeric, NA where unfitted).
    - Test: event_window carries, per shown event, scalar ar_t/car_t VALUES and their two-sided p-values as plain numerics (no distributional objects); jsonlite::toJSON(diag, null="null") does NOT error (guarded skip_if_not_installed("jsonlite") — Suggests-only, never a hard dep).
    - Test: cross_sectional carries n_events (= nrow data_tbl), n_valid_events (count is_fitted), car_iqr (stats::IQR of full-window CARs), car_sd, and n_overlap_pairs + any_overlap computed from as.Date(date,"%d.%m.%Y") interval intersection.
    - Test: contract_state carries per shown event is_fitted, na_ar_count (event window), na_est_count, insufficient_obs flag, zero_var_index flag.
    - Test: on create_mock_task() that is prepared+fitted but calculate_statistics NOT run (or aar_caar_tbl NULL), cross_sectional multi-event fields degrade to NA and es_diagnostics does not error.
  </behavior>
  <action>
    Expand es_diagnostics() into the documented six-section list by adding the @noRd internal harvest helpers named in artifacts_this_phase_produces. Estimation signals: reach model$statistics$residuals and recompute shapiro_p (stats::shapiro.test, wrapped in tryCatch → NA on <3 finite obs), dw_stat (the exact inline DW formula from R/diagnostics.R, not lmtest), ljung_box_p (stats::Box.test type="Ljung-Box"), acf1 (model$statistics$first_order_auto_correlation %||% NA_real_), plus sigma/r2/degree_of_freedom each guarded %||% NA_real_. Event-window: for each shown event, check "ART"/"CART" %in% names(task$data_tbl) before access (stat column names depend on ParameterSet — pitfall 3); pull scalar ar_t and car_t (final CART row) and convert their p-values via stats::pt(abs(t), df = degree_of_freedom, lower.tail = FALSE) * 2 — NEVER store *_dist objects (pitfall 1). Cross-sectional: n_events, n_valid_events, car_iqr/car_sd via stats::IQR/sd(na.rm=TRUE) over per-event final CARs, and n_overlap_pairs via the nested-loop calendar-date interval check using as.Date(date, "%d.%m.%Y") (pitfall 4), guarding is.null(task$aar_caar_tbl) (pitfall 2) so multi-event fields become NA when stats were not computed. Contract state: is_fitted, na_ar_count, na_est_count from the nested data tibble, and derive insufficient_obs / zero_var_index by replicating the two MarketModel$fit guards on the estimation window. Everything inside tryCatch so a single bad event never aborts the harvest (DIAG-07). Update print.es_diagnostics to also summarize median shapiro_p, median dw_stat, car_iqr, and n_overlap_pairs per the 05-RESEARCH print skeleton. Extend test_es_diagnostics.R with the behavior tests above.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_es_diagnostics.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. a distributional object leaks into the list (jsonlite::toJSON errors "cannot coerce class dist_student_t"), $aar_caar_tbl NULL crashes access, or string-date comparison yields NA overlap.</fails_when>
  </verify>
  <acceptance_criteria>
    - es_diagnostics() output has all six sections (meta, estimation_window, event_window, cross_sectional, contract_state, aggregate_summary) with the fields listed in behavior.
    - No distributional/dist_student_t object appears anywhere in the returned list (all p-values are plain numerics).
    - With jsonlite installed, jsonlite::toJSON(es_diagnostics(create_fitted_mock_task()), null="null") runs without error; test is skip_if_not_installed("jsonlite") guarded so jsonlite stays out of hard deps.
    - Calling es_diagnostics on a fitted task whose aar_caar_tbl is NULL returns NA cross-sectional multi-event fields and does not error.
    - testthat::test_file("tests/testthat/test_es_diagnostics.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <done>All required DIAG-02/03/04/05 signals are harvested into the serializable list, degenerate/NULL paths degrade to NA, and tests are green.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Anomaly ranking + top-N payload cap + aggregate remainder (DIAG-06)</name>
  <files>R/es_diagnostics.R, tests/testthat/test_es_diagnostics.R</files>
  <read_first>
    - 05-RESEARCH.md "Anomaly Ranking for Top-N Event Cap" (abs(final_car) metric; is_fitted==FALSE → score Inf; fallback abs(mean(AR)))
    - R/single_event_test_statistics.R:1-213 (CART$car column — last row = full-window CAR)
    - tests/testthat/helper-mock-data.R:130-134 (create_fitted_mock_task), :164-201 (degenerate-data factories for building an unfitted event)
    - R/simulation.R:146-157 (print convention for reporting truncation)
  </read_first>
  <behavior>
    - Test: with max_events smaller than n_events (e.g. build a 4-event task, call max_events = 2), meta$n_events_shown == 2, meta$n_events_summarized == 2, and per-event sections (estimation_window/event_window/contract_state vectors) have length 2.
    - Test: a degenerate event (is_fitted == FALSE) always appears among the shown events regardless of its CAR magnitude (anomaly score Inf).
    - Test: aggregate_summary is non-NULL when events are truncated and carries summary stats (e.g. n_summarized, mean/median of a key signal over the remainder); NULL when nothing is truncated.
    - Test: default call (max_events = 20) on a small task shows all events and aggregate_summary is NULL.
  </behavior>
  <action>
    Implement .rank_events_for_cap(task) returning a tibble of row_idx + anomaly_score where score = Inf when !model$is_fitted, else abs(tail(CART$car,1)) when the CART column exists and is non-NULL, else abs(mean(event-window abnormal_returns, na.rm=TRUE)); ties broken by original event_id order. In es_diagnostics(), rank once, take top min(max_events, n_total) row indices for the full per-event sections, and route the remainder through .aggregate_remainder(task, rest_idx) producing a compact summary list (count + mean/median of key signals) — NULL when rest_idx is empty. Wire meta$n_events_shown / n_events_summarized / event_ids_shown to the cap. Update print.es_diagnostics to note when events were summarized (e.g. "(N events summarized)") and, per 05-RESEARCH open-question 3, when any degenerate events were truncated. Extend test_es_diagnostics.R with the four behavior tests, constructing a multi-event task (create_fitted_mock_task with more firms, or a task combining a degenerate event) to exercise the cap.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_es_diagnostics.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. cap not applied (n_events_shown exceeds max_events), degenerate event dropped from shown set, or aggregate_summary NULL when truncation occurred.</fails_when>
  </verify>
  <acceptance_criteria>
    - .rank_events_for_cap assigns Inf to unfitted events so they always surface in top-N.
    - With max_events < n_events, per-event vectors are capped to max_events and aggregate_summary is populated.
    - With max_events >= n_events, all events shown and aggregate_summary is NULL.
    - Full new test file testthat::test_file("tests/testthat/test_es_diagnostics.R") exits 0 with 0 failures.
    - git diff DESCRIPTION is empty (CRAN-01: zero new hard deps).
  </acceptance_criteria>
  <reversibility rating="reversible">Additive internal helpers; no existing pipeline call site changed (CRAN-05).</reversibility>
  <done>Per-event payload is size-capped to max_events (default 20), most-anomalous-first with degenerate events always shown, remainder aggregated, and DIAG-06 tests green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| fitted EventStudyTask → es_diagnostics() | In-memory R6 object produced by the package's own pipeline; not untrusted external input, no network, no user-supplied code executed. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-05-01 | Information Disclosure | es_diagnostics output list | low | mitigate | The list is built ONLY from computed statistical signals; it never reads environment variables, API keys, or secrets. Verified guarantee: no Sys.getenv / Sys.setenv / file reads in R/es_diagnostics.R. |
| T-05-02 | Tampering | new package deps | high | mitigate | Zero new installs; acceptance criteria assert `git diff DESCRIPTION` empty. No package-legitimacy audit needed (no npm/pip/cargo/CRAN install). |
| T-05-03 | Denial of Service | degenerate/NA task input | low | mitigate | Every harvest step is tryCatch-guarded and payload is size-capped (max_events) so pathological inputs cannot exhaust memory or abort (DIAG-06, DIAG-07). |

Phase 5 opens no network surface and processes only in-memory fitted-task objects at ASVS L1; no applicable high-severity threat beyond the dependency-integrity guarantee (T-05-02).
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_es_diagnostics.R")'` → 0 failures.
- Wave merge / phase gate: `Rscript -e 'devtools::test()'` → existing 1378 tests still green (CRAN-05); `Rscript -e 'devtools::check(document=TRUE)'` → no new NOTEs/WARNINGs (CRAN-01).
- `git diff DESCRIPTION` empty across the plan.
</verification>

<success_criteria>
- `es_diagnostics(task)` returns a serializable `es_diagnostics` list with estimation-window, event-window, cross-sectional, and contract-state signals [DIAG-01..05].
- Runs without error on degenerate/NA tasks with no API key; payload capped at max_events (default 20) [DIAG-06, DIAG-07].
- Zero new hard dependencies; existing valid-input pipeline behavior byte-identical [CRAN-01, CRAN-05].
</success_criteria>

<output>
Create `.planning/phases/05-offline-diagnostics-grounding-knowledge-base/05-01-SUMMARY.md` when done.
</output>
