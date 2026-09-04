# Phase 7: Grounded Advise Layer + Grounding Guard - Context

**Gathered:** 2026-09-04
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous); four grey-area forks resolved by user decision

<domain>
## Phase Boundary

This phase delivers `es_advise()` — the **grounded interpretation layer** that turns
deterministic `es_diagnostics()` output into human-facing advice via an optional LLM
provider, while guaranteeing **every claim is provably tied to a diagnostic the package
actually computed**. It returns an `Advice` S3 object (`interpretation`,
`recommendations[]`, `caveats`) with a `print` method; each recommendation carries
`action`/`kind`/`rationale`/`expected_effect`/`evidence[]`, and each evidence entry is
structured `{diagnostic_key, value, threshold, direction}` referencing the diagnostics.

The invariant is enforced by a **runtime R grounding guard** (`.validate_grounding()`),
independent of the prompt: it rejects any recommendation whose evidence cites a key
absent from the diagnostics, or a value mismatching beyond tolerance. `es_advise()`
covers all six task types (`interpret`, `recommend_stat`, `recommend_model`,
`flag_robustness`, `design_discussion`, `report_writing`), errors clearly when no
provider/key is available (never silent/fabricated), and its `report_writing` output is
consumable by `generate_report()` via a new optional `advice = NULL` param rendered
through a guarded template section (existing render path unchanged).

This phase consumes the Phase 6 provider seam (`es_provider_response`, `provider()`,
the `schema` arg) and the Phase 5 offline layer (`es_diagnostics()`, KB, `es_advice`,
`recommend_stat()`/`flag_robustness()`). It adds NO new hard dependency; the LLM path
stays optional (Suggests, `requireNamespace()`-guarded). Phase 8 wraps this in the
Agent Skill + waitlist + green-check gate.

</domain>

<decisions>
## Implementation Decisions

### Grounding Guard Semantics
- **Guard failure mode = drop-and-keep.** When a recommendation's `evidence[]` cites a
  missing `diagnostic_key` or a value mismatching beyond tolerance, drop ONLY that
  recommendation, return the remaining grounded recommendations, and append a caveat
  noting N recommendations were dropped as ungrounded. Emit exactly ONE `warning()`.
  Never surface a fabricated claim; never `stop()` (respects the NA+one-warning contract).
- **Guard scope = structured evidence only.** `.validate_grounding()` validates each
  recommendation's `evidence[]` entries against the `es_diagnostics` object (ADV-04 as
  written). Interpretation/caveat prose is constrained to cite only provided diagnostics
  via the prompt — NO prose numeric-token scanning (deterministic, no false positives on
  years/window sizes).
- **Evidence resolution:** `diagnostic_key` addresses the six `es_diagnostics` sections
  (`meta`, `estimation_window`, `event_window`, `cross_sectional`, `contract_state`,
  `aggregate_summary`) and their documented keys. Vector-valued keys (per-event) are
  addressed with an index; the guard checks the cited value against the diagnostics value
  within a numeric tolerance (both absolute and relative floor), and NA-vs-present is a
  mismatch. Exact resolution key-path convention is Claude's discretion, guided by the
  Phase 5 diagnostics harvester shape.

### KB × LLM Interplay
- **recommend_stat / flag_robustness = KB grounds, LLM interprets.** When a provider is
  supplied for these two task types, the Phase 5 KB decision table produces the grounded
  recommendations + evidence (guaranteed non-fabricated, peer-reviewed mappings); the LLM
  only adds prose interpretation/rationale on top. The guard still runs. When no provider
  is supplied, these degrade to the pure Phase 5 offline `es_advice` path unchanged.
- **interpret / design_discussion / report_writing = LLM-required.** These have no offline
  equivalent; when no provider/key is available `es_advise()` errors clearly (ADV-06) —
  never a silent or fabricated result.

### Structured Output Contract
- **Provider schema → JSON.** `es_advise()` uses the Phase 6 provider `schema` arg to
  request JSON matching the Advice contract, then parses + guards it. Malformed, partial,
  or empty JSON (and any provider failure `es_provider_response`) degrades to one warning
  + an empty/NA Advice — never a crash. JSON parsing is guarded (`jsonlite` is Suggests).
- The `Advice` S3 object shares `source`/`is_deterministic` field names with Phase 5
  `es_advice` and Phase 6 `es_provider_response` so offline and online results are
  shape-compatible; `source` distinguishes offline_kb vs the provider, `is_deterministic`
  is TRUE only on the pure-KB path.

