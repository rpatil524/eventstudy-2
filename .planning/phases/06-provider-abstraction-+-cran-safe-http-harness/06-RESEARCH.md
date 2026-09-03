# Phase 6: Provider Abstraction + CRAN-Safe HTTP Harness - Research

**Researched:** 2026-09-03
**Domain:** R6 strategy pattern + thin `httr2` HTTP client for LLM providers, CRAN-safe optional-dependency discipline, offline testthat mocking
**Confidence:** HIGH

## Summary

This phase builds a uniform LLM-provider seam over a **hand-rolled thin `httr2` client** (RESOLVED — not Posit `ellmer`). The design is a three-class R6 strategy hierarchy (`OpenAICompatProvider`, `AnthropicProvider`, `CustomProvider`) descending from an abstract `ProviderBase`, mirroring the package's existing `ModelBase` / `TestStatisticBase` inheritance idiom. Every network, status, and parse failure is trapped and degraded to a single `warning()` plus a failure return that aligns with the Phase 5 `es_advice` S3 contract — reproducing the package's degenerate-input discipline (`R/contract.R`) at the HTTP layer. The entire LLM stack lives in `Suggests`, `requireNamespace()`-guarded, so `R CMD check` stays clean with `httr2`/`jsonlite` uninstalled and the Phase 5 offline layer keeps working with zero of these deps.

The linchpin is **offline testability**: `httr2::with_mocked_responses()` (verified present in the installed httr2 1.2.3) drives 200 / 4xx / 5xx / malformed-body / timeout scenarios with no network and no keys, and `CustomProvider` provides an in-process end-to-end seam. All three verified this session against the live `httr2` runtime.

The single most important verified implementation detail: **`req_auth_bearer_token()` redacts the `Authorization` header by default, but a manually-set `x-api-key` header (needed for Anthropic) is NOT redacted** — you must use `req_headers_redacted("x-api-key" = key)` for the Anthropic provider, or the dummy key leaks in `httr2` error/request printing. This was live-tested this session.

**Primary recommendation:** Build `ProviderBase` with a `complete(prompt, ...)` public method; factor a single private `.perform_request()` helper that wraps `req_perform()` in `tryCatch` + `req_error(is_error = ~ FALSE)` so non-2xx and transport failures both return inspectable objects; redact keys with `req_auth_bearer_token()` (OpenAI) and `req_headers_redacted()` (Anthropic); return an `es_advice`-shaped failure list (`source`, `is_deterministic = FALSE`, `text = NA_character_`) on every failure path with exactly one `warning()`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Provider Implementation — RESOLVED FORK (user decision 2026-09-03)**
- **Hand-rolled thin `httr2` client — NOT Posit `ellmer`.** Chosen for the smallest dependency surface, full control over key redaction and never-crash error trapping, and deterministic offline mocking. `ellmer`'s higher-level chat abstractions would enlarge the Suggests footprint and force coarser mocking with less control over the exact guarantees this phase's goal demands.
- LLM HTTP deps (`httr2`, `jsonlite`) stay in **`Suggests`**, every entry point guarded by `requireNamespace(..., quietly = TRUE)` (v0.50.0 discipline). Absent deps → a clear, actionable error, never a crash.

**Provider Class Shape (R6 strategy pattern)**
- `ProviderBase` (abstract R6): defines the `complete(prompt, ...)` (or equivalent) contract and shared request/response/error plumbing.
- `OpenAICompatProvider`: `base_url` + key → `POST {base_url}/chat/completions`; covers OpenAI, Ollama, LM Studio, and any OpenAI-compatible gateway via configurable `base_url` + `model`.
- `AnthropicProvider`: native `POST /v1/messages` with the Anthropic auth header + `anthropic-version`.
- `CustomProvider`: wraps a user `function(prompt) -> character` — the in-process, **offline test seam** and the escape hatch for unsupported backends.

**Backend Resolution**
- Precedence: **explicit argument → environment variable → default**. Env var names follow provider convention (e.g. `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_BASE_URL`). Missing key surfaces one clear error at call time, not at construction, and never prints the key.

**Failure & Safety Contract**
- **Never crash the session:** all network/parse/status failures are trapped (`httr2::req_error`, `tryCatch`) and degrade to a returned failure signal — return `NA`/`NULL` advice with **one** actionable `warning()`, consistent with the package's degenerate-input contract.
- **Never leak keys:** keys are redacted from every error message, condition, and any logged/echoed request. No key ever appears in a `warning`, `stop`, `print`, or test snapshot.
- **Offline-first tests:** the full provider suite runs with **no real API call** — `httr2::with_mocked_responses` for the HTTP providers and the `CustomProvider` fn seam for end-to-end. Tests must pass on CRAN machines with no network and no keys set (skip real-endpoint tests via `testthat::skip_if_offline()` / `skip_on_cran()` only where a live call would otherwise be needed — but coverage of the seam itself must not depend on it).

### Claude's Discretion
- Exact method names on `ProviderBase`, the internal request-builder helper factoring, the failure return shape (must align with the Phase 7 `Advice`/`es_advice` contract), retry/timeout defaults, and env-var naming details are at Claude's discretion, guided by codebase conventions and Phase 7 consumption needs.

