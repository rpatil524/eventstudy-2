---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 03
type: execute
wave: 3
depends_on: ["06-01", "06-02"]
files_modified:
  - R/provider.R
  - tests/testthat/helper-provider.R
  - tests/testthat/test_provider_anthropic.R
  - tests/testthat/test_provider_redaction.R
  - NAMESPACE
autonomous: true
requirements: [PROV-02, PROV-06, PROV-07, PROV-08, CRAN-02, CRAN-03]
estimate:
  tokens: 75000
  raw_tokens: 40000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "AnthropicProvider issues POST /v1/messages with the x-api-key + anthropic-version headers and max_tokens, implements the tool-use input_schema structured-output path WITH a plain text-block fallback (parsed$content[[1]]$text), and returns an es_provider_response of the shape 06-1 defined [PROV-02]"
    - "The Anthropic x-api-key header is set via req_headers_redacted('x-api-key' = key) (NOT plain req_headers) so the key is redacted from every request/error/print path — a mandatory test forces an error with a dummy key and asserts the key string is ABSENT from the condition message and any captured output [PROV-06]"
    - "Every Anthropic failure path (transport/timeout, 4xx, 5xx, malformed body, missing text, missing key) degrades to exactly ONE warning + text=NA offline via httr2 mocks, no network, no key [PROV-07, CRAN-03]"
    - "The provider() factory resolves and constructs all three types (custom/openai/anthropic) with no leftover placeholder guards; roxygen @examples never make a live call [PROV-08]"
    - "R CMD check is clean (no new NOTEs/WARNINGs) with httr2/jsonlite UNINSTALLED, and the existing 1657-pass suite stays green with valid-input behavior byte-identical [CRAN-02, PROV-08]"
  artifacts:
    - "R/provider.R — AnthropicProvider R6 (tool-use structured + text fallback), finalized provider() factory (all three branches)"
    - "tests/testthat/test_provider_anthropic.R — 200 tool-use + 200 text-fallback + full failure matrix, all offline"
    - "tests/testthat/test_provider_redaction.R — MANDATORY dummy-key-absent assertion (PROV-06)"
  key_links:
    - "x-api-key MUST use req_headers_redacted; plain req_headers('x-api-key'=key) LEAKS the key in print/error [VERIFIED: httr2 1.2.3] — .perform_request(auth='x-api-key') already does this in 06-2; the redaction test proves it end-to-end"
    - "structured output extraction: prefer the tool_use block's input (parsed$content[[i]]$input where type=='tool_use'); fall back to the first text block (parsed$content[[1]]$text) so the provider never crashes when the model returns text instead of a tool call [PROV-02, never-crash]"
    - "anthropic-version: 2023-06-01 + max_tokens (REQUIRED by the Anthropic API) go in the body/headers [CITED: claude-api reference]"
---

<objective>
Complete the seam with the native `AnthropicProvider` (`POST /v1/messages`, tool-use `input_schema` structured output with a plain-text fallback), land the MANDATORY key-redaction test proving the `x-api-key` never leaks, finalize the `provider()` factory across all three backends, and run the phase gate: full offline suite green, existing 1657 tests byte-identical, and `R CMD check` clean with `httr2`/`jsonlite` uninstalled.

Purpose: This closes Phase 6 — the third backend plus the phase's most security-critical guarantee (the Anthropic `x-api-key` redaction that `req_auth_bearer_token` does NOT provide) plus the CRAN-clean gate. It reuses the `.perform_request()`/`.finish_response()` helpers and mock builders from 06-2, so the Anthropic provider is thin.
Output: `AnthropicProvider` + finalized `provider()` factory in `R/provider.R`, `tests/testthat/test_provider_anthropic.R`, `tests/testthat/test_provider_redaction.R`, mock extensions in `tests/testthat/helper-provider.R`, regenerated NAMESPACE. DESCRIPTION is NOT touched (deps were added in 06-1).
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
This plan (06-3) produces:
- `AnthropicProvider` — R6 (inherit = ProviderBase): `initialize(model, base_url = "https://api.anthropic.com", max_tokens = 1024L)`; `complete(prompt, schema = NULL, ...)` that requireNamespace-guards httr2, resolves the key at call time via `.resolve_api_key("anthropic")` (fail with `.provider_failure` if NA), builds the Anthropic messages body (with a `tools` + `tool_choice` `input_schema` block when `schema` supplied, plain messages otherwise), calls the shared `.perform_request(..., auth = "x-api-key", extra_headers = list("anthropic-version" = "2023-06-01"))`, and finishes via `.finish_response()` with an `extract_fn` that prefers the `tool_use` block's `input` and falls back to the first `text` block.
- Finalized `provider()` factory: all three branches (`custom`/`openai`/`anthropic`) live; the 06-1 "delivered in a later plan" guard for anthropic is removed.
- MANDATORY redaction test in `tests/testthat/test_provider_redaction.R` (PROV-06): a dummy key + forced error, asserting the key string is absent from the emitted condition message and any `capture.output(print(<request>))`.
- New test file `tests/testthat/test_provider_anthropic.R`; any extra mock helpers appended to `tests/testthat/helper-provider.R`.

