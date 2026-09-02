# Stack Research

**Domain:** LLM-agnostic AI advisor layer for a CRAN R package (financial event study analysis)
**Researched:** 2026-09-02
**Confidence:** HIGH (versions verified on CRAN; provider structured-output shapes verified against official API docs)

> Authored by the orchestrator after the dispatched Stack researcher twice hit a transient 1M-context billing gate (it had to read the 41KB ARCHITECTURE.md, which pushed its context past the standard window). Content is cross-checked against the sibling ARCHITECTURE/FEATURES/PITFALLS research and current CRAN/API docs. Confidence is HIGH for this well-trodden ground.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| R6 | (existing) | Provider abstraction hierarchy (`AdvisorProvider` base → subclasses) | Already the codebase's only polymorphism mechanism (ModelBase, TestStatisticBase); zero new dep; keeps the custom-provider hook idiomatic |
| httr2 | 1.2.2 | HTTP client for LLM REST calls (Anthropic Messages, OpenAI-compatible `/chat/completions`) | Modern pipe interface; built-in `req_retry()` (exponential backoff + `Retry-After`), `req_timeout()`, `req_error()`; the maintained successor to httr; the R HTTP standard |
| jsonlite | ≥ 1.8.0 | Serialize the request body + parse/validate the structured `Advice` response | Ubiquitous, stable, already an indirect dep across the tidyverse; `fromJSON(simplifyVector=FALSE)` gives predictable nested lists for the grounding guard |

### The provider-layer fork: ellmer vs. hand-rolled httr2

There are two viable ways to build the LLM-agnostic layer. **This is the one decision to settle in the AI-integration/planning phase** — both keep the offline `es_diagnostics()` layer dependency-free.

| Option | What it is | Pros | Cons |
|--------|-----------|------|------|
| **ellmer** (tidyverse, on CRAN) — *recommended primary* | Purpose-built provider-agnostic LLM client: `chat_anthropic()`, `chat_openai()`, `chat_google_gemini()`, `chat_ollama()`, plus structured output via `type_object()`/`chat_structured()` and tool calling | Delivers "agnostic from the LLM" out of the box; **normalizes the Anthropic-vs-OpenAI structured-output difference for us** (see below); maintained by Posit; a natural fit for a tidyverse-style package | Larger dependency tree (S7, etc.) — must live in Suggests; less direct control over the exact request; custom-provider hook still needs a thin seam |
| **Thin httr2 layer** — *fallback* | Our own `AdvisorProvider` R6 subclasses issuing httr2 requests to two endpoint shapes | Minimal deps (httr2 + jsonlite only); total control over request/response and the grounding guard; the custom-provider hook is trivial | We hand-write and maintain the Anthropic tool-use vs OpenAI `json_schema` normalization and ret/timeout logic ourselves |

**Recommendation:** default to **ellmer in Suggests** for the two built-in providers, and keep a small `AdvisorProvider`/`CustomProvider` R6 seam so a user can plug any callable (satisfying the confirmed "custom-provider hook" requirement) without ellmer. If the dependency tree proves too heavy for CRAN comfort, fall back to the thin httr2 layer — the R6 seam and the grounding guard are identical either way, so this choice is contained to one file (`advisor_provider.R`).

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| httptest2 | 1.2.0 | Record/replay + mock HTTP for testing httr2 code offline | Test the provider layer with **no network**; `with_mock_dir()` / `with_mock_api()`; same author as httr2 (Neal Richardson), lighter than vcr |
| withr | (existing/Suggests) | Scoped env vars in tests (`withr::local_envvar()`) | Set/unset fake `ANTHROPIC_API_KEY` etc. deterministically inside a test without leaking to the session |
| keyring | optional (Suggests) | OS-keychain storage for API keys | Only as an *optional* convenience; never required — `Sys.getenv()` is the baseline |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `skip_on_cran()` | Guard any test that could touch a network or needs a key | Wrap all live-path tests; mock/guard tests run everywhere |
| `@examplesIf` / `\donttest{}` | Keep documentation examples from calling the network on CRAN | Gate advisor examples on `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` |
| roxygen2 7.3.3 (existing) | Docs + NAMESPACE | Advisor exports documented like the rest of the package |

## Installation

```r
# Suggests only — the LLM layer is optional; offline es_diagnostics() needs none of these
# DESCRIPTION: Suggests: ellmer, httr2, jsonlite, httptest2, withr, keyring

install.packages(c("ellmer", "httr2", "jsonlite"))   # runtime (advise path)
install.packages(c("httptest2", "withr"))            # tests
# keyring optional
```

## Provider structured-output normalization (the key technical detail)

The two provider families request structured JSON differently. The provider layer must present ONE `Advice` schema to the rest of the package and hide this difference:

- **Anthropic Messages API** — structured output via **tool use**: define a tool whose `input_schema` is the `Advice` JSON Schema, set `tool_choice` to force that tool; the model returns the object in `tool_use.input`. Auth header `x-api-key` + `anthropic-version`.
- **OpenAI-compatible `/chat/completions`** — structured output via **`response_format: {type: "json_schema", json_schema: {...}}`** (Structured Outputs). Covers Ollama/LM Studio/gateways that implement the OpenAI schema. Auth header `Authorization: Bearer …`.
- **ellmer** collapses both behind `type_object()` + `chat_structured()`, which is the main argument for using it. If hand-rolling, one `.to_provider_schema()` translator per family is required.