### Deferred Ideas (OUT OF SCOPE)
- Grounded `es_advise()` interpretation, the grounding guard (`.validate_grounding()`), report-narrative drafting → Phase 7.
- Agent Skill, waitlist, green-check gate → Phase 8.
- Retrieval-corpus "Advisor Pro" (RAG) + managed hosting → future waitlist-gated milestone.
- Streaming responses / multi-turn chat state — not needed for single-shot grounded advice; out of scope unless Phase 7 surfaces a need.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROV-01 | `AdvisorProvider`/`ProviderBase` R6 base, uniform contract consistent with `ModelBase`/`TestStatisticBase` | R6 shape section; inheritance idiom verified against `R/models.R` conventions |
| PROV-02 | Anthropic Messages using tool-use structured output (`input_schema`) | Anthropic wire-format section; `POST /v1/messages` body + `anthropic-version` header verified via claude-api reference |
| PROV-03 | OpenAI-compatible using `response_format` json_schema, any base URL incl Ollama/LM Studio | OpenAI wire-format section; `POST {base_url}/chat/completions`; `req_url_path_append` idiom |
| PROV-04 | `CustomProvider` `(prompt, schema) -> list` | CustomProvider seam section; the offline end-to-end test vehicle |
| PROV-05 | 3-tier precedence: arg → env var `EVENTSTUDY_ADVISOR_PROVIDER`/`_MODEL`/`_BASE_URL` → default | Backend resolution section; `%||%` chain + `Sys.getenv` idiom |
| PROV-06 | Keys env-only, never logged/bundled/committed/in-fixtures, redacted from errors | Key-redaction section — **critical `req_headers_redacted()` finding for Anthropic** |
| PROV-07 | Failures degrade → warning + NULL, never crash | Failure-trapping section; `req_error` + `tryCatch` + `es_advice` failure shape |
| PROV-08 | All LLM/HTTP deps in Suggests, requireNamespace-guarded | DESCRIPTION section; `report.R` guard idiom |
| CRAN-02 | No new R CMD check NOTEs/WARNINGs; Suggests-vs-Imports respected | CRAN doc discipline section |
| CRAN-03 | Provider tested offline with mocks/static fixtures; deterministic regression tests | Offline mocking section — `with_mocked_responses` recipes |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Provider strategy dispatch | R6 object layer (`R/provider.R`) | — | Pluggable backends mirror the `ModelBase`/`TestStatisticBase` strategy pattern already in the package |
| HTTP request construction | Private helper inside provider classes | `httr2` (Suggests) | Thin client — request assembly is package code; transport is `httr2` |
| JSON serialize/parse | Private helper | `jsonlite` (Suggests) — or `httr2`'s built-in | Body build + response parse; both guarded |
| Key resolution (arg→env→default) | Package helper (`.resolve_*`) | base R `Sys.getenv`, `rlang::%||%` | Pure R logic, no dependency; env read at call time not construction |
| Key redaction | `httr2` request layer | — | `req_auth_bearer_token` / `req_headers_redacted` do redaction in the request object |
| Failure trapping / degrade | Provider `complete()` + private `.perform_request()` | base R `tryCatch`, `httr2::req_error` | Mirror `R/contract.R` `.handle_degenerate()` discipline |
| Offline test doubles | testthat suite | `httr2::with_mocked_responses`, `CustomProvider` | Deterministic, network-free, CRAN-safe |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `httr2` | 1.2.3 `[VERIFIED: installed runtime]` | HTTP request/response/error/retry/timeout + mocking | Modern successor to `httr`; explicit request-object pipeline; built-in redaction and `with_mocked_responses` mocking. Tidyverse-blessed. |
| `jsonlite` | 2.0.0 `[VERIFIED: installed runtime]` | JSON body build + response parse | The de-facto R JSON library; `httr2` uses it internally for `req_body_json`/`resp_body_json`. Can rely on httr2's built-ins and skip a direct import, but listing it makes the parse-side explicit. |
| `R6` | (Imports, already present) | Strategy-pattern class system | Already a hard dependency; all model/statistic classes use it. |
| `rlang` | (Imports, already present) | `%||%` for arg→env→default chains | Already imported; `%||%` is the idiomatic resolution operator used across the codebase (`R/diagnostics.R:81`, `R/task.R:325`). |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `withr` | (already in Suggests) | `withr::local_envvar()` in tests to set/unset dummy keys deterministically | Test setup for env-var resolution paths without polluting the session. |
| `testthat` | ≥ 3.0.0 (Suggests) | 3e test framework; `skip_on_cran()`, `skip_if_offline()`, `expect_warning`, `expect_no_error` | The whole offline suite. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled `httr2` | Posit `ellmer` | REJECTED by user decision — larger Suggests footprint, coarser mocking, less control over exact redaction/never-crash guarantees. |
| `httr2` | legacy `httr` | `httr` is superseded; no `with_mocked_responses`, weaker redaction, discouraged for new code. |
| `jsonlite` direct | `httr2::resp_body_json()` / `req_body_json()` (which use jsonlite internally) | Using httr2's built-ins means you *may* not need `jsonlite` in Suggests at all — but declaring it is harmless and makes intent explicit. Planner's call. |

