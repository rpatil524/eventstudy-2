---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 02
subsystem: advisor-provider
tags: [provider, httr2, openai, ollama, cran-safe, offline-mocks, r6]
requires: ["06-1: ProviderBase, .provider_success/.provider_failure, .resolve_api_key, provider() factory"]
provides:
  - ".perform_request() / .finish_response() shared httr2 plumbing (reused unchanged by 06-3)"
  - "OpenAICompatProvider (OpenAI + any OpenAI-compatible endpoint via base_url)"
  - "mock_200/mock_status/mock_malformed/mock_timeout offline builders (reused by 06-3)"
affects: ["06-3 AnthropicProvider (reuses helpers + mocks)", "Phase 7 es_advise() online path"]
tech-stack:
  added: []
  patterns: ["httr2 thin-client never-throw pipeline", "requireNamespace-guarded Suggests use", "offline httr2 mocked responses"]
key-files:
  created:
    - tests/testthat/test_provider_openai.R
    - man/OpenAICompatProvider.Rd
  modified:
    - R/provider.R
    - tests/testthat/helper-provider.R
    - tests/testthat/test_provider_resolution.R
    - NAMESPACE
decisions:
  - "Empty-string OPENAI_API_KEY treated identically to unset (NA) -> 'no API key' at call time (Rule 1 fix)"
  - "es_provider_response serialized in tests via unclass() -> plain JSON object (the shape Phase 7 emits); jsonlite has no asJSON method for the S3 class by design"
  - "jsonlite never referenced in R code — httr2's built-in req_body_json/resp_body_json (jsonlite internally) suffice; one fewer unconditional Suggests reference"
metrics:
  duration: 7m
  completed: 2026-09-03
  tasks: 3
  commits: 3
  files: 6
actuals:
  tokens: 6539
  tasks: 3
  commits: 3
status: complete
---

# Phase 6 Plan 2: OpenAICompatProvider + CRAN-Safe HTTP Harness Summary

`OpenAICompatProvider` (OpenAI plus every OpenAI-compatible endpoint — Ollama, LM Studio, any gateway — via a `base_url` override) built on shared never-throw `httr2` helpers (`.perform_request`/`.finish_response`), with every failure path (transport/timeout, 4xx, 5xx, malformed 200 body, missing text, missing key) degrading to exactly one warning + `NA` — proven entirely offline via httr2 mocks with a dummy key, CRAN-safe with httr2/jsonlite guarded.

## What Was Built

- **Task 1 — shared httr2 plumbing (TDD).** Added two `@noRd` helpers to `R/provider.R`:
  - `.perform_request(base_url, path, body, key, auth = c("bearer","x-api-key"), extra_headers = list(), timeout = 30, max_tries = 2)` — builds the request pipeline (`req_url_path_append` → `req_body_json` → `req_timeout(30)` → `req_retry(max_tries=2, retry_on_failure=FALSE)` → `req_error(is_error = ~FALSE)`), attaches auth (`req_auth_bearer_token` for bearer — auto-redacts Authorization; `req_headers_redacted("x-api-key"=...)` for the x-api-key path 06-3 uses), merges `extra_headers` via `do.call(req_headers, ...)`, and wraps `req_perform` in `tryCatch` returning the condition on transport/timeout.
  - `.finish_response(resp, extract_fn, source_label)` — condition → failure; non-2xx → failure carrying ONLY `"HTTP <status>"` (no body, no key); malformed body (`resp_body_json` trapped to `NULL`) → failure; empty/missing text → failure; else `.provider_success`. All failures route through `.provider_failure` (the single warning point).
  - Added `mock_200/mock_status/mock_malformed/mock_timeout` builders to `helper-provider.R`.
- **Task 2 — OpenAICompatProvider (TDD).** Exported R6 (`inherit = ProviderBase`): `initialize(model, base_url = "https://api.openai.com/v1")`; `complete(prompt, schema = NULL, ...)` guards `requireNamespace("httr2")` first, resolves the key at call time (`OPENAI_API_KEY`), builds the OpenAI body, adds `response_format` json_schema ONLY when `schema` supplied (optional so local/plain-text works), and finishes via `.finish_response` extracting `$choices[[1]]$message$content`. Removed the factory's `openai` `exists()` guard so `provider("openai", ...)` constructs the class; the anthropic branch stays guarded for 06-3. Regenerated NAMESPACE + Rd.
- **Task 3 — full failure matrix.** Extended tests with 5xx / malformed-200 / timeout through the FULL provider, an exactly-one-warning count across all four failure modes, and a jsonlite-guarded serializability check on success + failure responses. Verified httr2/jsonlite are referenced only inside guarded code.