After this plan the seam is complete: three providers, one uniform `es_provider_response` contract, key-safe, never-crash, fully offline-tested — ready for Phase 7's `es_advise()` to wrap.
</artifacts_this_phase_produces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: AnthropicProvider — messages + tool-use input_schema structured output with text fallback</name>
  <files>R/provider.R, tests/testthat/test_provider_anthropic.R, NAMESPACE</files>
  <read_first>
    - 06-RESEARCH.md "Anthropic Messages request body (structured output via tool-use)" (body: model, max_tokens (REQUIRED), messages=[{role:user,content:prompt}]; headers x-api-key REDACTED + anthropic-version 2023-06-01; text extraction parsed$content[[1]]$text) [CITED claude-api reference]
    - 06-RESEARCH.md Open Question 1 + Assumption A4 (implement the tool-use input_schema structured path AND a text fallback — the resolved decision)
    - R/provider.R (.perform_request already supports auth="x-api-key" via req_headers_redacted and extra_headers; .finish_response; .resolve_api_key; .provider_failure — all from 06-1/06-2)
    - R/report.R:35-42 (requireNamespace guard at top of complete())
    - tests/testthat/helper-provider.R (mock_200/mock_status/mock_malformed/mock_timeout from 06-2)
  </read_first>
  <behavior>
    - Test (text path, no schema): with ANTHROPIC_API_KEY dummy via withr, local_mocked_responses(mock_200(list(content=list(list(type="text", text="anthropic says hi"))))); AnthropicProvider$new(model="claude-opus-4-8")$complete("hi") returns source "anthropic", is_deterministic=FALSE, text "anthropic says hi", error NULL.
    - Test (tool-use structured path): local_mocked_responses(mock_200(list(content=list(list(type="tool_use", input=list(advice="use Kolari-Pynnonen")))))); complete("hi", schema=list(type="object", properties=list(advice=list(type="string")))) returns text that carries the structured advice (extract_fn prefers the tool_use input; serialize/flatten to character as the es_provider_response$text) — never crashes.
    - Test (fallback when model returns text despite schema): schema supplied but the mocked response is a plain text block -> complete() still returns the text-block content (fallback), one path, no crash.
    - Test (no key): ANTHROPIC_API_KEY unset -> complete("hi") one warning + text NA at call time, no construction error.
    - Test (4xx): local_mocked_responses(mock_status(401L)) -> one warning + text NA.
  </behavior>
  <action>
    Add AnthropicProvider (inherit = ProviderBase) to R/provider.R: initialize(model, base_url = "https://api.anthropic.com", max_tokens = 1024L, ...) storing model/base_url/max_tokens (NO key). complete(prompt, schema = NULL, ...): FIRST requireNamespace("httr2", quietly=TRUE) guard -> clear stop() (report.R idiom); key <- .resolve_api_key("anthropic"); if (is.na(key)) return(.provider_failure("anthropic", "no API key (set ANTHROPIC_API_KEY)")); build body <- list(model=self$model, max_tokens=self$max_tokens, messages=list(list(role="user", content=prompt))); if (!is.null(schema)) attach a tools definition list(list(name="advice", description=..., input_schema=schema)) plus tool_choice=list(type="tool", name="advice") (the structured path per PROV-02). resp <- .perform_request(self$base_url, "v1/messages", body, key, auth="x-api-key", extra_headers=list("anthropic-version"="2023-06-01")). extract_fn: given parsed, look for the first content block with type=="tool_use" and return a character rendering of its $input (e.g. jsonlite::toJSON guarded, or paste of fields) when present; ELSE return the first block's $text (parsed$content[[1]]$text) — the fallback that keeps it never-crash when the model returns text instead of a tool call. return .finish_response(resp, extract_fn, "anthropic"). @export AnthropicProvider. Roxygen @examples in \dontrun{} only (never a live call). Regenerate NAMESPACE (adds export(AnthropicProvider)). Create tests/testthat/test_provider_anthropic.R with the five behavior tests, all offline via local_mocked_responses + withr::local_envvar dummy key.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_anthropic.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. tool_use extraction crashes, the text fallback is missing (schema present + text response errors), missing-key path errors instead of warning+NA, or the 401 mock produces an uncaught error.</fails_when>
  </verify>
  <acceptance_criteria>
    - AnthropicProvider is exported and posts to /v1/messages with anthropic-version + max_tokens.
    - The tool-use input_schema structured path works AND falls back to the first text block, never crashing.
    - Missing key -> one warning + NA at call time, never a construction error.
    - testthat::test_file("tests/testthat/test_provider_anthropic.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="reversible">New additive export reusing existing helpers; no existing behavior touched.</reversibility>
  <done>AnthropicProvider works end-to-end against mocks for both the tool-use structured path and the text fallback, key resolves at call time, and tests are green.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: MANDATORY key-redaction test — dummy key never appears in any condition or captured output (PROV-06)</name>
  <files>tests/testthat/test_provider_redaction.R, tests/testthat/helper-provider.R, R/provider.R</files>
  <read_first>
    - 06-RESEARCH.md "Pitfall 1: x-api-key leaks despite req_auth_bearer_token habits" and "test-provider-redaction.R (MANDATORY — PROV-06)" (the exact test: force an error with a dummy key, assert grepl(key, msg) is FALSE) [VERIFIED: req_headers('x-api-key') LEAKS vs req_headers_redacted REDACTS]
    - 06-RESEARCH.md Security Domain "API key leak in error message / print / test snapshot" (Information Disclosure mitigation)
    - R/provider.R (.perform_request auth="x-api-key" branch uses req_headers_redacted — the code under test; AnthropicProvider from Task 1)
  </read_first>
  <behavior>
    - Test (Anthropic condition): with ANTHROPIC_API_KEY="sk-SECRET-DUMMY-abc123" via withr, local_mocked_responses(mock_status(401L)); msg <- tryCatch(AnthropicProvider$new(model="claude-opus-4-8")$complete("hi"), warning=function(w) conditionMessage(w)); expect_false(grepl("sk-SECRET-DUMMY-abc123", msg, fixed=TRUE)) — the dummy key is absent from the emitted warning.
    - Test (request print, Anthropic): build the x-api-key request via .perform_request(auth="x-api-key", key="sk-SECRET-DUMMY-abc123") (or the provider's request builder) and assert the key string is absent from capture.output(print(req)) — proving req_headers_redacted redacts it. [VERIFIED plain req_headers would FAIL this.]
    - Test (OpenAI condition): with OPENAI_API_KEY dummy, mock_status(401L); assert the dummy key is absent from the emitted warning (req_auth_bearer_token redacts Authorization).
    - Test (no body/key in reason): for a mocked non-2xx, the es_provider_response$error string contains neither the key nor any response body — only "HTTP <status>".
  </behavior>
  <action>
    Create tests/testthat/test_provider_redaction.R. Add the four behavior assertions above, using withr::local_envvar to set dummy keys and local_mocked_responses for the 401. The Anthropic request-print assertion is the linchpin (PROV-06): construct the request the provider would send with a dummy x-api-key and assert grepl(key, capture.output(print(req)), fixed=TRUE) is entirely FALSE — this is the test that fails if anyone regresses req_headers_redacted back to plain req_headers. Add any small helper (e.g. a dummy-key constant) to helper-provider.R. If the assertion reveals a real leak, fix R/provider.R (must be req_headers_redacted for x-api-key) — do NOT weaken the test. Do not modify provider logic except to close a genuine leak.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_redaction.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — specifically if the dummy key appears in any warning message, in capture.output(print(req)), or in an es_provider_response$error string (a real key leak), or if any redaction path emits an uncaught error.</fails_when>
  </verify>
  <acceptance_criteria>
    - A dummy Anthropic key is provably absent from the emitted warning AND from capture.output(print(<request>)) (req_headers_redacted verified).
    - A dummy OpenAI key is provably absent from the emitted warning (req_auth_bearer_token verified).
    - No failure reason string carries the key or a response body.
    - testthat::test_file("tests/testthat/test_provider_redaction.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="one-way">The redaction guarantee is the phase's core security contract; the test locks req_headers_redacted permanently. A regression to plain req_headers must fail CI.</reversibility>
  <done>The mandatory key-redaction test proves neither the Anthropic x-api-key nor the OpenAI bearer key leaks into any condition, print, or error output, and is green.</done>
</task>

<task type="auto">
  <name>Task 3: Finalize provider() factory (all three branches) + phase gate (full suite green + R CMD check clean, deps uninstalled)</name>
  <files>R/provider.R, tests/testthat/test_provider_anthropic.R, NAMESPACE</files>
  <read_first>
    - R/provider.R (the provider() factory from 06-1 with the "delivered in a later plan" guard for anthropic still present after 06-2 removed the openai guard)
    - 06-RESEARCH.md Open Question 3 (export the three R6 generators AND the provider() factory) + Pitfall 5 (requireNamespace guard idiom for the R CMD check clean gate)
    - 06-RESEARCH.md Security Domain (final confirmation no key/body leaks anywhere)
  </read_first>
  <behavior>
    - Test: provider("anthropic", model="claude-opus-4-8") returns an AnthropicProvider; provider("openai", model="gpt-4o") an OpenAICompatProvider; provider("custom", fn=...) a CustomProvider — all three branches live, no placeholder stop().
    - Test: provider() with EVENTSTUDY_ADVISOR_PROVIDER set selects that type; an explicit type arg overrides it (precedence, cross-checking 06-1's resolver through the factory).
    - Test: provider("bogus") errors clearly via match.arg (input validation).
  </behavior>
  <action>
    In R/provider.R, remove the last 06-1 placeholder guard so the provider() factory's "anthropic" branch constructs AnthropicProvider$new(...) directly (all three branches now live). Ensure the factory wires .resolve_provider_config so provider() with no type falls back to the resolved default and honors EVENTSTUDY_ADVISOR_PROVIDER. Regenerate NAMESPACE (confirm exports: ProviderBase, CustomProvider, OpenAICompatProvider, AnthropicProvider, provider, plus any print method). Add the three factory behavior tests to test_provider_anthropic.R (or a small dedicated block). Then run the PHASE GATE: (1) full test suite green with the new provider tests plus the existing 1657 tests byte-identical (CRAN-05-equivalent); (2) R CMD check clean with NO new NOTEs/WARNINGs; (3) prove CRAN-cleanliness with the Suggests deps effectively uninstalled — every httr2/jsonlite reference is inside a requireNamespace-guarded branch, so a check run without them must not report a Suggests-used-unconditionally NOTE. If the check surfaces any new NOTE/WARNING, fix it in R/provider.R / roxygen (e.g. an undocumented argument, an unguarded reference, a live @example) before closing.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_anthropic.R")' && Rscript -e 'devtools::test()' && Rscript -e 'devtools::check(document = TRUE, args = c("--no-manual"))'</automated>
    <fails_when>testthat reports FAIL > 0, devtools::test() shows any regression in the existing 1657 tests, devtools::check() reports any NEW NOTE or WARNING (including a Suggests-used-unconditionally NOTE, an undocumented arg, or a live example), or Rscript exits non-zero.</fails_when>
  </verify>
  <acceptance_criteria>
    - provider() constructs all three backend types; no placeholder "later plan" stop() remains.
    - NAMESPACE exports ProviderBase, CustomProvider, OpenAICompatProvider, AnthropicProvider, and provider.
    - devtools::test() shows the existing 1657 tests still passing plus all Phase 6 provider tests green.
    - devtools::check() reports no new NOTEs/WARNINGs; httr2/jsonlite referenced only inside requireNamespace guards (CRAN-02, PROV-08).
    - All @examples across the provider layer are non-live (\dontrun{}/if(interactive())); the custom example is the only inline one.
  </acceptance_criteria>
  <reversibility rating="reversible">Factory finalization + gate verification; no existing pipeline behavior altered (valid-input paths byte-identical).</reversibility>
  <done>The provider() factory serves all three backends, the full suite (existing + new) is green, R CMD check is clean with Suggests deps uninstalled, and Phase 6 closes with the seam complete and key-safe.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| EventStudy -> Anthropic /v1/messages endpoint | Untrusted network response crosses back into the session; every field trapped to one warning + NA. |
| ANTHROPIC_API_KEY -> x-api-key header | Secret read at call time, attached via req_headers_redacted so it is redacted from EVERY request/error/print path (req_auth_bearer_token does NOT cover x-api-key). |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-06-10 | Information Disclosure | ANTHROPIC_API_KEY (x-api-key) leak | critical | mitigate | x-api-key set via req_headers_redacted (NOT plain req_headers) [VERIFIED: httr2 1.2.3 — plain header LEAKS]; the MANDATORY test (Task 2) forces an error with a dummy key and asserts it is absent from the warning AND capture.output(print(req)). This is the phase's core security guarantee. |
| T-06-11 | Denial of Service | hostile/malformed Anthropic response | high | mitigate | Reuses .perform_request/.finish_response (req_error ~FALSE + tryCatch on perform and parse); every non-2xx/transport/parse/empty-text failure degrades to one warning + NA (PROV-07). tool_use extraction is tryCatch-guarded with a text fallback so an unexpected content shape never crashes. |
| T-06-12 | Tampering | prompt injected into JSON body | medium | mitigate | Body built as an R list -> req_body_json (jsonlite escapes); prompt never string-concatenated into JSON. |
| T-06-13 | Tampering | new package deps used unconditionally | high | mitigate | All httr2/jsonlite references inside requireNamespace-guarded branches; the phase-gate R CMD check (Task 3) asserts no Suggests-used-unconditionally NOTE with them uninstalled (CRAN-02, PROV-08). Both are canonical Posit CRAN packages (06-RESEARCH audit: Approved). |
| T-06-14 | Tampering | MITM / cert bypass | high | accept | httr2/curl default TLS cert validation; ssl_verifypeer never disabled. |

This plan lands the phase's critical security control — the Anthropic x-api-key redaction that httr2's bearer helper does NOT provide — locked by a mandatory test. All package-legitimacy checks pass (Posit CRAN packages, Suggests-guarded); the phase-gate check proves R CMD check stays clean with the deps uninstalled.
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_anthropic.R")'` and `.../test_provider_redaction.R` → 0 failures.
- Offline guarantee (CRAN-03): the entire Anthropic + redaction suite runs via httr2 mocks with a dummy key, no network; no skip_on_cran needed for mocked paths.
- Phase gate (all Phase 6 requirements): `Rscript -e 'devtools::test()'` → existing 1657 tests still green (valid-input behavior byte-identical); `Rscript -e 'devtools::check(document = TRUE, args = c("--no-manual"))'` → no new NOTEs/WARNINGs; httr2/jsonlite referenced only inside requireNamespace guards (CRAN-02, PROV-08).
- `git diff DESCRIPTION` shows only the 06-1 Suggests addition (httr2/jsonlite); no other DESCRIPTION change in 06-3.
</verification>

<success_criteria>
- AnthropicProvider posts to /v1/messages with tool-use input_schema structured output + text fallback [PROV-02].
- x-api-key redacted via req_headers_redacted; the mandatory dummy-key-absent test passes [PROV-06].
- Every failure path degrades to one warning + NA offline [PROV-07, CRAN-03].
- provider() serves all three backends; examples never live [PROV-08].
- R CMD check clean with httr2/jsonlite uninstalled; existing 1657 tests byte-identical [CRAN-02, PROV-08].
</success_criteria>

<output>
Create `.planning/phases/06-provider-abstraction-+-cran-safe-http-harness/06-03-SUMMARY.md` when done.
</output>