**Installation:**
```r
# Added to Suggests, NOT Imports:
# httr2 (>= 1.0.0), jsonlite
```

**Version verification (run this session):**
- `packageVersion("httr2")` → **1.2.3** `[VERIFIED: installed runtime]`
- `packageVersion("jsonlite")` → **2.0.0** `[VERIFIED: installed runtime]`
- R version → **4.6.1** `[VERIFIED: installed runtime]`

The planner should add a minimum version floor `httr2 (>= 1.0.0)` in DESCRIPTION Suggests, because `with_mocked_responses` / `req_headers_redacted` are 1.0+ API. `[ASSUMED]` — the exact introduction version of `req_headers_redacted` was not confirmed against the httr2 changelog this session; 1.2.3 has it (verified), so the floor is safe but may be conservative.

## Package Legitimacy Audit

> Both packages are on CRAN, Posit-maintained (tidyverse org), and already installed in this session. Discovered from authoritative source (installed runtime + tidyverse provenance), not WebSearch.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `httr2` | CRAN | mature (Posit/tidyverse) | very high | github.com/r-lib/httr2 | OK | Approved |
| `jsonlite` | CRAN | mature (>10 yrs) | very high | github.com/jeroen/jsonlite | OK | Approved |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

Note: `gsd-tools query package-legitimacy check` targets npm/pypi/crates ecosystems, not CRAN — not applicable here. Both packages are verified present in the installed R library this session and are canonical tidyverse packages; this is stronger evidence than a registry lookup.

## Architecture Patterns

### System Architecture Diagram

```
                         provider() factory / resolver
                                     │
              arg → env var → default  (%||% chain, read at call time)
                                     │
                         ┌───────────┴───────────┐
                         ▼                       │
                   ProviderBase (R6, abstract)   │  complete(prompt, ...) contract
                   ├── initialize() validation   │  private $.perform_request()
                   └── $complete() = <abstract>   │
                         │                        │
        ┌────────────────┼─────────────────┬──────┘
        ▼                ▼                  ▼
 OpenAICompatProvider  AnthropicProvider  CustomProvider
   build OpenAI body     build Anthropic     wrap user fn(prompt)
   POST base_url/         body                     │
     chat/completions   POST /v1/messages          │  (no HTTP — in-process seam)
        │                │                         │
        └────────┬───────┘                         │
                 ▼                                  │
        .perform_request()  (httr2)                 │
        req() |> req_url_path_append()              │
             |> req_body_json()                     │
             |> req_auth_bearer_token()  ← OpenAI   │
             |> req_headers_redacted()   ← Anthropic│
             |> req_timeout() |> req_retry()        │
             |> req_error(is_error = ~FALSE)        │
             |> req_perform()                       │
                 │                                  │
     tryCatch ───┤ transport/timeout → httr2_failure│
                 ▼                                  │
        resp_status() branch                        │
        ├── 2xx → resp_body_json() (tryCatch)       │
        │         extract completion text           │
        └── non-2xx → degrade                       │
                 │                                  │
                 └──────────────┬───────────────────┘
                                ▼
              es_advice-shaped return
              success: {source, is_deterministic=FALSE, text, ...}
              failure: {source, is_deterministic=FALSE, text=NA} + ONE warning()
```

### Recommended Project Structure
```
R/
├── provider.R          # ProviderBase + all three subclasses + provider() factory
│                       #   (or split: provider_base.R / provider_openai.R / provider_anthropic.R / provider_custom.R)
├── provider_http.R     # (optional) private .perform_request / .build_request helpers
tests/testthat/
├── helper-provider.R   # mock response builders, dummy-key fixtures
├── test-provider-openai.R
├── test-provider-anthropic.R
├── test-provider-custom.R
├── test-provider-resolution.R   # arg→env→default precedence
└── test-provider-redaction.R    # mandatory key-leak test
```

### Pattern 1: httr2 request lifecycle (thin client)
**What:** A single left-to-right pipeline builds the request; `req_perform()` executes; response accessors read status/body. `req_error(is_error = ...)` and `tryCatch` convert every failure into an inspectable value rather than an uncaught condition.
**When to use:** Every HTTP provider's `.perform_request()` private method.
**Example:**
```r
# Source: httr2 request pipeline, verified live against httr2 1.2.3
.perform_request <- function(base_url, path, body, key,
                             auth = c("bearer", "x-api-key"),
                             extra_headers = list(),
                             timeout = 30, max_tries = 2) {
  auth <- match.arg(auth)

  req <- httr2::request(base_url) |>
    httr2::req_url_path_append(path) |>              # e.g. "chat/completions" or "v1/messages"
    httr2::req_body_json(body) |>                    # jsonlite-encoded body + content-type
    httr2::req_timeout(timeout) |>
    httr2::req_retry(max_tries = max_tries,          # signature verified live (see below)
                     retry_on_failure = FALSE) |>
    # CRITICAL: is_error = FALSE turns non-2xx into a normal return so we branch
    # on status ourselves instead of httr2 throwing an httr2_http_* condition.
    httr2::req_error(is_error = function(resp) FALSE)

  # Redaction depends on auth scheme (see Key Redaction section — VERIFIED)
  if (auth == "bearer") {
    req <- httr2::req_auth_bearer_token(req, key)        # Authorization: Bearer — auto-redacted
  } else {
    req <- httr2::req_headers_redacted(req, "x-api-key" = key)  # MUST use *_redacted for x-api-key
  }
  if (length(extra_headers)) {
    req <- do.call(httr2::req_headers, c(list(req), extra_headers))
  }

  # Transport/timeout failures raise httr2_failure — trap to a sentinel.
  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) e            # httr2_failure condition object
  )
  resp
}
```

