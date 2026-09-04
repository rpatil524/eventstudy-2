# Roadmap: EventStudy — Grounded AI Advisor

## Milestones

- ✅ **v0.50.0 Robustness Hardening** — Phases 1-4 (shipped 2026-09-02)
- ✅ **v0.60.0 Grounded AI Advisor** — Phases 5-8 (shipped 2026-09-04)

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Numbering is continuous across milestones. Full per-phase detail for shipped
milestones lives in `.planning/milestones/v{X.Y}-ROADMAP.md`.

<details>
<summary>✅ v0.50.0 Robustness Hardening (Phases 1-4) — SHIPPED 2026-09-02</summary>

- [x] **Phase 1: Contract Foundation** — degenerate-input contract + strict/lenient mode (completed 2026-09-02)
- [x] **Phase 2: Model and Stats Sweep** — contract applied across all 13 models + all test statistics (completed 2026-09-02)
- [x] **Phase 3: Pipeline and External Hardening** — hardened prepare/export + wrapped external-package areas (completed 2026-09-02)
- [x] **Phase 4: Regression Net and Check Gate** — per-fix regression tests + contract matrix + green R CMD check (completed 2026-09-02)

Archive: `.planning/milestones/v0.50.0-ROADMAP.md`

</details>

<details>
<summary>✅ v0.60.0 Grounded AI Advisor (Phases 5-8) — SHIPPED 2026-09-04</summary>

**Milestone Goal:** Add an LLM-agnostic AI advisor that guides users through an entire event study — grounded so it interprets only package-computed numbers and never fabricates results.

- [x] **Phase 5: Offline Diagnostics + Grounding Knowledge Base** — deterministic zero-dependency `es_diagnostics()`, pure-R assumption→test KB, non-LLM rule-based advice fallback (completed 2026-09-03)
- [x] **Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness** — LLM-agnostic `AdvisorProvider` R6 hierarchy (Anthropic, OpenAI-compatible, custom), 3-tier precedence, graceful degradation, offline-tested (completed 2026-09-04)
- [x] **Phase 7: Grounded Advise Layer + Grounding Guard** — `es_advise()` `Advice` object with runtime grounding guard, all six advice modes, `generate_report()` integration (completed 2026-09-04)
- [x] **Phase 8: Agent Skill + Waitlist + Green Check Gate** — Claude Code Agent Skill, "Advisor Pro" waitlist surface, green `R CMD check --as-cran` with suite green (completed 2026-09-04)

Archive: `.planning/milestones/v0.60.0-ROADMAP.md` · Audit: `.planning/milestones/v0.60.0-MILESTONE-AUDIT.md`

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Contract Foundation | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 2. Model and Stats Sweep | v0.50.0 | 4/4 | Complete | 2026-09-02 |
| 3. Pipeline and External Hardening | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 4. Regression Net and Check Gate | v0.50.0 | 2/2 | Complete | 2026-09-02 |
| 5. Offline Diagnostics + Grounding KB | v0.60.0 | 3/3 | Complete | 2026-09-03 |
| 6. Provider Abstraction + HTTP Harness | v0.60.0 | 3/3 | Complete | 2026-09-04 |
| 7. Grounded Advise Layer + Guard | v0.60.0 | 2/2 | Complete | 2026-09-04 |
| 8. Agent Skill + Waitlist + Check Gate | v0.60.0 | 2/2 | Complete | 2026-09-04 |
