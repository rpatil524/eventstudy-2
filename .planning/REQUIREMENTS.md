# Requirements: EventStudy — Robustness Hardening

**Defined:** 2026-09-02
**Core Value:** The package must never produce a silently incorrect statistical result. On degenerate input it either errors clearly or returns NA with one warning — never a plausible-looking wrong number.

## v1 Requirements

Requirements for this hardening milestone. Each maps to roadmap phases.

### Contract

The uniform degenerate-input policy and its configuration surface.

- [x] **CONTRACT-01**: A single documented degenerate-input contract defines expected behavior for insufficient observations (<2 estimation obs), zero variance, single-event groups, and NA propagation
- [x] **CONTRACT-02**: A configurable mode switch selects strict vs lenient handling (via ParameterSet field and/or package option), with a documented default
- [x] **CONTRACT-03**: In strict mode, degenerate input raises a descriptive error naming the offending event_id and/or firm_symbol
- [x] **CONTRACT-04**: In lenient mode, degenerate input sets `is_fitted = FALSE`, propagates NA through downstream statistics, and emits exactly one clear warning (no duplicate warnings per event)
- [x] **CONTRACT-05**: Behavior on valid (non-degenerate) input is unchanged from current release — the contract adds guards, not new results

### Models

Apply the contract uniformly across all return models.

- [x] **MODELS-01**: Every return model guards insufficient estimation observations before fitting and follows the contract (MarketModel, MarketAdjusted, ComparisonPeriodMean, FF3, FF5, Carhart4, BHAR, Volume, Volatility, RollingWindow, GARCH, DCC-GARCH, Custom)
- [x] **MODELS-02**: Every return model guards zero/near-zero variance (`sd < .Machine$double.eps`) before division, returning NA rather than Inf/NaN
- [x] **MODELS-03**: Degree-of-freedom counting uses only finite residuals across all models
- [x] **MODELS-04**: Forecast-error correction is applied consistently for event-window test statistics where the model supports it

### Stats

Apply the contract across single- and multi-event test statistics.

- [x] **STATS-01**: Single-event statistics (AR t, CAR t, BHAR) never leak Inf/NaN on degenerate input; they follow the contract
- [x] **STATS-02**: Multi-event statistics (AAR/CAAR, CSect t, Patell Z, BMP, Kolari-Pynnönen, Sign, Calendar-Time Portfolio) use correct, verified join keys (event_id) with no many-to-many inflation
- [x] **STATS-03**: CAR/cumsum chains are NA-safe (coalesce) so a firm dropping in/out mid-window cannot silently corrupt CARs
- [x] **STATS-04**: Single-event-group and firms-appearing-in-multiple-events cases produce correct denominators and counts

### Pipeline

Harden data preparation, windowing, and output.

- [x] **PIPELINE-01**: Window/preparation logic handles missing event dates and empty estimation/event windows per the contract
- [x] **PIPELINE-02**: Export and tidy methods guard NA before `if()` and use NA-safe verbs (replace_na/coalesce), consistently applying `na.rm`
- [x] **PIPELINE-03**: Cross-sectional regression degrades safely under collinear/singular design (no crash; NA or warning per contract)

### External

Defensively wrap external-package-bound areas so upstream failure degrades gracefully.

- [x] **EXTERNAL-01**: Panel DiD estimators wrap external calls (did, DIDmultiplegt, didimputation) in tryCatch with informative errors and version/availability guards
- [x] **EXTERNAL-02**: DIDmultiplegt load is isolated (subprocess check) so a segfault-prone platform warns rather than crashes the session
- [x] **EXTERNAL-03**: Missing optional packages (sandwich, rugarch, did) produce a clear warning about reduced capability instead of silently degrading inference
- [x] **EXTERNAL-04**: GARCH/DCC-GARCH and synthetic-control numerical paths guard overflow/underflow (softmax max-subtraction, domain checks on sqrt/log, denominator epsilon guards)

### Testing

Lock behavior with a durable regression net and a clean check.

- [x] **TEST-01**: Every bug fixed in this milestone has a regression test that fails before the fix and passes after
- [x] **TEST-02**: A contract test matrix exercises degenerate-input behavior across all covered components in both strict and lenient modes
- [x] **TEST-03**: The full existing test suite (400+ tests) remains green
- [x] **TEST-04**: `R CMD check` passes with no new NOTEs or WARNINGs introduced by this milestone

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Independence

- **INDEP-01**: Native reimplementation of Callaway-Sant'Anna estimator (drop `did` dependency)
- **INDEP-02**: Native reimplementation of de Chaisemartin-D'Haultfoeuille estimator (drop `DIDmultiplegt`)
- **INDEP-03**: Pure-R GARCH implementation (drop `rugarch` compilation dependency)

### Scale

- **SCALE-01**: Streaming/online computation for AAR/CAAR (Welford) on >1M observations
- **SCALE-02**: data.table backend for large cross-sectional datasets
- **SCALE-03**: Sparse fixed-effects / Frisch-Waugh-Lovell for large panels

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Native reimplementation of external estimators | This milestone wraps defensively; native rewrite is a separate independence milestone |
| Performance/scaling work (streaming, data.table, sparse FE) | Real concern but orthogonal to correctness; deferred to Scale milestone |
| New models, test statistics, task types, output formats | Hardening only — no feature growth |
| Result serialization format (JSON/HDF5) + reproducibility metadata | Deferred |
| Changing statistical intent of existing methods | Valid-input behavior must be preserved exactly |
| Data-download retry/cache improvements | Peripheral to core correctness; not this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CONTRACT-01 | Phase 1 | Complete |
| CONTRACT-02 | Phase 1 | Complete |
| CONTRACT-03 | Phase 1 | Complete |
| CONTRACT-04 | Phase 1 | Complete |
| CONTRACT-05 | Phase 1 | Complete |
| MODELS-01 | Phase 2 | Complete |
| MODELS-02 | Phase 2 | Complete |
| MODELS-03 | Phase 2 | Complete |
| MODELS-04 | Phase 2 | Complete |
| STATS-01 | Phase 2 | Complete |
| STATS-02 | Phase 2 | Complete |
| STATS-03 | Phase 2 | Complete |
| STATS-04 | Phase 2 | Complete |
| PIPELINE-01 | Phase 3 | Complete |
| PIPELINE-02 | Phase 3 | Complete |
| PIPELINE-03 | Phase 3 | Complete |
| EXTERNAL-01 | Phase 3 | Complete |
| EXTERNAL-02 | Phase 3 | Complete |
| EXTERNAL-03 | Phase 3 | Complete |
| EXTERNAL-04 | Phase 3 | Complete |
| TEST-01 | Phase 4 | Complete |
| TEST-02 | Phase 4 | Complete |
| TEST-03 | Phase 4 | Complete |
| TEST-04 | Phase 4 | Complete |

**Coverage:**

- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-02*
*Last updated: 2026-09-02 after roadmap creation*
