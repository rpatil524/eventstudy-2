---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 02
type: execute
wave: 2
depends_on: ["06-01"]
files_modified:
  - R/provider.R
  - tests/testthat/helper-provider.R
  - tests/testthat/test_provider_openai.R
  - NAMESPACE
autonomous: true
requirements: [PROV-03, PROV-07, PROV-08, CRAN-02, CRAN-03]
estimate:
  tokens: 75000
  raw_tokens: 40000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "OpenAICompatProvider issues POST {base_url}/chat/completions with an OpenAI-shaped body, resolves the key at call time, redacts Authorization via req_auth_bearer_token, and extracts completion text from parsed$choices[[1]]$message$content — returning an es_provider_response of the same shape 06-1 defined [PROV-03]"
    - "Any base_url works, so Ollama (http://localhost:11434/v1) and LM Studio (http://localhost:1234/v1) are covered by the same class via base_url override — proven by a doc @example (non-live) and a mocked test using a localhost base_url [PROV-03]"
    - "Every failure path — transport/timeout, 4xx, 5xx, malformed 200 body, missing completion text — degrades to EXACTLY ONE warning + es_provider_response with text=NA_character_, never an uncaught error, driven entirely by offline httr2 mocks with no network and no key [PROV-07, CRAN-03]"
    - "httr2/jsonlite are referenced ONLY inside requireNamespace(..., quietly=TRUE)-guarded branches so R CMD check is clean with them UNINSTALLED [PROV-08, CRAN-02]"
  artifacts:
    - "R/provider.R — OpenAICompatProvider R6 + shared @noRd .perform_request()/.finish_response() HTTP helpers reused by 06-3"
    - "tests/testthat/helper-provider.R — mock_200/mock_status/mock_malformed/mock_timeout response builders (added here, reused by 06-3)"
    - "tests/testthat/test_provider_openai.R — 200 happy path + 4xx/5xx/malformed/timeout/no-key degrade paths, all offline"
  key_links:
    - ".perform_request() sets req_error(is_error = ~FALSE) so non-2xx returns an inspectable response instead of throwing — .finish_response branches on resp_status() [VERIFIED: httr2 1.2.3]"
    - "resp_body_json() is wrapped in tryCatch(...) -> NULL so a malformed 200 body degrades to .provider_failure instead of crashing (Pitfall 3) [VERIFIED: httr2 1.2.3]"
    - "requireNamespace('httr2') guard at the top of OpenAICompatProvider$complete() (report.R idiom) so a user without httr2 gets a clear install message, not a crash, and R CMD check stays clean uninstalled"
---

<objective>
Expand the proven seam to the first HTTP provider: `OpenAICompatProvider`, covering OpenAI and every OpenAI-compatible endpoint (Ollama, LM Studio, any gateway) via a configurable `base_url` + `model`. Factor the shared `httr2` request/response plumbing (`.perform_request()`, `.finish_response()`) that 06-3's Anthropic provider will reuse. Prove every failure path (transport/timeout, 4xx, 5xx, malformed body, missing text, missing key) degrades to one warning + `NA` using `httr2` offline mocks — no network, no key.

Purpose: This is the horizontal expansion from the 06-1 tracer onto the real transport. It delivers the OpenAI-compatible backend (PROV-03) and the CRAN-safe offline HTTP harness (CRAN-03) that the whole phase is named for, and factors the request/parse helpers so 06-3 is thin.
Output: `OpenAICompatProvider` + `.perform_request()`/`.finish_response()` in `R/provider.R`, mock builders in `tests/testthat/helper-provider.R`, `tests/testthat/test_provider_openai.R`, regenerated NAMESPACE. DESCRIPTION is NOT touched (httr2/jsonlite were added in 06-1).
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/06-provider-abstraction-+-cran-safe-http-harness/06-CONTEXT.md
@.planning/phases/06-provider-abstraction-+-cran-safe-http-harness/06-RESEARCH.md
@./.claude/CLAUDE.md
@R/provider.R
@R/report.R
</context>

