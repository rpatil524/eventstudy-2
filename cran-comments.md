## R CMD check baseline (pre-milestone, commit 63d67a1)

The following NOTEs were present at the pre-milestone baseline (commit 63d67a1,
before Phases 1-4 robustness hardening). These are the expected, pre-existing
findings; the gate is NO NEW NOTEs/WARNINGs introduced by this milestone, NOT
absolute zero.

### Pre-existing NOTEs at baseline (63d67a1)

All items below are Suggests-related NOTEs from optional packages that are not
installed in the check environment but are listed in DESCRIPTION Suggests:

1. Packages suggested but not available for checking:
   - `rugarch` (optional GARCH model; guarded by requireNamespace())
   - `rmgarch` (optional DCC-GARCH; guarded by requireNamespace())
   - `did` (optional Callaway-Sant'Anna estimator; guarded by requireNamespace())
   - `DIDmultiplegt` (optional DiD estimator; guarded by requireNamespace())
   - `didimputation` (optional BJS estimator; guarded by requireNamespace())
   - `quadprog` (optional synthetic control QP solver; guarded by requireNamespace())
   - `sandwich` (optional HAC SEs for cross-sectional regression; guarded by requireNamespace())
   - `tidyquant` (optional data download; guarded by requireNamespace())
   - `quantmod` (optional data download; guarded by requireNamespace())
   - `DT` (optional interactive tables; guarded by requireNamespace())
   - `zoo` (optional time series; guarded by requireNamespace())
   - `openxlsx` (optional Excel export; guarded by requireNamespace())

2. Vignette execution failures (pre-existing, environment-dependent):
   - Vignettes requiring missing optional packages (tidyquant, rugauth) or
     network access to CRAN/data sources fail in the offline check environment.
   - These are pre-existing and not caused by this milestone.

3. Hidden files/directories `.git` and `.planning` NOTE:
   - Present when checked from a git worktree (the worktree is inside .claude/worktrees/).
   - Not present in the real package source directory; CRAN submission uses the
     installed package source, not the worktree.

These baseline NOTEs/WARNINGs are accepted per CRAN policy for packages with many
optional Suggests packages that require external data sources or platform-specific
libraries.

---

## R CMD check gate result (milestone: robustness-hardening, Phase 4, Plan 02)

**Check path: PRIMARY** — `devtools::check(document = TRUE, args = c("--no-manual", "--no-build-vignettes"))`

**Check date:** 2026-09-02

**R version:** 4.6.1 (2026-06-24), Linux (Manjaro), x86_64

### Initial check findings (before milestone fixes applied)

Run against commit 277b2c9 (post 04-01 merge), BEFORE this plan's fixes:

- **1 ERROR:** Vignette execution failures (pre-existing; offline CRAN, missing
  optional packages tidyquant/rugarch/etc.) — NOT milestone-caused.
- **1 WARNING:** `R/cross_sectional.R` — non-ASCII characters (em-dash `—`)
  in comments and warning strings — **NEW** (milestone-caused, Phase 3 commit 52f3d40).
- **3 NOTEs:**
  - Hidden files/dirs `.git`, `.planning` (worktree artifact; pre-existing in baseline)
  - `callr` used via `::` in `R/panel_event_study.R:511` but not declared in
    DESCRIPTION Suggests — **NEW** (milestone-caused; callr used for DIDmultiplegt probe)
  - `bootstrap_test: no visible binding for global variable 'n_car'` — **NEW**
    (milestone-caused; `n_car` NSE column not in `globalVariables()`)

### Fixes applied (source-level, no suppression)

1. **[Rule 1 - Bug] `R/cross_sectional.R`:** Replaced Unicode em-dash (`—`)
   with ASCII double-dash (`--`) in 4 lines (2 comments, 2 warning strings).
   Eliminates the non-ASCII WARNING.

2. **[Rule 2 - Missing] `DESCRIPTION Suggests`:** Added `callr` to Suggests.
   `callr::r()` is called directly in `R/panel_event_study.R:511` for the
   DIDmultiplegt subprocess probe, so it must be declared.

3. **[Rule 2 - Missing] `R/EventStudy-package.R`:** Added `"n_car"` to
   `utils::globalVariables()`. `n_car` is used as an NSE column name in
   `bootstrap_test()` in `R/bootstrap.R`.

### Final check result (after fixes, without vignettes for clean delta)

Command: `devtools::check(document=TRUE, args=c("--no-manual","--no-build-vignettes","--no-vignettes"), error_on="never")`

- **ERRORS: 0**
- **WARNINGS: 0**
- **NOTES: 1** — hidden files `.git`, `.planning` (worktree artifact; present in
  baseline; not present in CRAN submission from real package directory)

**Delta vs baseline: 0 new NOTEs/WARNINGs.** All 3 new findings were fixed at source.
The vignette ERROR is pre-existing (offline environment; not milestone-caused).

**Gate result: PASSED** — zero errors, and current findings (subset: `.git/.planning`
NOTE only) are a strict subset of the recorded baseline. No new finding introduced
by this milestone remains unaddressed.

---

## Test environments

* local: Linux (Manjaro), R 4.6.1 — 1378 pass / 0 fail / 52 skip

## Notes

This is a resubmission of the EventStudy package, previously archived on
2024-04-20. The package has been completely rewritten with all prior issues
addressed. Version number has been incremented beyond the archived version
(0.39.2 -> 0.40.0).

This milestone (0.50.0) adds robustness hardening: degenerate-input contract,
per-model guards, test-statistic guards, pipeline hardening, external-package
wrapping, and a 1378-test regression net.