### report_writing / generate_report Integration
- **`generate_report(advice = NULL)`** — new optional trailing param; when supplied and a
  grounded `Advice`, render it through a NEW guarded template section. When `NULL` (the
  default) the existing render path is byte-identical/unchanged. A supplied-but-invalid
  advice degrades gracefully (skip section + one warning), never breaks the report.

### Claude's Discretion
- Exact `diagnostic_key` path convention and tolerance constants; the Advice/evidence
  R6-vs-S3-list internal representation (S3 list per ADV-01); prompt templates per task
  type; the JSON schema passed to the provider; print-method formatting; whether the guard
  is one function or a small helper set. Guided by codebase conventions (snake_case public,
  leading-dot `@noRd` internal, testthat 3e) and the Phase 5/6 contracts.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`R/es_diagnostics.R`** — `es_diagnostics(task, max_events)` returns class
  `es_diagnostics`, six sections with documented plain-scalar/vector keys (JSON-safe via
  `unclass()`). This is the sole ground-truth source the guard validates against.
- **`R/advise_offline.R`** — `es_advice` S3 (`source`, `is_deterministic`, `rules_matched`,
  `diagnostics_ref`) + `print.es_advice`; `recommend_stat()`/`flag_robustness()` S3
  generics already dispatch on EventStudyTask | es_diagnostics and accept `provider = NULL`
  (Phase 5 forward-compat seam for exactly this phase). `.build_offline_advice` evaluates
  KB rules → grounded rules_matched. The Advice contract is explicitly "same shape".
- **`R/knowledge_base.R`** — `es_kb()` decision table with `category`
  (stat_choice|robustness) fields for filtering; the grounded recommendation source for
  recommend_stat/flag_robustness.
- **`R/provider.R`** (Phase 6) — `provider()` factory, `ProviderBase$complete(prompt,
  schema, ...)` returning `es_provider_response` (`source`, `is_deterministic=FALSE`,
  `text`, `error`); arg→env→default resolution; NA+one-warning on every failure; keys
  redacted; offline-testable via `httr2::with_mocked_responses` + `CustomProvider`.
- **`R/report.R`** — `generate_report(task, output_file, format, title, author, sections,
  cross_sectional, confidence_level, interactive, ...)`; `sections` vector gates rendering.
- **`R/contract.R`** — `.handle_degenerate()` NA+one-warning template mirrored by the guard.
- `%||%` (rlang) for resolution chains; `requireNamespace(..., quietly=TRUE)` discipline.

### Established Patterns
- Public snake_case `@export`; internal leading-dot `@noRd`; S3 generics + `.default`/
  typed methods with `stop(..., call.=FALSE)`; testthat 3e `helper-*.R`; optional deps only
  inside `requireNamespace()` guards so `R CMD check` stays clean when uninstalled.
- Failure contract: exactly ONE `warning(msg, call.=FALSE)` + NA/empty, never uncaught error.

### Integration Points
- New export: `es_advise()` + `Advice` print method; NAMESPACE regenerated via roxygen2.
- `CustomProvider` is the offline test seam — return canned JSON to exercise es_advise +
  guard end-to-end with zero network (deterministic guard regression tests are mandatory).
- `generate_report()` gains one optional param + one guarded section.

</code_context>

<specifics>
## Specific Ideas

- Guard regression tests must be deterministic and provider-independent: feed a canned
  JSON Advice (via `CustomProvider`) containing (a) a valid grounded recommendation, (b)
  one citing a missing key, (c) one with a value beyond tolerance — assert only (a)
  survives, a caveat records the 2 drops, and exactly one warning fires.
- No-provider path for LLM-only task types: assert a clear error (ADV-06), not NA/silence.
- report_writing: assert `generate_report(advice=NULL)` render path is unchanged and a
  supplied grounded advice renders the new section; invalid advice degrades with a warning.

</specifics>

<deferred>
## Deferred Ideas

- Agent Skill orchestrating load→diagnose→advise→re-run→compare, "Advisor Pro" waitlist,
  green `R CMD check` gate → Phase 8.
- Retrieval-corpus (RAG) grounding, managed hosting → future waitlist-gated milestone.
- Prose numeric-token scanning as a second guard layer — explicitly rejected this phase
  (deterministic structured-evidence guard only); revisit only if a fabrication path is
  found that the structured guard misses.

</deferred>