<artifacts_this_phase_produces>
This plan (06-2) produces:
- `.perform_request(base_url, path, body, key, auth = c("bearer","x-api-key"), extra_headers = list(), timeout = 30, max_tries = 2)` — `@noRd` shared httr2 pipeline builder (guarded by requireNamespace inside the calling `complete()`); returns either an httr2 response OR a condition object (transport/timeout). Auth branch: `req_auth_bearer_token()` for bearer, `req_headers_redacted()` for x-api-key (used by 06-3).
- `.finish_response(resp, extract_fn, source_label)` — `@noRd` shared status-branch + safe body extraction; condition -> failure, non-2xx -> failure, malformed body (tryCatch NULL) -> failure, empty text -> failure, else `.provider_success`.
- `OpenAICompatProvider` — R6 (inherit = ProviderBase): `initialize(model, base_url = "https://api.openai.com/v1")`; `complete(prompt, schema = NULL, ...)` that requireNamespace-guards httr2, resolves the key at call time via `.resolve_api_key("openai")` (fail with `.provider_failure` if NA), builds the OpenAI body (optionally `response_format` json_schema when `schema` supplied), calls `.perform_request(..., auth = "bearer")`, and finishes via `.finish_response()` with `extract_fn = \(p) p$choices[[1]]$message$content`.
- Mock builders in `tests/testthat/helper-provider.R` (reused by 06-3).
- New test file `tests/testthat/test_provider_openai.R`.

