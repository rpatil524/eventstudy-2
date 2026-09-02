# Milestones

## v0.50.0 Robustness Hardening (Shipped: 2026-09-02)

**Phases completed:** 4 phases, 10 plans, 18 tasks

**Key accomplishments:**

- Degenerate-input contract for MarketModel: R/contract.R with .resolve_degenerate_mode/.handle_degenerate, ParameterSet field, execute.R row-indexed key threading, byte-identical valid-input output confirmed
- testthat 3e regression net for the degenerate-input contract: 12 contract tests + 5 ParameterSet validation tests, degenerate data factories, man/degenerate-input-contract.Rd, and 973-test green suite
- Six models (MarketAdjusted, ComparisonPeriodMean, Custom, BHAR, Volume, Volatility) migrated onto the Phase 1 degenerate-input contract via .handle_degenerate(); .finite_residual_df() helper added; VolatilityModel guard-placement bug fixed; BHARModel df and unconditional-AR bugs fixed
- RollingWindowModel fully migrated onto .handle_degenerate() with n_valid upgrade; GARCHModel and DCCGARCHModel receive PRE-CALL contract guards before external package calls with FEC n_valid fix; Phase 3 failure wrapping untouched
- Surgical sigma==0 and n_events==1 denominator guards added to 5 test statistics; STATS-02/03/04 correctness locked with regression tests; full 409-test suite green.
- Mode-honoring missing-date degradation in prepare_event_study(), coalesce-guarded CAR cumsum in export, and tryCatch singular/collinear guard + message->warning in cross_sectional_regression()
- Wrapped all four external-package call sites (did, DIDmultiplegt, didimputation, sandwich) and both GARCH statistics paths (rugarch, rmgarch) with tryCatch+warning+NULL/NA degradation; added synthetic-control solve.QP and empty-pool guards.
- 25-component table-driven contract matrix (test_contract_matrix.R) and complete fix→test catalog in NEWS.md lock all Phases 1-3 degenerate-input hardening against regression
- Check gate passed — 0 errors/warnings vs baseline; fixed 3 new findings (non-ASCII WARNING, callr Suggests NOTE, n_car globalVariables NOTE) at source; full 1378-test suite green.

---
