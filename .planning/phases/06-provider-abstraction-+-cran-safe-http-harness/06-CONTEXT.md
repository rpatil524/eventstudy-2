# Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness - Context

**Gathered:** 2026-09-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous); one grey-area fork resolved by user decision

<domain>
## Phase Boundary

This phase delivers the **uniform LLM-provider seam** that the grounded advise layer (Phase 7) will call. A user can select any backend — native Anthropic, any OpenAI-compatible endpoint (including local Ollama / LM Studio), or a custom in-process function — through one interface that **never leaks API keys**, **never crashes the R session on failure** (network error, non-200, malformed body, missing key), and is **fully testable offline with no real API call**. It is purely additive and optional: the entire LLM stack lives in `Suggests`, guarded by `requireNamespace()`; the Phase 5 offline layer (`es_diagnostics()`, KB advice) keeps working with zero of these dependencies installed.

Delivers: an R6 `ProviderBase` strategy hierarchy (`OpenAICompatProvider`, `AnthropicProvider`, `CustomProvider`), a thin CRAN-safe HTTP call helper over `httr2`, backend resolution (explicit arg → environment variable → default), key redaction on every error path, and a deterministic offline test suite using `httr2::with_mocked_responses` plus the `CustomProvider` seam. **No provider is called by any Phase 5 code; this phase only builds and tests the seam. Phase 7 wires it to `es_advise()`.**

</domain>

<decisions>
## Implementation Decisions

### Provider Implementation — RESOLVED FORK (user decision 2026-09-03)
- **Hand-rolled thin `httr2` client — NOT Posit `ellmer`.** Chosen for the smallest dependency surface, full control over key redaction and never-crash error trapping, and deterministic offline mocking. `ellmer`'s higher-level chat abstractions would enlarge the Suggests footprint and force coarser mocking with less control over the exact guarantees this phase's goal demands.
- LLM HTTP deps (`httr2`, `jsonlite`) stay in **`Suggests`**, every entry point guarded by `requireNamespace(..., quietly = TRUE)` (v0.50.0 discipline). Absent deps → a clear, actionable error, never a crash.

### Provider Class Shape (R6 strategy pattern)
- `ProviderBase` (abstract R6): defines the `complete(prompt, ...)` (or equivalent) contract and shared request/response/error plumbing.
- `OpenAICompatProvider`: `base_url` + key → `POST {base_url}/chat/completions`; covers OpenAI, Ollama, LM Studio, and any OpenAI-compatible gateway via configurable `base_url` + `model`.
- `AnthropicProvider`: native `POST /v1/messages` with the Anthropic auth header + `anthropic-version`.
- `CustomProvider`: wraps a user `function(prompt) -> character` — the in-process, **offline test seam** and the escape hatch for unsupported backends.

### Backend Resolution
- Precedence: **explicit argument → environment variable → default**. Env var names follow provider convention (e.g. `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_BASE_URL`). Missing key surfaces one clear error at call time, not at construction, and never prints the key.

### Failure & Safety Contract
- **Never crash the session:** all network/parse/status failures are trapped (`httr2::req_error`, `tryCatch`) and degrade to a returned failure signal — return `NA`/`NULL` advice with **one** actionable `warning()`, consistent with the package's degenerate-input contract.
- **Never leak keys:** keys are redacted from every error message, condition, and any logged/echoed request. No key ever appears in a `warning`, `stop`, `print`, or test snapshot.
- **Offline-first tests:** the full provider suite runs with **no real API call** — `httr2::with_mocked_responses` for the HTTP providers and the `CustomProvider` fn seam for end-to-end. Tests must pass on CRAN machines with no network and no keys set (skip real-endpoint tests via `testthat::skip_if_offline()` / `skip_on_cran()` only where a live call would otherwise be needed — but coverage of the seam itself must not depend on it).

### Claude's Discretion
- Exact method names on `ProviderBase`, the internal request-builder helper factoring, the failure return shape (must align with the Phase 7 `Advice`/`es_advice` contract), retry/timeout defaults, and env-var naming details are at Claude's discretion, guided by codebase conventions and Phase 7 consumption needs.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 5 `es_advice` contract** (`R/advise_offline.R`): `source`, `is_deterministic`, `rules_matched` (plain JSON-safe scalars), `diagnostics_ref`. The online path in Phase 7 must return the **same-shaped** object (with `source` distinguishing offline vs a provider). Design the provider return type so Phase 7 can slot it in without reshaping.
- **v0.50.0 optional-dependency discipline** (rugarch/did/openxlsx precedent): every optional feature guarded by `requireNamespace()`, deps in `Suggests`, graceful clear error when absent. `httr2`/`jsonlite` follow this exact pattern.
- **Degenerate-input contract** (`R/contract.R`): the "NA + one warning, never silently wrong, never crash" discipline is the template for provider failure handling.
- `%||%` (rlang) for arg→env→default resolution chains.

### Established Patterns
- R6 classes PascalCase, inherit from a `*Base`; public methods + private helpers + `initialize()` validation (mirror `ModelBase`, `TestStatisticBase`).
- Public functions snake_case `@export`; internal helpers leading-dot `@noRd`; testthat 3e with `helper-*.R`.
- Optional deps referenced only inside `requireNamespace()`-guarded branches so `R CMD check` stays clean with them uninstalled.

### Integration Points
- `DESCRIPTION`: add `httr2`, `jsonlite` to **`Suggests`** (not Imports). No new hard dependency.
- New exports: the provider constructors / a `provider()` factory + resolution helper; NAMESPACE regenerated via roxygen2.
- Phase 7 consumes: a resolved provider object whose `complete()`-equivalent returns text (or a structured failure) for `es_advise()` to ground-check.

</code_context>

<specifics>
## Specific Ideas

- **Offline test seam is the linchpin:** `httr2::with_mocked_responses` (mock 200/4xx/5xx/malformed-body/timeout) + `CustomProvider` gives full-coverage deterministic tests with zero network. Assert on every failure path: (a) no key in the emitted condition text, (b) exactly one warning, (c) `NA`/failure return — never an uncaught error.
- **Key-redaction test is mandatory:** a test that forces an error with a known dummy key and asserts the key string is absent from the condition message and any captured output.
- **OpenAI-compatible covers local models for free:** Ollama (`http://localhost:11434/v1`) and LM Studio are just `base_url` overrides on `OpenAICompatProvider` — one class, many backends. Add a doc example.
- CRAN: guard all `httr2`/`jsonlite` use; `skip_on_cran()` any test that would touch a real endpoint; ensure examples don't perform live calls (`\dontrun{}` / `if (interactive())`).

</specifics>

<deferred>
## Deferred Ideas

- Grounded `es_advise()` interpretation, the grounding guard (`.validate_grounding()`), report-narrative drafting → Phase 7.
- Agent Skill, waitlist, green-check gate → Phase 8.
- Retrieval-corpus "Advisor Pro" (RAG) + managed hosting → future waitlist-gated milestone.
- Streaming responses / multi-turn chat state — not needed for single-shot grounded advice; out of scope unless Phase 7 surfaces a need.

</deferred>
