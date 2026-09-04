---
status: resolved
trigger: DCCGARCHModel double-warning on stats failure
created: 2026-09-04
updated: 2026-09-04
resolved: 2026-09-04
---

# Debug: DCCGARCHModel double-warning on stats failure

## Symptoms

- **Expected behavior:** On a `DCCGARCHModel` `calculate_statistics` failure (post-convergence), the model must emit **exactly ONE warning total** across `fit()` + `abnormal_returns()` combined, per the milestone's one-warning contract. `abnormal_returns()` must return all-NA and must NOT emit a second "not fitted" warning.
- **Actual behavior:** `fit()` emits its one warning and sets `is_fitted=FALSE`, but a subsequent `abnormal_returns()` call fires a SECOND warning — two warnings total — violating the one-warning contract.
- **Error messages (CI):**
  - `test_models_time_varying.R:665` — "DCCGARCHModel: calculate_statistics failure → exactly ONE warning (fit+abnormal_returns combined)": *Expected abnormal_returns() must NOT emit a second warning (one-warning contract) to equal 0L.*
  - `test_models_time_varying.R:586` — companion assertion ("...resets is_fitted=FALSE + named warning + NA ARs").
  - Surfaces as `R CMD check found ERRORs` → CI job `check-r-package` fails on ubuntu/macos/windows + Test coverage.
- **Timeline:** Present in CI at least since 2026-09-02 (v0.50.0 archive commit run 33667089051, and the run before it). NOT caused by the 2026-09-04 README push (run 33854684610) — that push merely re-exposed the same pre-existing red. The milestone shipped believing the suite was green because these tests are **skipped locally** (`rugarch`/`rmgarch` NOT installed → `skip_if_not_installed()`), but CI installs the deps and runs them.
- **Reproduction (CI / requires rmgarch + rugarch):** In `test_models_time_varying.R` the DCCGARCH test does:
  ```r
  local_mocked_bindings(rcov = function(...) stop("simulated rcov failure for WR-01"), .package = "rmgarch")
  dm <- DCCGARCHModel$new()
  # fit(dm, d) → 1 warning, is_fitted=FALSE   (correct)
  # dm$abnormal_returns(d) → SECOND warning     (BUG)
  ```

## Current Focus

hypothesis: CONFIRMED (root cause differs from original guess). The `calculate_statistics` failure handler at line 351 ALREADY sets `.degenerate_handled <- TRUE` — that path is fine. The actual bug is the *convergence-check* path. The test mocks `rmgarch::rcov` to `stop()`. In `fit()`, `rcov` is FIRST called at line 341 inside `converged <- tryCatch({ rcov(res$result); ... }, error = function(e) FALSE)`. With `rcov` mocked to stop, `converged` becomes FALSE, so control goes to the `else` branch at lines 357-360 which sets `is_fitted <- FALSE` and warns "DCC-GARCH model produced non-finite covariance" but does NOT set `.degenerate_handled <- TRUE`. The `calculate_statistics`-failure tryCatch at line 348 is never reached because `converged` is already FALSE. Result: `abnormal_returns()` sees `is_fitted=FALSE` AND `.degenerate_handled=FALSE` → falls through to the plain `else` at line 386 → SECOND warning.
test: reason from code path + build mocked reproduction (rcov→stop) driving fit()+abnormal_returns() without real rmgarch/rugarch
expecting: two warnings currently (repro); after fix, exactly one
next_action: add `private$.degenerate_handled <- TRUE` to the non-finite-covariance else branch (line 357-360) so abnormal_returns() honours the one-warning contract on the rcov-convergence-failure path