Non-streaming responses only (recommended) — simpler, deterministic, easier to mock.

## Testing without network (CRAN-safe)

Three-layer strategy, established by rOpenSci's HTTP-testing guidance:

1. **Grounding guard + schema + diagnostics** — pure R, no HTTP, tested directly and exhaustively. This is where correctness lives.
2. **Provider request construction** — assert the built request (URL, headers minus secrets, body) with httptest2 mocks or static fixtures; no live call.
3. **End-to-end happy path** — `skip_on_cran()`, run only when a real key is present in a dev/CI secret.

**httptest2 vs vcr:** prefer **httptest2** — lighter, same maintainer as httr2, mock-directory model fits this use. For the provider layer specifically, prefer **static hand-crafted mock JSON fixtures** over recorded cassettes: a recorded cassette can capture an `Authorization`/`x-api-key` header if redaction is misconfigured, whereas a hand-written fixture has no secret-exposure surface. (Per PITFALLS.md.)

## Token-budget heuristic (no tokenizer dependency)

Cap the diagnostics payload before the API call with `nchar(jsonlite::toJSON(diagnostics)) / 4` as a rough token estimate; enforce a row cap on any per-event tables in the diagnostics serializer rather than trusting the heuristic. Avoids adding a tokenizer dependency.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| ellmer (Suggests) | Thin httr2 provider layer | If ellmer's dependency tree is too heavy for CRAN comfort, or maximal request control is needed |
| httptest2 | vcr | If you need richer redaction config or already standardized on vcr elsewhere |
| httr2 | (raw) curl / httr | Never for new code — httr is superseded; curl is too low-level |
| Env-var keys (`Sys.getenv`) | keyring | Only as optional convenience for interactive users |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Heavy per-provider SDK wrappers (one dep per vendor) | Explodes the dependency surface; defeats "agnostic"; CRAN-fragile | One OpenAI-compatible path + Anthropic, or ellmer |
| reticulate / Python LLM libs | Adds a Python runtime dep to a pure-R CRAN package | Native R HTTP (httr2/ellmer) |
| Streaming responses | Non-deterministic, hard to mock/test, no benefit for a one-shot advise call | Non-streaming request |
| Storing/committing API keys, or keys in fixtures/logs | Secret leak; CRAN + security failure | `Sys.getenv()` only; redact in all fixtures |
| Any network call in `es_diagnostics()`, examples, or default tests | CRAN prohibits network in checks; breaks the offline guarantee | Offline layer stays pure base R; live paths behind `skip_on_cran()` |
| Adding httr2/ellmer to Imports | Would force the dep on every user incl. offline/no-key users; risks R CMD check | Suggests + `requireNamespace()` guard |

## Stack Patterns by Variant

**If the user has no API key / is offline:**
- Only `es_diagnostics()` runs (pure base R); `es_advise()` errors clearly ("advisor requires an LLM provider; set ANTHROPIC_API_KEY or configure a provider") — never a silent wrong result.
- Rule-based recommendations (assumption→test decision table) can still run without any LLM, as a non-LLM fallback for `recommend_stat`/`flag_robustness`.

**If the user wants a local model:**
- Point the OpenAI-compatible provider at an Ollama/LM Studio base URL via `EVENTSTUDY_ADVISOR_BASE_URL`; no code change.

**If the user wants an unsupported provider:**
- `CustomProvider` accepts a user function `(prompt, schema) -> list`; satisfies the custom-provider hook requirement with zero package changes.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| httr2 1.2.2 | R ≥ 4.1, httptest2 1.2.0 | httptest2 tracks httr2; keep them paired |
| ellmer (CRAN) | R ≥ 4.1 | Pulls S7 and friends — Suggests only; verify R CMD check with it absent |
| jsonlite ≥ 1.8 | base R | No constraints |

## Sources

- [CRAN: httr2](https://cran.r-project.org/package=httr2) — current version 1.2.2 (released 2026-05-08), retry/timeout/error API
- [CRAN: httptest2](https://cran.r-project.org/package=httptest2) — current version 1.2.0, httr2 test helpers
- [ellmer (tidyverse)](https://ellmer.tidyverse.org/) — provider-agnostic LLM client, structured output via `type_object()`, providers incl. Anthropic/OpenAI/Gemini/Ollama
- [Getting started with ellmer](https://cran.r-project.org/web/packages/ellmer/vignettes/ellmer.html) — structured data extraction, tool calling
- Sibling research: `.planning/research/ARCHITECTURE.md` (provider R6 design, build order), `.planning/research/PITFALLS.md` (CRAN network policy, secret-leak avoidance, static-mock rationale)
- CRAN Repository Policy — no network in checks, no phoning home without consent (verified via PITFALLS.md research)

---
*Stack research for: LLM-agnostic AI advisor on a CRAN R package*
*Researched: 2026-09-02*