06-3 (Anthropic) reuses `.perform_request()`/`.finish_response()` and the mock builders unchanged.
</artifacts_this_phase_produces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Shared httr2 request/response helpers (.perform_request + .finish_response) with the never-throw discipline</name>
  <files>R/provider.R, tests/testthat/helper-provider.R, tests/testthat/test_provider_openai.R</files>
  <read_first>
    - 06-RESEARCH.md "Pattern 1: httr2 request lifecycle (thin client)" (the exact .perform_request pipeline: request |> req_url_path_append |> req_body_json |> req_timeout |> req_retry(retry_on_failure=FALSE) |> req_error(is_error = ~FALSE); auth branch; tryCatch(req_perform, error=identity)) [VERIFIED signature]
    - 06-RESEARCH.md "Pattern 2: Status-branch + safe body extraction" (the exact .finish_response: condition->fail, resp_status branch, tryCatch(resp_body_json)->NULL->fail, empty text->fail, else success)
    - 06-RESEARCH.md "Offline mocking recipes" (mock_200/mock_status/mock_malformed/mock_timeout builders; response_json/response/charToRaw; httr2_failure structure)
    - 06-RESEARCH.md "Common Pitfalls" 2/3/4 (4xx auto-throws without req_error; malformed 200 crashes resp_body_json; local_mocked_responses vs with_mocked_responses scope)
    - R/report.R:35-42 (requireNamespace guard idiom the callers use)
    - R/provider.R (.provider_success/.provider_failure from 06-1 — the helpers return through these)
  </read_first>
  <behavior>
    - Test: .finish_response(<a condition object>, extract_fn, "openai") returns an es_provider_response with is.na(text) and error mentioning network/timeout, emitting one warning.
    - Test: .finish_response applied to a mocked non-2xx (401) response returns text NA + one warning; the reason is "HTTP 401" and contains NO response body and NO key.
    - Test: .finish_response on a mocked 200 with a malformed body (charToRaw("{not json")) returns text NA + one warning ("malformed response body") — resp_body_json's error is trapped, not propagated.
    - Test: .finish_response on a mocked 200 whose extract_fn yields "" (empty) returns text NA + one warning ("no completion text").
    - Test: .finish_response on a mocked 200 with a well-formed body and a working extract_fn returns .provider_success with the extracted text and error NULL.
  </behavior>
  <action>
    Add mock builders to tests/testthat/helper-provider.R exactly per 06-RESEARCH: mock_200(body) -> function(req) httr2::response_json(status=200L, body=body); mock_status(code) -> function(req) httr2::response(status_code=code); mock_malformed() -> function(req) httr2::response(status_code=200L, body=charToRaw("{not json")); mock_timeout() -> function(req) stop(structure(class=c("httr2_failure","error","condition"), list(message="timed out"))). Add @noRd .perform_request() to R/provider.R per Pattern 1 (match.arg auth; req_url_path_append; req_body_json; req_timeout(30); req_retry(max_tries=2, retry_on_failure=FALSE); req_error(is_error=function(resp) FALSE); bearer -> req_auth_bearer_token, x-api-key -> req_headers_redacted; extra_headers via do.call(req_headers,...); tryCatch(req_perform(req), error=function(e) e)). Add @noRd .finish_response(resp, extract_fn, source_label) per Pattern 2 (inherits(resp,"condition") -> .provider_failure(source_label,"request failed (network/timeout)"); resp_status branch non-2xx -> .provider_failure(source_label, paste0("HTTP ", status)) with NO body/key; tryCatch(resp_body_json,error=NULL) NULL -> .provider_failure "malformed response body"; text <- tryCatch(extract_fn(parsed), error=NA_character_); is.na(text)||!nzchar(text) -> .provider_failure "no completion text in response"; else .provider_success(source_label, text)). Both helpers reference httr2 ONLY inside their bodies (callers guard). Create tests/testthat/test_provider_openai.R and add the five .finish_response behavior tests driving each mock through the helper directly (no provider needed yet); wrap each in local_mocked_responses inside test_that where a real response object is needed, or construct responses directly via httr2::response_json/response.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_openai.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. a malformed body crashes instead of degrading, a non-2xx propagates as an error, more than one warning per failure, or a response body/key leaks into the reason string.</fails_when>
  </verify>
  <acceptance_criteria>
    - .perform_request and .finish_response exist as @noRd helpers in R/provider.R; both keep httr2 references inside their bodies only.
    - .finish_response degrades condition/non-2xx/malformed/empty-text to exactly one warning + NA and returns success only on a well-formed body.
    - No response body and no key ever appears in a failure reason string.
    - Mock builders exist in helper-provider.R.
    - testthat::test_file("tests/testthat/test_provider_openai.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="reversible">Additive @noRd helpers + test fixtures; no existing call site changed.</reversibility>
  <done>The shared never-throw request/response helpers are proven against every mocked failure and success path, offline, and committed.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: OpenAICompatProvider end-to-end (happy path + json_schema + any base_url incl Ollama/LM Studio)</name>
  <files>R/provider.R, tests/testthat/test_provider_openai.R, NAMESPACE</files>
  <read_first>
    - 06-RESEARCH.md "OpenAI-compatible request body (structured output via response_format)" (body shape: model + messages=[{role:user,content:prompt}]; response_format=list(type="json_schema", json_schema=list(name=..., schema=schema)) ONLY when schema supplied; base_url overrides for OpenAI/Ollama/LM Studio; path "chat/completions"; extraction $choices[[1]]$message$content) [CITED; response_format sub-shape ASSUMED — keep optional]
    - 06-RESEARCH.md Assumption A3 (local models may not support response_format -> keep it optional so plain-text path still works with a base_url override)
    - R/report.R:35-42 (requireNamespace guard to place at the TOP of complete())
    - R/provider.R (ProviderBase, .resolve_api_key, .perform_request, .finish_response, .provider_failure from 06-1/Task 1)
    - 06-RESEARCH.md "Offline mocking recipes" test-provider-openai example (local_mocked_responses + withr::local_envvar dummy key)
  </read_first>
  <behavior>
    - Test (happy path): with OPENAI_API_KEY set to a dummy via withr, local_mocked_responses(mock_200(list(choices=list(list(message=list(content="hello from model")))))); OpenAICompatProvider$new(model="gpt-4o")$complete("hi") returns is_deterministic=FALSE, source "openai", text "hello from model", error NULL.
    - Test (base_url / local model): OpenAICompatProvider$new(model="llama3", base_url="http://localhost:11434/v1")$complete("hi") under the same mock returns the mocked text — proving Ollama/LM Studio work via base_url override with no code change.
    - Test (schema optional): complete("hi", schema=list(type="object")) still returns the mocked text (response_format is added to the body but the mock ignores it); complete("hi") with no schema also works (plain-text path).
    - Test (no key): with OPENAI_API_KEY unset (withr::local_envvar(OPENAI_API_KEY="")), complete("hi") returns one warning + text NA (missing key surfaces at call time via .provider_failure), never a construction error.
    - Test (4xx): local_mocked_responses(mock_status(401L)); complete("hi") warns once and returns text NA.
  </behavior>
  <action>
    Add OpenAICompatProvider (inherit = ProviderBase) to R/provider.R: initialize(model, base_url = "https://api.openai.com/v1", ...) storing model/base_url (NO key). complete(prompt, schema = NULL, ...): FIRST if (!requireNamespace("httr2", quietly = TRUE)) stop("Package 'httr2' is required for the OpenAI-compatible provider. Install it with: install.packages('httr2')") (report.R idiom); key <- .resolve_api_key("openai"); if (is.na(key)) return(.provider_failure("openai", "no API key (set OPENAI_API_KEY)")); build body <- list(model = self$model, messages = list(list(role="user", content=prompt))); if (!is.null(schema)) body$response_format <- list(type="json_schema", json_schema=list(name="advice", schema=schema)) (kept OPTIONAL per A3); resp <- .perform_request(self$base_url, "chat/completions", body, key, auth="bearer"); return .finish_response(resp, function(p) p$choices[[1]]$message$content, "openai"). @export OpenAICompatProvider. Roxygen @examples: a \dontrun{} block showing OpenAICompatProvider$new(model="gpt-4o")$complete("...") AND a commented note/example of the Ollama base_url override — NEVER a live call. In R/provider.R, remove the 06-1 factory guard for the "openai" branch (exists("OpenAICompatProvider") is now TRUE) so provider("openai", ...) constructs it. Regenerate NAMESPACE (adds export(OpenAICompatProvider)). Extend test_provider_openai.R with the five behavior tests (all offline via local_mocked_responses + withr::local_envvar dummy key).
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_openai.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. missing-key path errors instead of warning+NA, base_url override not honored, response_format made mandatory (breaks plain-text/local path), or the 4xx mock produces an uncaught error.</fails_when>
  </verify>
  <acceptance_criteria>
    - OpenAICompatProvider is exported and posts to {base_url}/chat/completions extracting $choices[[1]]$message$content.
    - Any base_url works (localhost Ollama/LM Studio test passes) with no code change.
    - schema adds response_format optionally; omitting schema uses the plain-text path.
    - Missing key -> one warning + NA at call time, never a construction error.
    - provider("openai", ...) factory branch now constructs the class (06-1 guard removed).
    - testthat::test_file("tests/testthat/test_provider_openai.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="reversible">New additive export; no existing behavior touched.</reversibility>
  <done>OpenAICompatProvider works end-to-end against mocks for OpenAI and localhost base_urls, key resolves at call time, structured output is optional, and tests are green.</done>
</task>

<task type="auto">
  <name>Task 3: Full failure-matrix coverage + CRAN-absent guard verification for the OpenAI provider</name>
  <files>tests/testthat/test_provider_openai.R, R/provider.R</files>
  <read_first>
    - 06-RESEARCH.md "Offline mocking recipes" and "Common Pitfalls" 2/3/4 (the 5xx / malformed / timeout scenarios to cover through the full provider, not just the helper)
    - 06-RESEARCH.md "Pitfall 5: requireNamespace guard missing" (how to prove R CMD check clean with httr2 uninstalled)
    - R/provider.R (OpenAICompatProvider$complete guard + helpers)
  </read_first>
  <behavior>
    - Test (5xx): local_mocked_responses(mock_status(503L)); complete("hi") warns once + text NA.
    - Test (malformed 200): local_mocked_responses(mock_malformed()); complete("hi") warns once + text NA ("malformed response body"), no crash.
    - Test (timeout/transport): local_mocked_responses(mock_timeout()); complete("hi") warns once + text NA ("network/timeout"), no crash.
    - Test (exactly one warning per failure): each failure scenario emits precisely one warning (no double-warn from helper + complete) — assert via testthat::expect_warning with a single match or by counting captured warnings.
    - Test (serializable): the es_provider_response from both a success and a failure is a plain list of scalars; skip_if_not_installed("jsonlite") then jsonlite::toJSON(res, null="null") does not error.
  </behavior>
  <action>
    Extend tests/testthat/test_provider_openai.R with the 5xx, malformed-200, and timeout scenarios driven through the FULL OpenAICompatProvider$complete() (not just the helper) via local_mocked_responses, each asserting exactly one warning + text NA + no uncaught error. Add the single-warning-count assertion for at least one failure scenario (guarding the "centralize the warning in .provider_failure" rule from 06-RESEARCH anti-patterns). Add the jsonlite-guarded serializability test on both a success and a failure es_provider_response. Fix any genuine bug these surface in R/provider.R only (e.g. a double warning, or a leaked body in a reason). Then run the deps-absent verification: confirm httr2/jsonlite are referenced only inside requireNamespace-guarded code — the failing signal for CRAN-02 would be R CMD check reporting a Suggests-used-unconditionally NOTE.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_openai.R")' && Rscript -e 'devtools::test()'</automated>
    <fails_when>testthat reports FAIL > 0 on the OpenAI file, the full devtools::test() shows any regression in the existing 1657-pass suite, or Rscript exits non-zero — e.g. a failure scenario double-warns, an es_provider_response is not JSON-serializable, or a timeout mock crashes.</fails_when>
  </verify>
  <acceptance_criteria>
    - 5xx, malformed-200, and timeout each degrade to exactly one warning + text NA through the full provider, never crashing.
    - Each failure emits precisely one warning (no double-warn).
    - es_provider_response (success and failure) is JSON-serializable under a jsonlite skip guard.
    - httr2/jsonlite are referenced only inside requireNamespace-guarded branches (no unconditional Suggests use).
    - devtools::test() shows the existing 1657 tests still green plus the OpenAI tests.
  </acceptance_criteria>
  <reversibility rating="reversible">Test-only expansion plus any bug fix in the new provider code; no existing pipeline touched.</reversibility>
  <done>The OpenAI provider's full offline failure matrix passes, every failure warns exactly once, responses serialize, guards keep R CMD check clean, and the existing suite stays green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| EventStudy -> OpenAI-compatible HTTP endpoint | Untrusted network response (status, headers, body) crosses back into the session; every field is treated as untrusted and trapped. |
| OPENAI_API_KEY -> request Authorization header | Secret read at call time, attached via req_auth_bearer_token which auto-redacts Authorization in all print/error paths. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-06-05 | Information Disclosure | OPENAI_API_KEY in error/print | high | mitigate | req_auth_bearer_token() marks Authorization redacted at the request-object level [VERIFIED: httr2 1.2.3]; failure reasons carry only "HTTP <status>"/"network/timeout"/"malformed body" — never the key or response body. The cross-provider redaction assertion lands in 06-3. |
| T-06-06 | Denial of Service | hostile/malformed HTTP response | high | mitigate | req_error(is_error=~FALSE) + tryCatch on req_perform AND resp_body_json degrade every non-2xx/transport/parse failure to one warning + NA (PROV-07); timeout via req_timeout(30) and no transport retry (retry_on_failure=FALSE) so a hanging endpoint fails fast. |
| T-06-07 | Tampering | prompt injected into JSON body | medium | mitigate | Body built as an R list -> req_body_json (jsonlite escapes); the prompt is never paste0'd into a JSON string (V5 input validation). |
| T-06-08 | Tampering | MITM / cert bypass | high | accept | httr2/curl default TLS cert validation is used; ssl_verifypeer is never disabled. Standard transport security accepted as httr2's default. |
| T-06-09 | Tampering | new package deps httr2/jsonlite used unconditionally | high | mitigate | All httr2/jsonlite references sit inside requireNamespace-guarded branches (report.R idiom); R CMD check clean with them uninstalled is asserted (CRAN-02, PROV-08). |

This plan opens the OpenAI-compatible HTTP surface; all response fields are treated as untrusted and trapped to one warning + NA, keys are redacted by httr2, and Suggests deps stay guarded. The mandatory key-leak assertion test is completed in 06-3 (which introduces the x-api-key redaction requiring the explicit req_headers_redacted fix).
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_openai.R")'` → 0 failures.
- Offline guarantee (CRAN-03): the entire OpenAI suite runs via httr2 mocks with no network and a dummy key; no skip_on_cran needed for the mocked paths.
- Deps-absent gate (CRAN-02/PROV-08): httr2/jsonlite referenced only inside requireNamespace-guarded branches; R CMD check with httr2 removed reports no Suggests-used-unconditionally NOTE.
- Phase gate: `Rscript -e 'devtools::test()'` → existing 1657 tests still green (full check deferred to 06-3 phase gate).
</verification>

<success_criteria>
- OpenAICompatProvider posts to {base_url}/chat/completions and extracts $choices[[1]]$message$content [PROV-03].
- Any base_url (Ollama/LM Studio localhost) works via override with no code change [PROV-03].
- Every failure path degrades to one warning + NA offline via httr2 mocks, no network, no key [PROV-07, CRAN-03].
- httr2/jsonlite guarded, R CMD check clean with them uninstalled [PROV-08, CRAN-02].
</success_criteria>

<output>
Create `.planning/phases/06-provider-abstraction-+-cran-safe-http-harness/06-02-SUMMARY.md` when done.
</output>
