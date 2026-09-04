---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 01
subsystem: advisor-provider-seam
tags: [r6, provider, llm, cran-safe, tracer]
requires:
  - "Phase 5 es_advice shape (R/advise_offline.R:221-229) for field-name alignment"
provides:
  - "ProviderBase abstract R6 uniform complete(prompt, schema, ...) contract"
  - "CustomProvider (in-process user-fn hook, zero HTTP)"
  - "es_provider_response success/failure plumbing (.provider_success/.provider_failure)"
  - "call-time backend + key resolution (.resolve_provider_config/.resolve_api_key)"
  - "provider() exported factory (custom branch wired; openai/anthropic gated for 06-2/06-3)"
affects:
  - "06-2 OpenAICompatProvider and 06-3 AnthropicProvider extend this skeleton"
  - "Phase 7 es_advise() consumes es_provider_response (field names locked)"
tech-stack:
  added:
    - "httr2 (>= 1.0.0) — DESCRIPTION Suggests (used by 06-2/06-3 HTTP providers only)"
    - "jsonlite — DESCRIPTION Suggests"
  patterns:
    - "R6 strategy pattern mirroring ModelBase/TestStatisticBase"
    - "single-warning failure discipline mirroring .handle_degenerate()"
    - "arg -> env -> default 3-tier resolution via %||% chain"
key-files:
  created:
    - R/provider.R
    - tests/testthat/helper-provider.R
    - tests/testthat/test_provider_custom.R
    - tests/testthat/test_provider_resolution.R
    - man/ProviderBase.Rd
    - man/CustomProvider.Rd
    - man/provider.Rd
  modified:
    - DESCRIPTION
    - NAMESPACE
decisions:
  - "Default provider is 'custom' — resolves to a working, no-network provider with zero config"
  - "es_provider_response is a distinct S3 class (not es_advice); shares source/is_deterministic field names for trivial Phase 7 slotting"
  - "openai/anthropic factory branches gated behind exists() with a clear 'delivered in a later plan' stop() so 06-1 is independently green"
  - "jsonlite kept in Suggests alongside httr2 (explicit parse-side intent) though httr2 built-ins could cover it"
metrics:
  duration: "~6 min"
  completed: "2026-09-03"
actuals:
  tokens: 5349
  tasks: 3
  commits: 3
status: complete
---

# Phase 6 Plan 1: Provider Abstraction Tracer Summary

Delivered the end-to-end provider seam tracer: an abstract R6 `ProviderBase` defining the uniform `complete(prompt, schema, ...)` contract, the shared `es_provider_response` success/failure plumbing, a fully-working in-process `CustomProvider` (zero HTTP), call-time arg→env→default backend/key resolution, and an exported `provider()` factory — with `httr2`/`jsonlite` added to Suggests only. The whole seam is proven end-to-end (construct → `complete()` → `es_provider_response`; a failing call degrades to exactly one `warning()` + NA) before any HTTP code exists.

## What Was Built

- **`ProviderBase`** (abstract R6, `@export`): stores non-secret config (`model`, `base_url`) only; `complete()` stops "abstract" on the base. Mirrors the `ModelBase`/`TestStatisticBase` idiom.
- **`CustomProvider`** (`inherit = ProviderBase`, `@export`): wraps a user `function(prompt, schema, ...)`; runs it in `tryCatch`; a throwing fn routes through `.provider_failure()` → exactly one warning + `text = NA_character_`, never crashes.
- **`.provider_success()` / `.provider_failure()`** (`@noRd`): the single success/failure builders of the `es_provider_response` S3 object. `.provider_failure()` is the ONLY warning-emitting point. Fields `source`, `is_deterministic = FALSE`, `text`, `error` are locked to align with the Phase 5 `es_advice` shape.
- **`.resolve_provider_config()`** (`@noRd`): arg → `EVENTSTUDY_ADVISOR_PROVIDER/_MODEL/_BASE_URL` → default (`"custom"`); `""` treated as unset.
- **`.resolve_api_key()`** (`@noRd`): reads `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` at call time; returns `NA_character_` when unset — never stops. Keys never read at construction, never stored, never printed.
- **`provider()`** (`@export`): factory dispatching the `custom` branch (no HTTP); `openai`/`anthropic` gated behind `exists()` with a clear "delivered in a later plan" `stop()`; `match.arg` rejects unknown types. `@examples` are non-live (custom inline, HTTP `\dontrun{}`).

## New Exports

`ProviderBase`, `CustomProvider`, `provider` (all in NAMESPACE via roxygen2).

## Verification

- `test_provider_custom.R`: 15 pass, 0 fail (happy path, one-warning degrade, abstract base, prompt/schema seam).
- `test_provider_resolution.R`: 22 pass, 0 fail (arg→env→default precedence, call-time key resolution, factory dispatch/rejection).
- **Full suite (`devtools::test()`): 1694 pass, 0 fail, 31 skip, 1 warn.** Baseline was 1657 pass; +37 from new provider tests. The 31 skips and 1 warning are pre-existing (optional-dep skips; rank-deficient-design warning in `test_edge_cases.R`) — unrelated to this plan.
- **CRAN-clean deps-absent gate:** no live `httr2`/`jsonlite` symbol anywhere in `R/` (grep-confirmed — only comments/roxygen mention them); neither in NAMESPACE; both Suggests-only; `provider("custom", ...)` works with `httr2` not loaded. Valid-input behavior of Phase 1–5 code byte-identical.

## Tracer Feedback Gate

Task 1 was the `type="tracer"` slice. After committing it, the gate re-ran `<verify>` end-to-end (automated-only verify, auto mode off, `human_verify_mode=end-of-phase`): passed → `⚡ Tracer verified end-to-end — expanding`. No blocking-human gate on the task, so expansion (Tasks 2–3) proceeded without a checkpoint.

## Deviations from Plan

None — plan executed exactly as written. `provider()`'s `type` default is `NULL` (resolved to `"custom"` via `.resolve_provider_config`) rather than a literal `c(...)` default, which is the cleaner way to let the env selector participate; behavior matches the plan's intent (unset type falls back to the resolved default).

## Known Stubs

None. The `openai`/`anthropic` factory branches are intentionally deferred to 06-2/06-3 and error clearly ("delivered in a later plan") rather than returning a stub value — documented in the factory roxygen. This is a planned handoff, not a silent stub.

## Self-Check: PASSED

- FOUND: R/provider.R, tests/testthat/helper-provider.R, tests/testthat/test_provider_custom.R, tests/testthat/test_provider_resolution.R, man/ProviderBase.Rd, man/CustomProvider.Rd, man/provider.Rd
- FOUND commits: 8aaaf06, f97964a, 16abe52
- NAMESPACE contains export(ProviderBase), export(CustomProvider), export(provider)