## Helper Signatures Added

```r
.perform_request(base_url, path, body, key,
                 auth = c("bearer", "x-api-key"),
                 extra_headers = list(), timeout = 30, max_tries = 2)  # -> httr2 response | condition
.finish_response(resp, extract_fn, source_label)                       # -> es_provider_response
```

## New Exports

- `OpenAICompatProvider` (R6 generator) — `export(OpenAICompatProvider)` in NAMESPACE.

## Test Results

- `tests/testthat/test_provider_openai.R`: **40 PASS / 0 FAIL** (all offline, dummy key via `withr::local_envvar`).
- Full `devtools::test()`: **1735 PASS / 0 FAIL / 31 SKIP / 1 WARN**. Baseline was 1694 pass; +41 net new, zero regressions. The single WARN is a pre-existing one at `test_edge_cases.R:817` (out of scope, present at baseline).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Empty-string API key not treated as missing**
- **Found during:** Task 2 (missing-key test failed)
- **Issue:** `.resolve_api_key("openai")` returns `""` (not `NA`) when `OPENAI_API_KEY` is set to an empty string (as `withr::local_envvar(OPENAI_API_KEY="")` does). The `if (is.na(key))` check let an empty key through to an HTTP request instead of failing fast.
- **Fix:** Changed the guard to `if (is.na(key) || !nzchar(key))` so unset and set-but-empty are handled identically — one warning + NA at call time.
- **Files modified:** R/provider.R
- **Commit:** 26fee94

**2. [Rule 1 - Bug] Stale 06-1 factory test asserted the wrong outcome**
- **Found during:** Task 3 phase gate (`devtools::test()`)
- **Issue:** `test_provider_resolution.R:91` asserted `provider("openai")` throws "later plan" — no longer true now that 06-2 delivers the class.
- **Fix:** Split into two tests: `provider("openai")` constructs `OpenAICompatProvider`; `provider("anthropic")` still errors "later plan".
- **Files modified:** tests/testthat/test_provider_resolution.R
- **Commit:** 268ce1f

### Design note (not a deviation)

`jsonlite::toJSON` has no `asJSON` method for the `es_provider_response` S3 class, so the serializability tests call `jsonlite::toJSON(unclass(res), ...)`. This is the intended shape — the response is a plain list of scalars, and Phase 7 (which owns interpretation) emits it as a plain JSON object. The custom class is a transport marker, not a serialization contract.

## Requirements Satisfied

- **PROV-03** — OpenAICompatProvider posts to `{base_url}/chat/completions`, extracts `$choices[[1]]$message$content`; any base_url (Ollama/LM Studio localhost) works via override with no code change (mocked test + `\dontrun` example).
- **PROV-07 / CRAN-03** — every failure path degrades to one warning + NA, driven entirely by offline httr2 mocks with no network and a dummy key.
- **PROV-08 / CRAN-02** — httr2/jsonlite referenced only inside requireNamespace-guarded code; jsonlite not referenced in R code at all.

## Threat Model Coverage

- **T-06-05 (key disclosure):** OpenAI uses `req_auth_bearer_token()` (auto-redacts Authorization); failure reasons carry only `"HTTP <status>"` / `"network/timeout"` / `"malformed body"` — never key or body. Cross-provider key-leak assertion lands in 06-3 (x-api-key path).
- **T-06-06 (malformed-response DoS):** `req_error(~FALSE)` + `tryCatch` on both `req_perform` and `resp_body_json` — all covered by the 5xx/malformed/timeout tests.
- **T-06-07 (prompt injection):** body built as an R list → `req_body_json` (jsonlite escapes); prompt never string-concatenated into JSON.
- **T-06-09 (unconditional Suggests):** all httr2 references sit inside the guarded helpers/complete().

No new threat surface beyond the plan's `<threat_model>`.

## Self-Check: PASSED

- Files exist: R/provider.R, tests/testthat/helper-provider.R, tests/testthat/test_provider_openai.R, man/OpenAICompatProvider.Rd — all FOUND.
- Commits exist: c71a0fe, 26fee94, 268ce1f — all FOUND.