reasoning_checkpoint:
  hypothesis: "The rcov mock triggers the converged=FALSE branch (line 357), not the calculate_statistics tryCatch (line 348); that branch fails to set .degenerate_handled, so abnormal_returns() emits a second warning."
  confirming_evidence:
    - "Line 341: rcov(res$result) is called inside the converged tryCatch; mocking rcov→stop forces converged=FALSE."
    - "Line 357-360 else branch sets is_fitted<-FALSE + warning but has NO .degenerate_handled<-TRUE assignment."
    - "Line 348 calculate_statistics tryCatch (which DOES set the flag at 351) is only reached when converged=TRUE, unreachable under the mock."
    - "abnormal_returns() line 381 else-if requires .degenerate_handled=TRUE to stay silent; otherwise line 386 else fires the second warning."
  falsification_test: "If the mocked repro emits only ONE warning before the fix, the hypothesis is wrong. If it emits TWO, confirmed."
  fix_rationale: "Setting .degenerate_handled<-TRUE on the converged=FALSE branch routes abnormal_returns() to the silent NA branch — same contract the calculate_statistics path already satisfies. Addresses root cause (missing flag on this specific failure branch), not a symptom."
  blind_spots: "The 'DCC-GARCH fitting failed' branch (line 361-366, dccfit error) also lacks the flag — but the test does not mock dccfit, so it is out of scope for THIS failing test. Worth noting for completeness."
  candidate_causes:
    - "code: missing .degenerate_handled<-TRUE assignment on the non-finite-covariance branch"
    - "code(test-design): the WR-01 test mocks rcov, which routes to the convergence branch rather than the intended calculate_statistics branch — so the original fix landed on a path the test never exercises"
  and_gate: "no — a single missing assignment on the exercised branch fully explains two warnings; the test-design observation is a contributing insight but the code fix on the converged-FALSE branch alone makes the test pass."

## Investigation Constraints

- **rugarch / rmgarch are NOT installed in this local environment** — the exact failing test cannot be run locally as-is. To verify a fix, either (a) install `rugarch` + `rmgarch` locally, or (b) reason from code parity with the already-fixed `GARCHModel` path and, if feasible, construct a mock-based repro that exercises the same handler without the real packages. Do NOT declare the fix verified without either running the DCCGARCH test with the deps present or a clearly-equivalent mocked reproduction. Flag the verification method used.
- Milestone core value: never emit more than one warning on degenerate input. The fix must preserve the exactly-one-warning contract and keep valid-input behavior byte-identical.
- CRAN: no new NOTEs/WARNINGs; `rugarch`/`rmgarch` stay Suggests, `requireNamespace()`-guarded.

## Evidence

- timestamp: 2026-09-04
  checked: R/models_time_varying.R DCCGARCHModel fit() lines 336-366 + abnormal_returns() lines 372-391 + calculate_statistics() lines 394-458
  found: Line 351 ALREADY sets .degenerate_handled<-TRUE inside the calculate_statistics-failure tryCatch handler. But rcov is called at line 341 inside the converged<-tryCatch guard, and again at line 399 inside calculate_statistics. The converged else-branch (357-360) and the dccfit-error branch (361-366) do NOT set the flag.
  implication: Original hypothesis (missing flag on stats-failure path) is WRONG — that flag is present. Real gap is on the convergence-failure branch.

- timestamp: 2026-09-04
  checked: tests/testthat/test_models_time_varying.R lines 635-667 (the failing DCCGARCH one-warning test)
  found: Test does local_mocked_bindings(rcov = function(...) stop(...), .package = "rmgarch"). Because rcov is invoked FIRST at line 341 (convergence check), the mock forces converged=FALSE and routes to the line 357 else-branch — NOT the line 348 calculate_statistics tryCatch.
  implication: The WR-01 fix at line 351 sits on a branch this test never reaches. The test exercises line 357-360, which lacks .degenerate_handled<-TRUE → abnormal_returns() line 386 else fires the second warning. Root cause confirmed.

- timestamp: 2026-09-04
  checked: tests/testthat/test_models_time_varying.R lines 564-592 (EXTERNAL-04 companion test)
  found: EXTERNAL-04 ALSO mocks rcov->stop and asserts (line 586) a warning matching "DCC-GARCH.*statistics.*failed|statistics.*computation.*failed". But the rcov mock routes to the convergence else-branch (line 357) whose message is "DCC-GARCH model produced non-finite covariance" — which does NOT match that regex.
  implication: TWO distinct CI failures share ONE root cause: the convergence check at line 341 calls rcov BEFORE the calculate_statistics path, so the rcov mock never reaches the intended stats-failure handler. WR-01 (line 665) fails on double-warning; EXTERNAL-04 (line 586) fails on wrong warning message. A fix that only adds .degenerate_handled to the convergence branch fixes WR-01 but NOT EXTERNAL-04's message assertion. The correct fix must make the rcov mock reach the calculate_statistics-failure handler (the "statistics computation failed" message + already-present flag).

