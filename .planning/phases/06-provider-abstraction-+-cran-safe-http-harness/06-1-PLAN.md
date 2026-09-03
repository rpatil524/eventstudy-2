---
phase: 06-provider-abstraction-+-cran-safe-http-harness
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/provider.R
  - tests/testthat/helper-provider.R
  - tests/testthat/test_provider_custom.R
  - tests/testthat/test_provider_resolution.R
  - DESCRIPTION
  - NAMESPACE
autonomous: true
requirements: [PROV-01, PROV-04, PROV-05, PROV-07, PROV-08, CRAN-02, CRAN-03]
estimate:
  tokens: 70000
  raw_tokens: 38000
  tasks: 3
  confidence: med
must_haves:
  truths:
    - "An AdvisorProvider/ProviderBase R6 base defines a uniform complete(prompt, schema, ...) contract consistent with the ModelBase/TestStatisticBase idiom, and CustomProvider (a user (prompt, schema) -> list/character hook) implements it end-to-end with zero HTTP [PROV-01, PROV-04]"
    - "Provider/model/base_url resolve by 3-tier precedence explicit arg -> EVENTSTUDY_ADVISOR_PROVIDER/_MODEL/_BASE_URL env -> default, and API keys resolve OPENAI_API_KEY/ANTHROPIC_API_KEY from the environment ONLY at call time (never at construction) [PROV-05]"
    - "A CustomProvider whose user function errors degrades to exactly ONE warning() plus an es_provider_response with text=NA_character_ and never crashes the session — mirroring .handle_degenerate() [PROV-07]"
    - "es_provider_response return type carries fields source, is_deterministic=FALSE, text, error — field names identical to the Phase 5 es_advice shape so Phase 7 slots in trivially [PROV-01]"
    - "httr2/jsonlite are added to Suggests only; the package loads and this whole plan's tests pass with httr2/jsonlite UNINSTALLED (CustomProvider + resolution need no HTTP) and R CMD check stays clean [PROV-08, CRAN-02]"
  artifacts:
    - "R/provider.R — ProviderBase R6, CustomProvider R6, .resolve_provider_config(), .resolve_api_key(), .provider_success(), .provider_failure(), provider() factory (custom branch only in this plan)"
    - "tests/testthat/helper-provider.R — dummy-key + mock-response builder fixtures reused by later plans"
    - "tests/testthat/test_provider_custom.R — CustomProvider happy path + errored-fn degrade path"
    - "tests/testthat/test_provider_resolution.R — arg->env->default precedence + call-time key resolution"
  key_links:
    - ".provider_failure() is the SINGLE point that emits the one warning() and builds the es_provider_response failure — every provider failure path routes through it (never warn twice)"
    - "es_provider_response field names (source, is_deterministic, text, error) must match the Phase 5 es_advice field names (source, is_deterministic) so Phase 7's wrapper is trivial [VERIFIED: R/advise_offline.R:221-229]"
    - "Key resolution happens INSIDE complete(), not initialize() — a missing key surfaces one clear failure at call time, never a construction crash (anti-pattern in 06-RESEARCH.md)"
---

<objective>
Deliver the end-to-end provider seam tracer: an abstract R6 `ProviderBase` defining the uniform `complete(prompt, schema, ...)` contract and the shared `es_provider_response` success/failure plumbing, plus the fully-working `CustomProvider` (an in-process user-function hook that needs NO network), plus the call-time backend/key resolution helpers. This is the thinnest path that proves the whole seam — construct a provider, call `complete()`, get an `es_provider_response` back, and degrade a failing call to one warning + NA — with zero HTTP. The two HTTP providers (06-2 OpenAI-compatible, 06-3 Anthropic) expand out from this proven skeleton.

Purpose: Phase 7's `es_advise()` needs one uniform seam whose return object slots next to the Phase 5 offline `es_advice`. Proving the contract, the failure discipline, the key-safe resolution, and the return shape on `CustomProvider` (no network required) validates the entire architecture before any HTTP code is written.
Output: `R/provider.R`, `tests/testthat/helper-provider.R`, `tests/testthat/test_provider_custom.R`, `tests/testthat/test_provider_resolution.R`, `httr2`/`jsonlite` added to DESCRIPTION Suggests, regenerated NAMESPACE.
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
@R/contract.R
@R/advise_offline.R
</context>