**Verified `req_retry` signature (live this session):**
`function(req, max_tries = NULL, max_seconds = NULL, retry_on_failure = FALSE, is_transient = NULL, backoff = NULL, after = NULL, failure_threshold = Inf, failure_timeout = 30, failure_realm = NULL)` `[VERIFIED: httr2 1.2.3 runtime]`.

Retry/timeout defaults are Claude's discretion — recommend conservative `timeout = 30`, `max_tries = 2`, `retry_on_failure = FALSE` (don't retry transport failures — a network-down machine should fail fast to one warning, not stall). `[ASSUMED]` — these are judgement defaults, confirm no long-hang risk with the planner.

### Pattern 2: Status-branch + safe body extraction
**What:** After `.perform_request()`, branch on the returned object's class/status. Wrap `resp_body_json()` in `tryCatch` because a 200 with a malformed body still errors on parse.
**When to use:** Inside each subclass `complete()` after the shared request helper returns.
**Example:**
```r
# Source: httr2 response handling, verified live (malformed-JSON trapping confirmed)
.finish_response <- function(resp, extract_fn, source_label) {
  # Transport/timeout failure came back as a condition object
  if (inherits(resp, "condition")) {
    return(.provider_failure(source_label, "request failed (network/timeout)"))
  }
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    return(.provider_failure(source_label,
                             paste0("HTTP ", status)))  # never include body/key
  }
  parsed <- tryCatch(
    httr2::resp_body_json(resp),
    error = function(e) NULL             # malformed body → NULL, not a crash
  )
  if (is.null(parsed)) {
    return(.provider_failure(source_label, "malformed response body"))
  }
  text <- tryCatch(extract_fn(parsed), error = function(e) NA_character_)
  if (is.na(text) || !nzchar(text)) {
    return(.provider_failure(source_label, "no completion text in response"))
  }
  .provider_success(source_label, text)
}
```

### Pattern 3: es_advice-aligned failure/success shape (Phase 7 forward-compat)
**What:** Both success and failure return an `es_advice`-shaped list so Phase 7 can slot the online path next to the offline path without reshaping.
**When to use:** The return value of every provider `complete()`.
**Example:**
```r
# Aligns with .build_offline_advice() structure in R/advise_offline.R:221-229
# [VERIFIED: R/advise_offline.R:221-230] — offline builder returns:
#   structure(list(source, is_deterministic=TRUE, rules_matched, diagnostics_ref),
#             class = "es_advice")
# The provider path is NOT deterministic and returns raw text for Phase 7 to ground-check.

.provider_success <- function(source_label, text) {
  structure(
    list(
      source           = source_label,     # e.g. "openai", "anthropic", "custom"
      is_deterministic = FALSE,            # LLM output, unlike offline_kb (TRUE)
      text             = text,             # raw completion for Phase 7 grounding
      error            = NULL
    ),
    class = "es_provider_response"          # distinct from es_advice; Phase 7 wraps it
  )
}

.provider_failure <- function(source_label, reason) {
  warning(sprintf("Advisor provider '%s' failed: %s. Returning NA.",
                  source_label, reason), call. = FALSE)   # EXACTLY ONE warning
  structure(
    list(
      source           = source_label,
      is_deterministic = FALSE,
      text             = NA_character_,
      error            = reason
    ),
    class = "es_provider_response"
  )
}
```