## Eliminated

- hypothesis: Adding .degenerate_handled to the convergence else-branch is the complete fix
  evidence: It silences WR-01's double-warning but EXTERNAL-04 (line 586) asserts the warning MESSAGE contains "statistics...failed / computation failed", which the convergence branch does not produce. Both tests expect the rcov failure to be handled as a *statistics* failure, not a *non-finite covariance* failure.
  timestamp: 2026-09-04

- hypothesis: The calculate_statistics-failure tryCatch handler is missing .degenerate_handled<-TRUE
  evidence: Line 351 already contains that exact assignment inside the tryCatch error handler; the flag IS set on that path. The failing test simply never reaches that path.
  timestamp: 2026-09-04

## Resolution

root_cause: In DCCGARCHModel$fit(), the convergence check calls rmgarch::rcov (R/models_time_varying.R:341) BEFORE the calculate_statistics path. It collapsed BOTH "rcov errored" and "rcov returned non-finite" into a single converged=FALSE outcome that emitted the "non-finite covariance" warning WITHOUT setting private$.degenerate_handled. The two failing CI tests both mock rcov->stop() intending to exercise the *statistics-failure* handler, but the mock was caught by the earlier convergence probe instead. Consequences: (1) WR-01 test (line 665) — the missing .degenerate_handled let abnormal_returns() fire a second warning (double-warning contract violation); (2) EXTERNAL-04 test (line 586) — the emitted message "non-finite covariance" did not match the required "statistics...failed / computation failed" regex. Single shared root cause: rcov-error and rcov-nonfinite were not distinguished, and the error case was mis-routed.
fix: Replaced the boolean `converged <- tryCatch(all(is.finite(rcov(...))), error=FALSE)` with a probe that captures the error object: `conv_probe <- tryCatch(list(ok=all(is.finite(rcov(...))), err=NULL), error=function(e) list(ok=NA, err=e))`. Now (a) rcov ERROR routes to the statistics-computation-failure handler (correct "statistics...failed" message + .degenerate_handled<-TRUE); (b) rcov returns non-finite -> unchanged "non-finite covariance" warning (now also sets .degenerate_handled<-TRUE for the one-warning contract); (c) rcov ok+finite -> normal fit, byte-identical to before. Also added .degenerate_handled<-TRUE to the dccfit-error branch (line ~364) for contract parity (blind-spot from reasoning_checkpoint; not exercised by the failing tests but same latent double-warning gap).
verification: rugarch/rmgarch NOT installable locally, so the exact CI tests skip. VERIFICATION METHOD (b) — equivalent mocked reproduction (scratchpad/repro_v2.R) reconstructing the exact fit() convergence-branch + abnormal_returns() logic driven by rcov->stop / rcov->nonfinite / rcov->ok stubs: mode=error yields message matching /statistics.*failed|computation.*failed/ AND total=1 warning AND is_fitted=FALSE AND all-NA ARs (satisfies EXTERNAL-04 line 586 + WR-01 line 665); mode=nonfinite yields one "non-finite covariance" warning; mode=ok yields zero warnings + is_fitted=TRUE (valid-input byte-identical). Local test_file runs: test_models_time_varying.R -> 0 failed / 56 passed / 16 skipped; test_models.R -> 0 failed / 276 passed. NOTE: the two target CI tests themselves still skip locally and were NOT run against the real packages — verification rests on the equivalent mocked reproduction, not on executing the skipped tests.
files_changed: [R/models_time_varying.R]

human_verify: RESOLVED 2026-09-04 — user chose Option 1 ("Commit on mock proof; let CI confirm"). Authorized committing the applied-but-uncommitted DCCGARCHModel fix on the strength of verification method (b) — the mocked reproduction — plus passing local self-tests (test_models_time_varying.R 0 failed/56 passed/16 skipped; test_models.R 0 failed/276 passed). The two target CI tests (test_models_time_varying.R:665 WR-01, :586 EXTERNAL-04) still skip locally because rugarch/rmgarch are not installed; CI installs the deps and will run them for definitive confirmation. If CI goes red, revise. Fix committed + session archived; pushing (deferred to the user) is what triggers the definitive CI run.