<artifacts_this_phase_produces>
This plan (06-1) produces the seam skeleton that 06-2 and 06-3 build on:
- `ProviderBase` — abstract R6 base (PascalCase, `*Base` idiom like `ModelBase`/`TestStatisticBase`): `initialize()` validation, an abstract `complete(prompt, schema = NULL, ...)` public method that stops "not implemented" on the base, and shared private plumbing the subclasses reuse.
- `CustomProvider` — R6 wrapping a user `function(prompt, schema) -> list|character`; NO `httr2`, NO guard needed; the offline end-to-end test seam and escape hatch (PROV-04).
- `.resolve_provider_config(provider = NULL, model = NULL, base_url = NULL)` — `@noRd` arg->env->default resolver reading `EVENTSTUDY_ADVISOR_PROVIDER`/`_MODEL`/`_BASE_URL` (PROV-05, selectors).
- `.resolve_api_key(provider)` — `@noRd` reads `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` from the environment at CALL time (PROV-05/PROV-06, secrets); returns `NA_character_` when unset (never stops here — the failure surfaces through `.provider_failure`).
- `.provider_success(source_label, text)` / `.provider_failure(source_label, reason)` — `@noRd` builders of the `es_provider_response` S3 object; `.provider_failure` is the single warning-emitting point (PROV-07).
- `provider(type = c("custom","openai","anthropic"), ...)` — exported factory; in THIS plan only the `custom` branch is wired (the two HTTP branches error "delivered in 06-2/06-3" placeholders are NOT added — instead the factory dispatches only implemented types and the HTTP types are added by their own plans).
- New file `R/provider.R`; new test files `tests/testthat/helper-provider.R`, `test_provider_custom.R`, `test_provider_resolution.R`.

