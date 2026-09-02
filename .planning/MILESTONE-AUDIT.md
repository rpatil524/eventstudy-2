---
milestone: EventStudy — Robustness Hardening
audited: 2026-09-02
status: passed
requirements_met: 24/24
core_value_delivered: true
tech_debt: []
---

# Milestone Audit: EventStudy — Robustness Hardening

**Status: PASSED**

## Summary

All 24 v1 requirements (CONTRACT-01..05, MODELS-01..04, STATS-01..04,
PIPELINE-01..03, EXTERNAL-01..04, TEST-01..04) were delivered and verified
across four phases. The core value — the package never produces a
silently incorrect statistical result on degenerate input — is observably
true: every return model and test statistic routes degenerate conditions
through `.handle_degenerate()`, with lenient mode returning NA + one named
warning and strict mode raising a descriptive error naming the offending
component/event/firm. The review rounds in Phases 2 and 3 caught and fixed
exactly this class of silent-wrong-number bug (MarketAdjusted false-degenerate
scope, export CAR coalesce→0, synthetic-control empty-pool wrong ATT,
many-to-many join inflation GH #7). The full suite is green at
1378 pass / 0 fail / 52 skip (skips: absent optional packages only). R CMD
check passes with 0 errors, 0 warnings, 1 NOTE (pre-existing worktree artifact
`.git`/`.planning`, present in the recorded baseline — 0 new findings).

## Tech Debt / Acceptable Limitations

- **DIDmultiplegt callr probe is opt-in only.** The subprocess isolation for
  the macOS-segfault-prone DIDmultiplegt package is guarded by an opt-in
  option; users on platforms where DIDmultiplegt is stable run without the
  overhead. This is intentional design, not a gap.
- **GARCH/DCC tests skip when rugarch/rmgarch absent.** 14 tests are skipped
  in environments without rugarch/rmgarch. The guards are correct and tested
  via mock paths; the skips are acceptable per the CRAN Suggests boundary.
- Both items were visible to the verifier and assessed as acceptable at
  Phase 3/4 verification. No item was dropped or silently omitted.

## v2 Deferred Items (correct)

INDEP-01..03 (native DiD/GARCH reimplementations) and SCALE-01..03
(streaming/data.table/sparse-FE) were explicitly deferred to future milestones.
These are correctly out of scope; no in-scope requirement was mis-deferred.

---
*Audited: 2026-09-02*
*Auditor: Claude (gsd-milestone-audit)*
