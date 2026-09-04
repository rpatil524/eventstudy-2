---
gsd_state_version: 1.0
milestone: v0.60.0
milestone_name: Grounded AI Advisor
current_phase: 8
current_phase_name: Agent Skill + Waitlist + Green Check Gate
status: planning
stopped_at: Completed 08-02-PLAN.md — CRAN green-check gate
last_updated: "2026-09-04T07:53:07.956Z"
last_activity: 2026-09-04
last_activity_desc: Phase 7 complete, transitioned to Phase 8
state_head: 709942faa3079edd3e47795867582563c8c9bbe9
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 10
  completed_plans: 10
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-02)

**Core value:** Trustworthy numbers, trustworthy interpretation — the pipeline is never silently wrong, and the AI advisor cites only package-computed diagnostics, never fabricating a result.
**Current focus:** Phase 05 — Offline Diagnostics + Grounding Knowledge Base

## Current Position

Phase: 8 — Agent Skill + Waitlist + Green Check Gate
Plan: Not started
Status: Ready to plan
Last activity: 2026-09-04 — Phase 7 complete, transitioned to Phase 8

Progress: [████████░░] 75%

## Performance Metrics

**Velocity:**

- Total plans completed (all milestones): 11
- Average duration: -
- Total execution time: 0 hours

**By Phase (v0.60.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 5 | 3 | - | - |
| 6 | 3 | - | - |
| 7 | 2 | - | - |
| 8 | TBD | - | - |

**Recent Trend:**

- Last 5 plans: n/a
- Trend: n/a

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 05 P01 | 10 | 3 tasks | 5 files |
| Phase 05-offline-diagnostics-grounding-knowledge-base P02 | 277 | 2 tasks | 5 files |
| Phase 05 P03 | 18 | 2 tasks | 6 files |
| Phase 06 P01 | 6m | 3 tasks | 8 files |
| Phase 06 P02 | 7m | 3 tasks | 6 files |
| Phase 06 P03 | 9 min | 3 tasks | 7 files |
| Phase 07 P2 | 4 | 2 tasks | 4 files |
| Phase 08 P02 | 838 | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Two-layer advisor: deterministic offline `es_diagnostics()` + grounded `es_advise()` (pyfda/fdars pattern); offline layer always available and testable
- Grounding invariant enforced by a runtime guard (`.validate_grounding()`), not by prompt alone
- LLM layer optional (Suggests: httr2/jsonlite, requireNamespace-guarded); offline layer pure base R, zero hard deps
- Provider abstraction = OpenAI-compatible + Anthropic + custom hook (R6 strategy pattern); resolution arg → env → default
- Freemium: bundled advisor free; retrieval-corpus "Advisor Pro" a future paid tier gated by a waitlist
- [Phase 05]: p-values extracted via stats::pt(abs(t), df, lower.tail=FALSE)*2 — dist_student_t objects never stored in es_diagnostics output
- [Phase 05]: unclass() required before jsonlite::toJSON() to strip S3 class from es_diagnostics and invoke default list handler
- [Phase 05]: cross_sectional signals computed across ALL events; per-event vectors capped to max_events top-N by anomaly score (Inf for unfitted, abs(final_car) otherwise)
- [Phase 05]: Added category field (stat_choice|robustness) to KB rules to enable recommend_stat()/flag_robustness() filtering without re-classifying at call time
- [Phase 05]: KB-PRETREND omitted: pretrend signal not available in es_diagnostics harvester; documented in SUMMARY
- [Phase 05]: recommend_stat/flag_robustness dispatch: accept either fitted task or es_diagnostics; provider=NULL silently ignored for Phase 7 forward-compat
- [Phase 05]: es_advice contract: source=offline_kb, is_deterministic=TRUE, rules_matched with plain scalar fields only (JSON-safe)
- [Phase 06]: provider layer = hand-rolled thin httr2 client (NOT ellmer) — user decision 2026-09-03. R6 ProviderBase → OpenAICompat/Anthropic/Custom; httr2/jsonlite stay Suggests; offline-tested via httr2::with_mocked_responses; keys redacted on all error paths; NA+one-warning on failure
- [Phase 6]: es_provider_response is a distinct S3 class sharing source/is_deterministic field names with es_advice for trivial Phase 7 slotting
- [Phase 6]: OpenAICompatProvider covers OpenAI + Ollama/LM Studio via base_url override; shared .perform_request/.finish_response reused by 06-3
- [Phase 6]: Empty-string API key treated as missing (one warning + NA at call time)
- [Phase 6]: AnthropicProvider tool-use input_schema structured output serialized to character via guarded jsonlite::toJSON, with a plain text-block fallback (never-crash)
- [Phase 7]: advice param positioned after interactive and before ... — zero positional-arg breakage
- [Phase 7]: skeleton.Rmd eval= double-guard (is.null + inherits) ensures NULL path is byte-identical
- [Phase 8]: Pre-existing non-ASCII WARNING (Phases 5-7) does not block v0.60.0 CRAN gate; documented as pre-existing baseline in cran-comments.md

### Pending Todos

- **Phase 6 post-review fixes — RESOLVED (2026-09-04, commit 23cc972).** Both CONFIRMED never-crash criticals fixed + regression-tested (CustomProvider NULL/character(0) degrade; OpenAICompat jsonlite-absent degrade). Full suite 1793 pass / 0 fail. Phase 6 marked complete.
- **CRAN R CMD check (CRAN-02)** was NOT re-run after the fix (fix is within the guarded pattern, tests green). The Phase 8 green-check gate re-runs the full `R CMD check`; confirm clean there.

### Blockers/Concerns

- **Phase 6 planning-time fork — RESOLVED (2026-09-03, user decision):** provider implementation = **hand-rolled thin `httr2` client** (not Posit `ellmer`). Rationale: smallest dependency surface (httr2/jsonlite stay Suggests, requireNamespace-guarded), full control over key redaction + never-crash error trapping, deterministic offline tests via `httr2::with_mocked_responses` with zero real API calls. Shape: R6 `ProviderBase` → `OpenAICompatProvider` (POST /chat/completions), `AnthropicProvider` (/v1/messages), `CustomProvider` (user `fn(prompt)->text`, the offline test seam); resolution arg→env→default; failure returns NA + one warning; keys redacted in all error paths.
- **Phase 5 KB correctness:** cross-check assumption→test mappings against Brown & Warner (1985), MacKinlay (1997), Patell (1976), BMP (1991), Kolari-Pynnönen (2010) primary literature.

## Deferred Items

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| Independence | INDEP-01..03: native reimplementation of did/DIDmultiplegt/rugarch | Deferred | v0.50.0 init | v2 |
| Scale | SCALE-01..03: streaming/data.table/sparse FE | Deferred | v0.50.0 init | v2 |
| Advisor Pro | PRO-01..02: RAG corpus advisor + managed hosting | Deferred | v0.60.0 roadmap | future (waitlist-gated) |
| Surfaces | SURF-01..02: MCP server + panel/intraday/synthetic diagnostics | Deferred | v0.60.0 roadmap | future |

## Session Continuity

Last session: 2026-09-04T07:53:07.897Z
Stopped at: Completed 08-02-PLAN.md — CRAN green-check gate
Resume file: None

## Operator Next Steps

- Plan the first phase with `/gsd-plan-phase 5`