**Design note for the planner (Claude's discretion resolved):** The offline path uses `class = "es_advice"` with `is_deterministic = TRUE`, `rules_matched`, `diagnostics_ref` `[VERIFIED: R/advise_offline.R:221-229]`. The provider path returns *raw text*, not matched rules — Phase 7's `es_advise()` is what turns provider text into an `es_advice`. So the provider return should be a **distinct, simpler class** (`es_provider_response` above) carrying `source` + `text` + `error`, NOT a full `es_advice`. This keeps the seam clean: provider = transport, Phase 7 = interpretation. The `source`/`is_deterministic` field names are kept identical so Phase 7's wrapper is trivial.

### Anti-Patterns to Avoid
- **Reading the API key at construction time.** CONTEXT mandates resolution at *call time*. Store the resolution inputs (explicit arg, env-var name), resolve inside `complete()`. A missing key must surface one clear error at call, not a construction crash.
- **Letting `httr2` throw on non-2xx.** Default `req_perform` throws `httr2_http_4xx`/`5xx`. Without `req_error(is_error = ~FALSE)` you must catch a condition subclass hierarchy; with it you branch on `resp_status()` cleanly. (Both work — the `req_error` approach is simpler and was verified live.)
- **Setting `x-api-key` via plain `req_headers()`.** VERIFIED to leak the key in request/error printing. Always `req_headers_redacted()` for `x-api-key`.
- **Emitting more than one warning per failure.** The contract is exactly one `warning()`. Do not warn in the helper AND again in `complete()`. Centralize the warning in `.provider_failure()`.
- **Substituting a fabricated string on parse failure.** Return `NA_character_`, never a plausible-looking wrong completion — this is the package's "never silently wrong" core value applied to the LLM layer.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP retries/backoff | manual `for`-loop + `Sys.sleep` | `httr2::req_retry()` | Correct exponential backoff, `Retry-After` handling, transient-error detection built in. |
| Key redaction in errors | manual string-scrubbing of messages | `req_auth_bearer_token()` + `req_headers_redacted()` | httr2 marks headers as redacted at the request-object level so they never appear in *any* print/error path. Manual scrubbing misses paths. |
| JSON encode/decode | `paste0` string-building | `req_body_json()` / `resp_body_json()` (jsonlite) | Correct escaping, unicode, nesting; string-building JSON is a classic injection/escaping bug source. |
| Timeout enforcement | `setTimeLimit` / `tryCatch` on wall clock | `req_timeout()` | Enforced at the curl layer, cross-platform, doesn't leave dangling connections. |
| HTTP mocking in tests | custom function-stubbing of `req_perform` | `httr2::with_mocked_responses()` | First-class mock API; constructs real `httr2_response` objects so `resp_status`/`resp_body_json` behave exactly as in production. |

**Key insight:** The whole value of choosing `httr2` over a bespoke client is that redaction, retry, timeout, and mocking are *already correct*. The package code is thin: build a body, pick an auth scheme, branch on status. Everything hard is delegated.

## Runtime State Inventory

> Not a rename/refactor phase — this is purely additive greenfield code. Section retained per protocol.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore keys or IDs introduced. | none |
| Live service config | None — no external service registration; API endpoints are user-supplied at call time. | none |
| OS-registered state | None. | none |
| Secrets/env vars | **New env vars READ (never written): `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_BASE_URL`, and the EVENTSTUDY_ADVISOR_* per REQUIREMENTS.** These are read at call time; the package never sets, writes, or persists them. Tests set dummy values via `withr::local_envvar()` only. | Document env-var names in roxygen; ensure `.Renviron`/keys never committed or bundled (PROV-06). |
| Build artifacts | NAMESPACE regenerated by roxygen2 for new exports; no compiled artifacts. | Run `devtools::document()`. |

**Nothing found requiring data migration** — this phase writes no persistent state.

## Common Pitfalls

### Pitfall 1: `x-api-key` leaks despite `req_auth_bearer_token` habits
**What goes wrong:** Developers assume httr2 redacts all auth headers. It redacts `Authorization` (via `req_auth_bearer_token`) but a manually-set `x-api-key` (Anthropic's scheme) prints in cleartext.
**Why it happens:** Redaction is opt-in per header; only the auth-helper-managed header is auto-redacted.
**How to avoid:** Use `httr2::req_headers_redacted("x-api-key" = key)` for Anthropic. `[VERIFIED: httr2 1.2.3 runtime]` — live-tested that `req_headers("x-api-key" = key)` prints the secret in `capture.output(print(req))` while `req_headers_redacted(...)` prints `<REDACTED>`.
**Warning signs:** The mandatory redaction test (dummy key + assert-absent) will catch this — it MUST exist (PROV-06).

### Pitfall 2: `req_perform` throws on 4xx/5xx before you can branch
**What goes wrong:** Without `req_error()`, a 401 raises `httr2_http_401`; a 500 raises `httr2_http_500`. Uncaught, these crash the call.
**Why it happens:** httr2's default `is_error` treats non-2xx as errors.
**How to avoid:** Either (a) `req_error(is_error = function(resp) FALSE)` then branch on `resp_status()` (recommended, verified), or (b) `tryCatch` the `httr2_http_*` / `httr2_failure` condition classes. `[VERIFIED: httr2 1.2.3 runtime]` — confirmed 4xx auto-errors as `httr2_http_401` and that `req_error(is_error = ~FALSE)` converts it to a normal return.
**Warning signs:** A test mocking a 404 that produces an uncaught error instead of a single warning.

### Pitfall 3: 200 OK with malformed body still crashes on parse
**What goes wrong:** `resp_body_json()` on a truncated/invalid JSON 200 raises a parse error.
**Why it happens:** Status success ≠ body validity.
**How to avoid:** Wrap `resp_body_json()` in `tryCatch(..., error = function(e) NULL)`; NULL → degrade path. `[VERIFIED: httr2 1.2.3 runtime]` — confirmed malformed JSON errors inside `resp_body_json` and is trappable.
**Warning signs:** A malformed-body mock scenario that errors instead of warning once + returning NA.

### Pitfall 4: `with_mocked_responses` vs `local_mocked_responses` version/scope confusion
**What goes wrong:** Using the wrong mocking entry point or expecting a signature it doesn't have.
**Why it happens:** httr2 has both `with_mocked_responses(mock, code)` (scoped to an expression) and `local_mocked_responses(mock, env = caller_env())` (scoped to the calling frame, auto-cleanup at test end). Both present in 1.2.3.
**How to avoid:** Prefer `local_mocked_responses()` inside a `test_that()` block (auto-teardown); use `with_mocked_responses()` when you need to scope a single expression. The `mock` argument is a function `function(req) <httr2_response>` (or a list of responses). Build responses with `httr2::response_json(status = ..., body = ...)` or `httr2::response(status_code = ...)`. `[VERIFIED: httr2 1.2.3 runtime]` — both functions and the `response`/`response_json` constructors confirmed present.
**Warning signs:** Mock not intercepting because it was set with the wrong scope, or a real network call leaking through.

### Pitfall 5: `requireNamespace` guard missing on an entry point
**What goes wrong:** `httr2`/`jsonlite` referenced outside a guard → `R CMD check` NOTE (Suggests used unconditionally) when the dep is uninstalled.
**Why it happens:** Forgetting the guard on one of several entry points.
**How to avoid:** Mirror `R/report.R:35-42` exactly — guard at the top of every public entry (`OpenAICompatProvider$new`/`$complete`, `AnthropicProvider`, the `provider()` factory). `CustomProvider` needs NO guard (no httr2). `[VERIFIED: R/report.R:35-42]` — the canonical idiom.
**Warning signs:** `R CMD check` with `httr2` removed from the library reports a NOTE.

## Code Examples

### Anthropic Messages request body (structured output via tool-use)
```r
# Source: claude-api reference (POST /v1/messages) — CITED
# Wire shape for AnthropicProvider$complete()
body <- list(
  model = model,                       # e.g. "claude-opus-4-8"
  max_tokens = 1024L,                  # REQUIRED by Anthropic API
  messages = list(
    list(role = "user", content = prompt)
  )
)
# Headers: x-api-key (REDACTED) + anthropic-version
# extra_headers = list("anthropic-version" = "2023-06-01")
# Completion text lives at: parsed$content[[1]]$text
#   (content is an array of blocks; take the first text block)
```
`[CITED: claude-api skill reference — curl/examples.md]` — `x-api-key`, `anthropic-version: 2023-06-01`, `max_tokens` required, and `.content[0].text` extraction path all from the Anthropic Messages reference. **PROV-02 note:** for *structured* output the reference uses tool-use with `input_schema` (a tool definition + `tool_choice`); the completion then lives in a `tool_use` block's `input`. For Phase 6 the plan can start with the plain text-block shape above and expose the tool-use/`input_schema` path as the structured variant — Phase 7 decides which it needs. `[ASSUMED]` — whether Phase 6 must implement the full `input_schema` tool-use path now or just the text path is a scoping call for the planner; REQUIREMENTS PROV-02 names `input_schema`, so implement the tool-use structured path.

### OpenAI-compatible request body (structured output via response_format)
```r
# Source: OpenAI chat/completions shape — CITED (widely documented)
# Wire shape for OpenAICompatProvider$complete()
body <- list(
  model = model,                       # e.g. "gpt-4o", or Ollama model name
  messages = list(
    list(role = "user", content = prompt)
  )
  # For structured output (PROV-03):
  # response_format = list(type = "json_schema",
  #                        json_schema = list(name = "advice", schema = <schema>))
)
# Header: Authorization: Bearer <key>  (auto-redacted by req_auth_bearer_token)
# base_url: OpenAI "https://api.openai.com/v1", Ollama "http://localhost:11434/v1",
#           LM Studio "http://localhost:1234/v1"  — all just base_url overrides
# Path appended: "chat/completions"
# Completion text lives at: parsed$choices[[1]]$message$content
```
`[CITED: OpenAI chat/completions API — standard shape]` — `.choices[0].message.content` extraction path and `response_format` json_schema. `[ASSUMED]` — exact `response_format`/`json_schema` sub-shape not re-verified against live OpenAI docs this session; the `.choices[0].message.content` path is stable and long-standing. The planner should gate any `response_format` specifics behind a note that local models (Ollama/LM Studio) may not support `response_format` — keep it optional so `base_url` overrides for local models still work with plain text completion.

### CustomProvider seam (offline end-to-end)
```r
# The in-process test seam and escape hatch — NO httr2, NO guard needed.
# PROV-04: user function is (prompt, schema) -> list (or -> character)
CustomProvider <- R6::R6Class("CustomProvider",
  inherit = ProviderBase,
  public = list(
    initialize = function(fn) {
      stopifnot(is.function(fn))
      private$.fn <- fn
    },
    complete = function(prompt, ...) {
      out <- tryCatch(private$.fn(prompt, ...),
                      error = function(e) e)
      if (inherits(out, "condition")) {
        return(.provider_failure("custom", "custom function errored"))
      }
      .provider_success("custom", as.character(out)[[1]])
    }
  ),
  private = list(.fn = NULL)
)
# In tests: CustomProvider$new(function(prompt, ...) "canned advice text")
# drives the whole complete() -> es_provider_response path with zero network.
```

### Offline mocking recipes (the CRAN-03 linchpin)
```r
# Source: httr2 with_mocked_responses / response constructors — VERIFIED present
# helper-provider.R
mock_200 <- function(body) {
  function(req) httr2::response_json(status = 200L, body = body)
}
mock_status <- function(code) {
  function(req) httr2::response(status_code = code)      # 401, 404, 500 ...
}
mock_malformed <- function() {
  function(req) httr2::response(status_code = 200L, body = charToRaw("{not json"))
}
mock_timeout <- function() {
  function(req) stop(structure(class = c("httr2_failure", "error", "condition"),
                               list(message = "timed out")))
}

# test-provider-openai.R
test_that("4xx degrades to one warning + NA, no key leak", {
  withr::local_envvar(OPENAI_API_KEY = "sk-DUMMYKEY-should-never-print")
  p <- OpenAICompatProvider$new(model = "gpt-4o")
  httr2::local_mocked_responses(mock_status(401L))
  expect_warning(res <- p$complete("hi"), "failed")
  expect_true(is.na(res$text))
})

# test-provider-redaction.R  (MANDATORY — PROV-06)
test_that("dummy key never appears in emitted condition or output", {
  key <- "sk-SECRET-DUMMY-abc123"
  withr::local_envvar(ANTHROPIC_API_KEY = key)
  p <- AnthropicProvider$new(model = "claude-opus-4-8")
  httr2::local_mocked_responses(mock_status(401L))
  msg <- tryCatch(p$complete("hi"),
                  warning = function(w) conditionMessage(w))
  expect_false(grepl(key, msg, fixed = TRUE))
  # also assert against the printed request object if the provider stores it
})
```
`[VERIFIED: httr2 1.2.3 runtime]` — `with_mocked_responses`, `local_mocked_responses`, `response`, and `response_json` all confirmed present with the signatures used above; malformed-JSON trapping and `httr2_failure`-based timeout simulation confirmed live.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `httr` (verb-based, `GET()`/`POST()`) | `httr2` (request-object pipeline) | httr2 GA ~2023 | Explicit pipeline, first-class mocking, built-in redaction — the reason this phase is feasible thin. |
| `mockery`/`testthat::with_mock` (removed) for stubbing | `httr2::with_mocked_responses` / `local_mocked_responses` | httr2 1.0+ | Real `httr2_response` objects, no fragile function-stubbing; CRAN-safe. |
| Manual `Authorization` header string | `req_auth_bearer_token()` | httr2 1.0 | Auto-redaction; no manual scrubbing. |

**Deprecated/outdated:**
- `testthat::with_mock()` / `with_mock` — defunct in testthat 3e; do NOT use. Use `httr2::local_mocked_responses`.
- `httr::POST()` — superseded; not used here.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `httr2 (>= 1.0.0)` is a safe Suggests floor for `req_headers_redacted`/`with_mocked_responses` | Standard Stack | If the floor is wrong, install works (1.2.3 present) but a too-low floor could let an old httr2 in that lacks these; bump floor if CI on old httr2 fails. Low risk — 1.2.3 verified has everything. |
| A2 | Retry/timeout defaults (`timeout=30`, `max_tries=2`, `retry_on_failure=FALSE`) | Pattern 1 | Wrong defaults could stall a run on a slow/hanging endpoint. Discretionary; confirm no long-hang path. |
| A3 | OpenAI `response_format` json_schema sub-shape not re-verified live; local models may not support it | OpenAI code example | If required and unsupported by Ollama/LM Studio, structured output fails for local models — keep `response_format` optional so plain-text path still works. |
| A4 | PROV-02 requires the full Anthropic tool-use `input_schema` structured path in Phase 6 (not just text) | Anthropic code example | REQUIREMENTS names `input_schema`; if only text is needed, extra work — but implementing tool-use is the safe reading. |
| A5 | `jsonlite` may be omittable if only httr2 built-ins are used | Alternatives Considered | None — declaring it is harmless; omitting it saves one Suggests line. Planner's call. |
| A6 | Env-var names: REQUIREMENTS says `EVENTSTUDY_ADVISOR_PROVIDER`/`_MODEL`/`_BASE_URL`; CONTEXT examples say `OPENAI_API_KEY`/`ANTHROPIC_API_KEY`/`OPENAI_BASE_URL` | Backend resolution / Runtime State | These serve different roles: `EVENTSTUDY_ADVISOR_*` selects provider/model/base-url; `*_API_KEY` supplies the secret per provider convention. Implement BOTH — the EVENTSTUDY_* selectors AND the conventional key vars. This is the reconciled reading; confirm with planner. |

## Open Questions

1. **Does Phase 6 implement the full Anthropic tool-use `input_schema` structured-output path, or defer to Phase 7?**
   - What we know: REQUIREMENTS PROV-02 explicitly names tool-use `input_schema`; CONTEXT leaves structured shape to discretion.
   - What's unclear: whether Phase 7 needs structured JSON from the provider or does its own parsing of raw text.
   - Recommendation: Implement the tool-use `input_schema` path for Anthropic and `response_format` json_schema for OpenAI (satisfies PROV-02/PROV-03 literally), but ALSO support plain-text completion as a fallback so local models work. Extraction returns text either way.

2. **Single `R/provider.R` file or split per class?**
   - What we know: package convention is one file per major component area (`models.R` holds multiple model classes).
   - Recommendation: one `R/provider.R` holding `ProviderBase` + three subclasses + `provider()` factory, matching `models.R`'s multi-class-per-file precedent. Split only if it exceeds ~400 lines.

3. **Should the `provider()` factory be exported, or only the three constructors?**
   - What we know: CONTEXT says "provider constructors / a `provider()` factory + resolution helper".
   - Recommendation: export both the three R6 generators AND a `provider(type = c("openai","anthropic","custom"), ...)` convenience factory that does arg→env→default resolution. NAMESPACE regenerated via roxygen2.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `httr2` | OpenAI/Anthropic providers | ✓ | 1.2.3 | `CustomProvider` (no HTTP) covers offline; providers error clearly if httr2 absent |
| `jsonlite` | body/response JSON | ✓ | 2.0.0 | httr2 built-ins (uses jsonlite internally anyway) |
| `withr` | test env-var scoping | ✓ | in Suggests | — |
| `testthat` | offline suite | ✓ | ≥ 3.0.0 | — |
| R | runtime | ✓ | 4.6.1 | — (Depends R ≥ 4.1.0) |

**Missing dependencies with no fallback:** none — all present this session.
**Missing dependencies with fallback:** For end users who install `EventStudy` without `httr2`/`jsonlite`, the guard emits a clear install message (mirroring `report.R`); the offline Phase 5 layer and `CustomProvider` still work.

## Security Domain

> `security_enforcement` treated as enabled (no config flag disabling it). This phase handles API keys — security is central.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Bearer token / `x-api-key` via httr2 auth helpers; keys never at construction, resolved at call time |
| V3 Session Management | no | Stateless single-shot HTTP; no sessions |
| V4 Access Control | no | No multi-user access control surface in-package |
| V5 Input Validation | yes | `match.arg` for provider type; `stopifnot` on custom fn; body built via `req_body_json` (no string interpolation of prompt into JSON) |
| V6 Cryptography | yes (transport) | TLS via httr2/curl (HTTPS endpoints); never hand-roll — httr2 enforces cert validation |
| V7 Error Handling & Logging | yes | **Key redaction on every error/print path** (PROV-06); one warning, NA return, no secret in any condition/snapshot |

### Known Threat Patterns for R package + LLM HTTP

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key leak in error message / print / test snapshot | Information Disclosure | `req_auth_bearer_token()` + `req_headers_redacted()`; mandatory redaction test asserting dummy key absent |
| Key committed in fixture/.Renviron | Information Disclosure | Keys env-only, never in fixtures; tests use `withr::local_envvar` dummy values; `.Renviron` gitignored |
| Prompt injected into JSON body via string concat | Tampering/Injection | Build body as an R list → `req_body_json()` (jsonlite escapes); never `paste0` the prompt into a JSON string |
| Uncaught condition crashes R session on hostile/malformed response | Denial of Service | `req_error(is_error = ~FALSE)` + `tryCatch` on perform and parse; degrade to one warning + NA |
| MITM / cert bypass | Tampering | httr2/curl default TLS cert validation; do not disable `ssl_verifypeer` |

## Sources

### Primary (HIGH confidence)
- **Installed `httr2` 1.2.3 runtime** — live-verified this session: `with_mocked_responses`, `local_mocked_responses`, `response`, `response_json` present; `req_retry` signature; `req_auth_bearer_token` redacts `Authorization`; `req_headers("x-api-key")` LEAKS vs `req_headers_redacted("x-api-key")` REDACTS; 4xx → `httr2_http_401`; `req_error(is_error=~FALSE)` converts; malformed JSON traps in `resp_body_json`; `httr2_failure` timeout simulation.
- **`R/advise_offline.R:221-230`** — `es_advice` structure the provider return aligns to (`source`, `is_deterministic`, `rules_matched`, `diagnostics_ref`; `class = "es_advice"`).
- **`R/contract.R:74-97`** — `.handle_degenerate()` strict/lenient discipline (one `warning(msg, call. = FALSE)`, sets state) — the failure-handling template.
- **`R/report.R:35-42`** — canonical `requireNamespace(..., quietly = TRUE)` guard idiom.
- **`DESCRIPTION:45-64`** — current Suggests block; `httr2`/`jsonlite` to be added here.

### Secondary (MEDIUM confidence)
- **claude-api skill reference (`curl/examples.md`)** — Anthropic `POST /v1/messages`, `x-api-key`, `anthropic-version: 2023-06-01`, `max_tokens` required, `.content[0].text` extraction; tool-use `input_schema` for structured output.

### Tertiary (LOW confidence)
- OpenAI `chat/completions` `response_format`/json_schema exact sub-shape — from training knowledge, not re-verified live; `.choices[0].message.content` extraction path is stable/long-standing.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — both packages present and verified this session; hand-rolled-httr2 fork is a locked user decision.
- Architecture: HIGH — all httr2 mechanisms (mocking, redaction, error-branching, parse-trapping, timeout) live-verified; R6 idiom matches existing `ModelBase`/`TestStatisticBase`.
- Pitfalls: HIGH — the redaction, error-branch, and malformed-body pitfalls were each reproduced live against httr2 1.2.3.
- Wire formats: MEDIUM — Anthropic shape cited from claude-api reference; OpenAI shape from stable training knowledge (extraction path stable, `response_format` sub-shape assumed).

**Research date:** 2026-09-03
**Valid until:** 2026-10-03 (30 days — httr2 API is stable; wire formats stable; re-check only if httr2 major version bumps).