The `es_provider_response` field names (`source`, `is_deterministic`, `text`, `error`) are LOCKED by CONTEXT — 06-2/06-3 return the identical shape. Document them in the `@return` roxygen so later plans rely on them.
</artifacts_this_phase_produces>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: End-to-end CustomProvider tracer — user fn through ProviderBase to es_provider_response, one path, zero HTTP</name>
  <files>R/provider.R, tests/testthat/test_provider_custom.R, NAMESPACE</files>
  <read_first>
    - R/models.R:57-63 and R/models.R (ModelBase abstract R6: initialize + abstract method that stops "not implemented" — COPY this base-class idiom for ProviderBase)
    - R/advise_offline.R:221-229 (the es_advice structure(list(source, is_deterministic, ...), class=...) return — the es_provider_response aligns field names source/is_deterministic to this) [VERIFIED]
    - R/contract.R:74-97 (.handle_degenerate: exactly one warning(msg, call. = FALSE) then degrade — the failure-discipline template .provider_failure mirrors)
    - R/simulation.R:125-157 (S3-classed list + print.es_* cat convention, in case a print.es_provider_response is wanted — optional here)
    - 06-RESEARCH.md "CustomProvider seam (offline end-to-end)" and "Pattern 3: es_advice-aligned failure/success shape" (the exact .provider_success/.provider_failure bodies and the CustomProvider R6 skeleton)
    - tests/testthat/helper-mock-data.R (testthat 3e conventions; how helper files are structured)
  </read_first>
  <behavior>
    - Test 1 (RED first): CustomProvider$new(function(prompt, schema) "canned advice")$complete("hi") returns an object where inherits(res, "es_provider_response") is TRUE, res$source == "custom", res$is_deterministic is FALSE, res$text == "canned advice", res$error is NULL.
    - Test 2: A CustomProvider whose fn stop()s ("boom") makes complete("hi") emit EXACTLY ONE warning and return res$text that is NA_character_ with res$error a non-NULL reason string — the call does NOT error (expect_warning wrapping, then expect_true(is.na(res$text))).
    - Test 3: ProviderBase$new()$complete("hi") stops with a clear "not implemented"/abstract message (base contract is abstract).
    - Test 4: The dummy custom fn receives the schema argument (CustomProvider$new(function(prompt, schema) if (is.null(schema)) "noschema" else "hasschema")$complete("hi", schema = list(x=1))$text == "hasschema") — proving the (prompt, schema) seam of PROV-04.
  </behavior>
  <action>
    Create R/provider.R. Write ONE thin end-to-end path FIRST. Define ProviderBase as an abstract R6 class (PascalCase, mirroring ModelBase): public initialize() (stores model/base_url fields, no key read), and public complete(prompt, schema = NULL, ...) that stop("ProviderBase is abstract; use a concrete provider.", call. = FALSE). Define .provider_success(source_label, text) and .provider_failure(source_label, reason) as @noRd helpers building the es_provider_response object exactly per 06-RESEARCH Pattern 3: structure(list(source = source_label, is_deterministic = FALSE, text = <text|NA_character_>, error = <NULL|reason>), class = "es_provider_response"); .provider_failure emits EXACTLY ONE warning(sprintf("Advisor provider '%s' failed: %s. Returning NA.", source_label, reason), call. = FALSE) then returns the failure object (single warning point, mirroring .handle_degenerate). Define CustomProvider (inherit = ProviderBase): initialize(fn) with stopifnot(is.function(fn)); complete(prompt, schema = NULL, ...) that runs out <- tryCatch(private$.fn(prompt, schema, ...), error = function(e) e); if inherits(out, "condition") return .provider_failure("custom", "custom function errored"); else return .provider_success("custom", as.character(out)[[1]]). Roxygen: @export on ProviderBase, CustomProvider; @return on complete() documenting the es_provider_response fields (source, is_deterministic=FALSE, text, error). Regenerate NAMESPACE with roxygen2. Do NOT touch DESCRIPTION in this task (deps added in Task 3). Create tests/testthat/test_provider_custom.R with the four behavior tests.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_custom.R")'</automated>
    <fails_when>testthat reports any FAIL > 0 or Rscript exits non-zero — e.g. es_provider_response not classed, ProviderBase$complete does not stop, a custom-fn error escapes as an uncaught error instead of one warning + NA, or the schema argument does not reach the user fn.</fails_when>
  </verify>
  <acceptance_criteria>
    - R/provider.R defines ProviderBase and CustomProvider R6 classes, both @export.
    - NAMESPACE contains export(ProviderBase) and export(CustomProvider).
    - CustomProvider$new(fn)$complete(prompt, schema) returns an es_provider_response with source="custom", is_deterministic=FALSE.
    - A stop()ing custom fn degrades to exactly one warning + res$text NA_character_, never an uncaught error.
    - testthat::test_file("tests/testthat/test_provider_custom.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="reversible">New additive exports; no existing behavior touched, trivially removable.</reversibility>
  <done>The single happy path — user fn in, es_provider_response out, error degrades to one warning + NA, base is abstract — is committed and green end-to-end with zero HTTP.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Call-time backend + key resolution (arg -> env -> default), never read keys at construction</name>
  <files>R/provider.R, tests/testthat/test_provider_resolution.R, tests/testthat/helper-provider.R, NAMESPACE</files>
  <read_first>
    - R/diagnostics.R:81 and R/task.R:325 (existing %||% arg->fallback resolution idiom in the codebase to match)
    - 06-RESEARCH.md "Backend Resolution" and "Anti-Patterns to Avoid" (resolve at call time NOT construction; missing key -> one clear failure at call, never a construction crash)
    - 06-RESEARCH.md "Runtime State Inventory" (env vars READ never written: EVENTSTUDY_ADVISOR_PROVIDER/_MODEL/_BASE_URL selectors + OPENAI_API_KEY/ANTHROPIC_API_KEY secrets — the two distinct roles, both implemented per A6)
    - Standard Stack note: withr::local_envvar for deterministic test env-var scoping (withr already in Suggests)
  </read_first>
  <behavior>
    - Test: .resolve_provider_config(provider=NULL, model=NULL, base_url=NULL) with no env set returns the documented defaults (e.g. provider "custom" or "openai" per Claude's discretion, model NULL/default, base_url NULL); with EVENTSTUDY_ADVISOR_PROVIDER="anthropic" set (withr::local_envvar) returns provider "anthropic"; an explicit provider="openai" arg OVERRIDES the env (arg wins).
    - Test: EVENTSTUDY_ADVISOR_MODEL and EVENTSTUDY_ADVISOR_BASE_URL are honored the same way (env fills when arg NULL, arg overrides env).
    - Test: .resolve_api_key("openai") reads OPENAI_API_KEY; .resolve_api_key("anthropic") reads ANTHROPIC_API_KEY; returns NA_character_ when the env var is unset (does NOT stop).
    - Test: constructing a provider with NO key set does NOT error (key is read at call time, not construction) — build the provider object under withr::local_envvar(OPENAI_API_KEY = "") and assert expect_no_error on $new().
  </behavior>
  <action>
    Add .resolve_provider_config(provider = NULL, model = NULL, base_url = NULL) @noRd: each field resolves arg %||% Sys.getenv("EVENTSTUDY_ADVISOR_*", unset = "") -> "" treated as unset -> documented default; return a named list(provider, model, base_url). Add .resolve_api_key(provider) @noRd: switch on provider to the conventional env var name (openai -> OPENAI_API_KEY, anthropic -> ANTHROPIC_API_KEY), Sys.getenv(name, unset = NA_character_); return NA_character_ when unset — NEVER stop here (the missing-key failure is surfaced by the HTTP providers' complete() via .provider_failure at call time in 06-2/06-3). Ensure ProviderBase$initialize stores ONLY non-secret config (model, base_url) and does NOT call .resolve_api_key (call-time-only rule). Create tests/testthat/helper-provider.R and move/define any shared dummy-key + fixture constants there (this file is extended by 06-2/06-3 with mock-response builders — add a short header comment noting that). Create tests/testthat/test_provider_resolution.R with the four behavior tests using withr::local_envvar for deterministic scoping. Regenerate NAMESPACE if any new @export was added (resolution helpers stay @noRd — no new export expected).
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_resolution.R")'</automated>
    <fails_when>testthat reports FAIL > 0 or Rscript exits non-zero — e.g. env not honored when arg is NULL, explicit arg not overriding env, .resolve_api_key stop()ing on unset key instead of returning NA, or a key being read at construction time.</fails_when>
  </verify>
  <acceptance_criteria>
    - .resolve_provider_config honors precedence explicit arg -> EVENTSTUDY_ADVISOR_* env -> default for provider, model, and base_url.
    - .resolve_api_key returns the env key for openai/anthropic and NA_character_ when unset, never stopping.
    - Constructing any provider with no key present raises no error (call-time resolution).
    - tests/testthat/helper-provider.R exists and is loaded by the suite.
    - testthat::test_file("tests/testthat/test_provider_resolution.R") exits 0 with 0 failures.
  </acceptance_criteria>
  <reversibility rating="reversible">Pure additive @noRd helpers; no existing call site changed.</reversibility>
  <done>Backend + key resolution follows arg->env->default, keys read only at call time, and precedence tests are green.</done>
</task>

<task type="auto">
  <name>Task 3: Add httr2/jsonlite to Suggests + provider() factory (custom branch) + verify CRAN-clean with deps absent</name>
  <files>DESCRIPTION, R/provider.R, tests/testthat/test_provider_resolution.R, NAMESPACE</files>
  <read_first>
    - DESCRIPTION:45-64 (current Suggests block — add httr2 (>= 1.0.0) and jsonlite in alpha-consistent position, Suggests NOT Imports)
    - R/report.R:35-42 (the canonical requireNamespace(..., quietly = TRUE) -> clear stop() guard idiom the HTTP providers will use in 06-2/06-3; the factory should NOT itself require httr2 for the custom branch)
    - 06-RESEARCH.md "Pitfall 5: requireNamespace guard missing" and "DESCRIPTION section" (httr2 (>= 1.0.0) floor rationale)
    - 06-RESEARCH.md Open Question 3 (export both the R6 generators AND a provider() convenience factory)
  </read_first>
  <behavior>
    - Test: provider("custom", fn = function(prompt, schema) "x") returns a CustomProvider whose complete("hi")$text == "x" (factory dispatches the custom branch, needs no httr2).
    - Test: provider() with no type arg resolves via .resolve_provider_config default and returns a working provider for the default type OR errors clearly if the default type needs an unimplemented branch (document which — custom is the safe default for this plan).
    - Test: match.arg on an unknown type errors clearly (input validation, ASVS V5).
  </behavior>
  <action>
    Add httr2 (>= 1.0.0) and jsonlite to DESCRIPTION Suggests (NOT Imports) in a position consistent with the existing alpha-ish ordering; this is the ONLY DESCRIPTION change in Phase 6, so 06-2/06-3 must NOT re-touch it. Add exported provider(type = c("custom","openai","anthropic"), fn = NULL, model = NULL, base_url = NULL, ...) factory: match.arg(type) after applying .resolve_provider_config so an unset type falls back to the resolved default; for "custom" construct CustomProvider$new(fn); for "openai"/"anthropic" the factory constructs the respective class — BUT those classes are added in 06-2/06-3, so in THIS plan the factory's openai/anthropic branches call the (not-yet-defined) constructors that 06-2/06-3 add. To keep 06-1 self-contained and green, gate those two branches behind exists("OpenAICompatProvider")/exists("AnthropicProvider") and stop() with "provider type '<t>' is delivered in a later plan" if absent — 06-2/06-3 remove that guard when they add the class (note this handoff in the roxygen). @export provider(). Roxygen @examples that NEVER make a live call: wrap any HTTP-provider example in \dontrun{} or if (interactive()); the custom example runs inline (no network). Regenerate NAMESPACE (adds export(provider)). Extend test_provider_resolution.R with the three factory behavior tests. Then run the CRAN-absent verification below.
  </action>
  <verify>
    <automated>Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_resolution.R"); testthat::test_file("tests/testthat/test_provider_custom.R")' && Rscript -e 'devtools::test()'</automated>
    <fails_when>testthat reports FAIL > 0 on either provider test file, the full devtools::test() shows any regression in the existing 1657-pass suite, or Rscript exits non-zero — e.g. factory does not dispatch custom, unknown type not rejected, or a top-level httr2/jsonlite reference breaks load_all when they are treated as Suggests.</fails_when>
  </verify>
  <acceptance_criteria>
    - DESCRIPTION Suggests contains httr2 (>= 1.0.0) and jsonlite; neither appears in Imports (grep Imports block shows neither).
    - provider() is exported and dispatches the custom branch with no httr2 dependency.
    - provider() rejects an unknown type via match.arg.
    - All @examples are non-live (custom inline; HTTP examples \dontrun{}/if(interactive())).
    - devtools::test() shows the existing 1657 tests still passing plus the new provider tests green.
    - Only DESCRIPTION change in Phase 6 is this Suggests addition.
  </acceptance_criteria>
  <reversibility rating="reversible">Additive Suggests entries + one exported factory; no existing behavior altered.</reversibility>
  <done>httr2/jsonlite are in Suggests, the provider() factory dispatches CustomProvider with zero HTTP, examples are non-live, and the full suite (existing + new) is green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| user-supplied custom fn -> CustomProvider$complete() | User R code executed in-process; trapped in tryCatch so a throwing fn degrades to one warning + NA, never crashes the session. No network in this plan. |
| environment (OPENAI_API_KEY/ANTHROPIC_API_KEY/EVENTSTUDY_ADVISOR_*) -> resolvers | Secrets are READ at call time only, never written, never returned in any object or condition. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-06-01 | Information Disclosure | .resolve_api_key / es_provider_response | high | mitigate | Keys are read at call time and NEVER placed into the es_provider_response, any warning, or any print path; .resolve_api_key returns the raw key only to the (later) HTTP request builder which redacts it. es_provider_response carries source/text/error only — no key field. The mandatory redaction test lands in 06-3. |
| T-06-02 | Denial of Service | throwing custom fn | medium | mitigate | CustomProvider wraps the user fn in tryCatch -> .provider_failure (one warning + NA), so a hostile/buggy custom fn cannot crash the R session (PROV-07). |
| T-06-03 | Tampering | new package deps httr2/jsonlite | high | mitigate | Both are canonical Posit/tidyverse CRAN packages (06-RESEARCH Package Legitimacy Audit: OK/Approved), added to Suggests only, requireNamespace-guarded at HTTP entry points (06-2/06-3). CRAN-clean with them uninstalled is asserted. |
| T-06-04 | Information Disclosure | key read at construction | high | mitigate | Keys are resolved INSIDE complete() at call time, never in initialize(), so a key never lives on a long-held provider object; test asserts construction with no key raises no error. |

This plan opens no network surface (CustomProvider + resolvers only); the HTTP attack surface and the mandatory key-redaction test are introduced with the HTTP providers in 06-2/06-3. All package-legitimacy checks are satisfied (CRAN Posit packages, Suggests-guarded).
</threat_model>

<verification>
- Per task: `Rscript -e 'devtools::load_all("."); testthat::test_file("tests/testthat/test_provider_custom.R")'` and `.../test_provider_resolution.R` → 0 failures.
- Deps-absent gate (CRAN-02/PROV-08): with httr2/jsonlite NOT loaded, CustomProvider + resolution tests still pass (they use no httr2). Optionally assert via `Rscript -e 'devtools::load_all("."); stopifnot(!"httr2" %in% loadedNamespaces() || TRUE)'` — the substantive check is that no top-level httr2 symbol is referenced.
- Phase gate: `Rscript -e 'devtools::test()'` → existing 1657 tests still green (valid-input behavior byte-identical); `Rscript -e 'devtools::check(document=TRUE)'` → no new NOTEs/WARNINGs (deferred to 06-3 phase gate for the full HTTP surface).
</verification>

<success_criteria>
- ProviderBase abstract R6 + CustomProvider implement the uniform complete() contract end-to-end with zero HTTP [PROV-01, PROV-04].
- Backend/model/base_url and keys resolve arg->env->default, keys at call time only [PROV-05].
- A throwing custom fn degrades to one warning + NA, never crashes [PROV-07].
- httr2/jsonlite in Suggests only, CustomProvider + resolution work with them absent [PROV-08, CRAN-02].
- es_provider_response field names match the Phase 5 es_advice shape for trivial Phase 7 slotting [PROV-01].
</success_criteria>

<output>
Create `.planning/phases/06-provider-abstraction-+-cran-safe-http-harness/06-01-SUMMARY.md` when done.
</output>
