# Project Research Summary

**Project:** EventStudy v0.60.0 "Grounded AI Advisor"
**Domain:** LLM-agnostic AI advisor layer over a mature CRAN R package (financial event study analysis)
**Researched:** 2026-09-02
**Confidence:** HIGH

---

## Executive Summary

EventStudy v0.60.0 adds a two-layer grounded AI advisor to the existing statistical pipeline: an offline `es_diagnostics()` layer (pure base R, zero dependencies) that harvests all package-computed signals into a serializable named list, followed by a grounded `es_advise()` layer (LLM provider abstraction via httr2/jsonlite in Suggests) that interprets results with runtime enforcement that every evidence citation comes from the diagnostics. The key design decision is that **the two-layer split is non-negotiable** — the offline diagnostics must work completely independently so it never requires an API key or network access, and the advising must be purely interpretive (never generative of new numbers).

The tech stack is minimal and established (httr2, jsonlite, R6 for provider strategy pattern) with a critical provider-layer fork decision to settle in planning: whether to use ellmer (tidyverse provider-agnostic client, recommended) or hand-roll with thin httr2 wrappers (more control, less dependency overhead). Both paths keep the offline layer dependency-free and deliver identical R6 seams for custom providers and identical grounding enforcement.

The core risks are CRAN compliance (network policy, no phoning home, Suggests-guard discipline), grounding violation (the LLM must never cite diagnostics values that don't exist; runtime guards are mandatory, not optional), and statistical correctness (the assumption→test mapping knowledge base must encode the causal relationships documented in Brown & Warner / MacKinlay / BMP literature, testable via decision tables, not prose). These risks are not novel to the project but are load-bearing: the v0.50.0 robustness contract established "never silently wrong," and v0.60.0 must extend that promise into the advisory layer.

---

## Key Findings

### Recommended Stack

The stack is deliberately minimal. **httr2** (v1.2.2) is the modern R HTTP client standard (successor to httr) with built-in retry/timeout/error handling — essential for LLM API calls with graceful degradation. **jsonlite** (≥1.8.0) serializes diagnostics to JSON and parses structured LLM responses with predictable nested-list output. **R6** (already in codebase) provides the only polymorphism mechanism via the `AdvisorProvider` base class and concrete provider subclasses (AnthropicProvider, OpenAICompatibleProvider, CustomProvider) — consistent with how the pipeline uses R6 for models and test statistics.

**Critical fork decision for planning:** Provider dispatch can be implemented via **ellmer** (Posit's tidyverse-native LLM client, handles Anthropic/OpenAI normalization, available on CRAN, more dependencies, less control) or a **thin httr2 layer** (full control, minimal Suggests deps, hand-written provider schema normalization). Both keep the offline `es_diagnostics()` dependency-free. **Recommendation:** default to ellmer for the two built-in providers and keep a lightweight `CustomProvider` R6 hook for users with unsupported endpoints — if ellmer's dependency tree proves too heavy for CRAN comfort during planning, fall back to thin httr2 (implementation is contained, no architectural change needed).

**Core technologies:**
- **httr2 (1.2.2)** — Modern HTTP client with `req_retry()`, `req_timeout()`, `req_error()` — the standard for CRAN-safe LLM integrations
- **jsonlite (≥1.8.0)** — JSON serialization/parsing; produces predictable nested lists from diagnostics
- **R6** — Provider abstraction hierarchy (existing pattern in codebase; no new language)
- **httptest2 (1.2.0)** — Mock HTTP fixtures for offline testing; prevents network calls in CI/CRAN

### Expected Features

**Must have (table stakes) for v0.60.0:**
- `es_diagnostics(task)` — offline, zero-dep diagnostics dict harvesting model fit, autocorrelation, normality tests, CAR/CAAR stats, v0.50.0 contract signals. Why essential: the grounding invariant depends on this.
- `es_advise(diagnostics, provider=, model=, task_type=)` — grounded Advice S3 object with structured schema, runtime guard, graceful degradation. Why essential: the user-facing feature.
- **Grounding runtime guard** — post-generation validator rejecting evidence citing keys absent from diagnostics dict. Why essential: runtime enforcement is testable and deterministic.
- **Provider abstraction** — OpenAI-compatible + Anthropic + custom hook. Why essential: vendor lock-in blocks adoption of non-Anthropic users.
- **Rule-based test-statistic recommendation** — deterministic mapping (Shapiro-Wilk p < 0.05 → non-parametric; overlap → KP correction). Why essential: answers most common question offline.
- `es_flag_issues(task)` — pure rule-based interpreter of v0.50.0 contract signals. Why essential: makes the robustness contract human-readable.
- **CRAN-clean packaging** — zero new Imports, all AI deps in Suggests, @examplesIf guards, skip_on_cran tests, static fixtures. Why essential: CRAN gate.
- **Agent Skill SKILL.md** — Claude Code orchestration (diagnose → advise → re-run loop). Why essential: stated in PROJECT.md.

**Should have (v0.60.x):**
- Report-writing assistance (mode="report_section")
- Design discussion mode (mode="discuss")
- `es_analyze()` convenience wrapper

**Defer (v1.0+ / Advisor Pro):**
- Retrieval-grounded corpus RAG
- Multi-turn conversation state

### Architecture Approach

Two read-only layers above the existing pipeline: (1) **Offline diagnostics** (`es_diagnostics.R`, pure base R) harvests task$data_tbl, model$statistics, model$is_fitted into serializable named list. (2) **Grounded advise** (`es_advise.R`, httr2+jsonlite in Suggests) resolves provider (3-tier: arg → env → default), builds prompts (KB + flat diagnostics schema), calls provider, parses response, runs grounding guard, returns Advice S3.

**Major components:**
1. **`es_diagnostics()`** — Zero-dep diagnostics harvester; serializable named list; 100% testable offline
2. **`AdvisorProvider` R6 hierarchy** — Base class with abstract `call()` method; AnthropicProvider (Messages API), OpenAICompatibleProvider (/chat/completions), CustomProvider (user function)
3. **Grounding guard** — `.validate_grounding()` flattens diagnostics, checks evidence keys exist, drops/errors on violations
4. **Knowledge base** — Curated assumption→test decision table (structured R data, testable, cited)
5. **Advice S3 object** — Structured return; interpretation, recommendations, caveats, grounding_status; print method

### Critical Pitfalls (Top 5)

1. **CRAN network policy violations** — httr2 calls without guards in examples/tests/vignettes break R CMD check. Prevention: @examplesIf, skip_on_cran(), vignette eval guards.

2. **API key leakage via fixtures** — vcr cassettes/mocks capture Authorization headers. Prevention: static hand-crafted mocks, filter_sensitive_data config, pre-commit grep.

3. **Grounding guard bypass** — LLM rephrases numbers ("approximately 2%"). Prevention: Runtime R function checks evidence keys; rejects on value tolerance violation.

4. **Statistical KB errors** — Wrong assumption→test mapping (Patell under non-normality). Prevention: Testable decision table; regression tests verify each rule against literature.

5. **Suggests-guard mistakes** — require() instead of requireNamespace(), missing pkg::fun() notation. Prevention: Strict import discipline from Phase 1.

---

## Implications for Roadmap

Research suggests **4-phase structure** driven by dependency ordering and risk isolation.

### Phase 1: Offline Diagnostics + Provider Abstraction Foundation

**Rationale:** Offline layer is zero-dep grounding foundation; provider R6 hierarchy testable in isolation; establishes CRAN-safe infrastructure.

**Delivers:** es_diagnostics() exported; R6 provider hierarchy; unit tests (no network); Suggests-guard patterns established.

**Addresses:** es_diagnostics, provider abstraction, CRAN compliance
**Avoids:** CRAN network policy, key leakage, guard mistakes
**Research flags:** None — offline-only, standard patterns

---

### Phase 2: Knowledge Base + Grounding Guard

**Rationale:** Grounding invariant is load-bearing; must be deterministic and independently testable before any LLM involvement.

**Delivers:** assumption_test_map (structured tibble + citations); `.validate_grounding()` function; 15+ decision-table tests; mock LLM rejection tests.

**Addresses:** Rule-based recommendations, grounding guard, es_flag_issues
**Avoids:** KB statistical errors, grounding bypass
**Research flags:** **Needs validation** — Cross-check assumption→test mapping against Brown & Warner (1985), MacKinlay (1997), BMP (1991), KP (2010/2011). Recommend literature-review sub-task.

---

### Phase 3: Provider Layer HTTP Integration + Test Harness

**Rationale:** Once diagnostics and guard solid, integrate HTTP; tested entirely with httptest2 mocks (no real keys/calls in CI).

**Delivers:** AnthropicProvider + OpenAICompatibleProvider complete; req_timeout/req_retry logic; static mocks; defensive parsing; timeout/rate-limit tests.

**Addresses:** Provider implementations, graceful degradation, key safety
**Avoids:** Key leakage, flaky tests, provider drift, injection attacks
**Research flags:** **Provider fork decision** — ellmer vs. thin httr2. Recommend 1–2 hour spike at Phase 3 start.

---

### Phase 4: Advise + Grounding Integration + Agent Skill

**Rationale:** Integrate all layers; write Agent Skill orchestrating full loop. Last phase because depends on everything prior.

**Delivers:** es_advise() complete; Advice S3 object; es_flag_issues(); Agent Skill SKILL.md + references; integration + smoke tests.

**Addresses:** es_advise, Advice schema, Agent Skill, all task_type variants
**Avoids:** All prior pitfalls mitigated
**Research flags:** None — integration only

---

### Phase Ordering Rationale

- **Offline first** — No external dependencies; forms grounding foundation
- **Guards second** — Safety invariant; independently testable; regression-heavy
- **HTTP third** — Integrates after foundation solid; mocked entirely
- **Integration last** — Each dependency verified; straightforward

Operationalizes dependency inversion: higher-level features depend on lower-level abstractions that are independently testable.

### Research Flags

**Needs deeper research:**
- **Phase 2:** KB correctness — Verify assumption→test mappings against primary literature
- **Phase 3:** Provider fork (ellmer vs. thin httr2) — Prototype spike needed

**Standard patterns (skip research):**
- **Phase 1:** Mirrors existing diagnostics.R, contract.R patterns
- **Phase 4:** All components independently tested

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | HIGH | httr2 1.2.2, jsonlite, R6 verified on CRAN; provider schema from official APIs; fork is planning decision |
| **Features** | HIGH | Aligns with PROJECT.md intent; assumption→test table verified against literature |
| **Architecture** | HIGH | Two-layer pattern from pyfda/fdars; confirmed against codebase R6 conventions |
| **Pitfalls** | HIGH | CRAN policy verifiable; HTTP patterns from rOpenSci; statistical risks from event-study literature |

**Overall confidence:** HIGH

### Gaps to Address

1. **Provider fork decision** — Spike at Phase 3 start to prototype both implementations
2. **KB completeness** — Cross-check against Brown & Warner Table III, BMP Table I, KP 2010 Table 2
3. **Report-writing scope** — Verify generate_report() optional advice param integration
4. **Vignette strategy** — Defer to v0.60.1 or pre-build static HTML
5. **Offline rule-based path** — Verify identical results to KB decision table

---

## Sources

### Primary (HIGH confidence)

- **CRAN Repository Policy** — Network access, user consent, no phoning home
- **httr2 (CRAN)** — v1.2.2, retry/timeout/error API; documentation at https://httr2.r-lib.org/
- **Anthropic Messages API** — Structured output via tool_use; https://docs.anthropic.com/
- **OpenAI API** — Structured output via response_format.type="json_schema"
- **EventStudy codebase** — R/contract.R, R/diagnostics.R, R/models.R; R6 patterns, precedence models

### Secondary (MEDIUM confidence)

- **HTTP Testing in R** (rOpenSci) — vcr, httptest2, secret redaction, CRAN policy
- **R Packages (2e)** — Suggests/Imports, requireNamespace, skip_if_not_installed patterns
- **fdars Python package** (PyPI) — Two-layer diagnostic+advise pattern precedent

### Tertiary (PRIMARY LITERATURE, HIGH academic confidence)

- Brown & Warner (1985) — Foundation for normality tests, parametric choice
- MacKinlay (1997) — Comprehensive test statistic selection framework
- Patell (1976) — Patell Z test, homoskedasticity assumption
- BMP (1991) — BMP test under event-induced variance
- Kolari & Pynnönen (2010/2011) — Cross-correlation corrections, CAR window overlap

---

## Cross-Cutting Throughlines

Three design decisions recur throughout all research and must be locked:

1. **Two-layer split is non-negotiable:** `es_diagnostics()` works offline (zero new hard deps); `es_advise()` purely interprets from diagnostics (never generates new numbers). Ensures API key never required for core functionality.

2. **Grounding enforced at runtime, not just in prompts:** System prompt instruction insufficient. `.validate_grounding()` must be deterministic R function checking every evidence entry exists in actual diagnostics dict. Testable, verifiable.

3. **CRAN network policy enforced from Phase 1:** Every import guard, skip_on_cran(), mock fixture in place before any HTTP code written. Prevents failure mode where local tests pass but CRAN check fails.

---

*Research completed: 2026-09-02*
*Synthesized by: gsd-synthesizer agent*
*Ready for roadmap planning: YES*
