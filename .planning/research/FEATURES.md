# Feature Research

**Domain:** Grounded AI Advisor for a CRAN R statistical package (financial event study analysis)
**Researched:** 2026-09-02
**Confidence:** MEDIUM (statistical grounding mapping HIGH; LLM advisor patterns MEDIUM; SKILL.md anatomy HIGH; CRAN policy HIGH)

---

## Background: The Advisor Pattern

The advisor follows the two-layer pattern from the fdars/pyfda project (github.com/sipemu/pyfda): a deterministic, offline `build_diagnostics` layer that harvests package-computed values, plus a grounded `advise()` layer that passes those values to an LLM and forbids the LLM from introducing numbers not present in the diagnostics. The hard invariant — "interpret only what was computed, never fabricate" — is the statistical analog of the v0.50.0 robustness contract's "never silently wrong."

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Depends On | Notes |
|---------|--------------|------------|------------|-------|
| **`es_diagnostics(task)` — offline diagnostics dict** | Every grounded advisor needs a deterministic, serializable feature layer that works with no API key. Users expect diagnostics to be runnable independently. | MEDIUM | `diagnostics.R` (model_diagnostics, pretrend_test), v0.50.0 contract signals (is_fitted, NA counts, zero-variance flags), `single_event_test_statistics.R`, `multi_event_test_statistics.R` | Pure base R; zero new hard deps. Returns a named list: model fit stats, per-event is_fitted/NA/zero-var flags, Shapiro-Wilk p per firm, DW stat, Ljung-Box p, acf1, sigma, r2, pre-trend t/p, CAR/CAAR + p-values, n_events, cross-sectional dispersion (IQR of CARs), event-window overlap count. |
| **`es_advise(diag, ...)` — grounded Advice object** | Users bringing an LLM to a stats package expect a structured, trustworthy return — not a raw chat response. The Advice schema is the contract. | HIGH | `es_diagnostics()` (must run first), httr2 + jsonlite (Suggests), provider abstraction | Schema fields listed in "Advice Schema" section below. LLM receives only the diagnostics dict as grounding context; runtime guard rejects any evidence field citing values absent from it. |
| **Grounding runtime guard** | Without this, the "grounded" promise is just a system prompt clause. Users and maintainers need testable enforcement. | MEDIUM | `es_advise()`, Advice schema | Implemented as a post-generation validator: each `evidence` string is checked against the diagnostics keys; any recommendation citing a value not in the dict is dropped with a warning, not silently returned. Covered by regression tests. |
| **LLM-agnostic provider abstraction** | Researchers use many providers; hard-coding Anthropic would exclude OpenAI/Ollama users and create a single-vendor dependency. | MEDIUM | httr2, jsonlite (both Suggests) | Three-tier precedence: function arg `provider=` → env var `EVENTSTUDY_LLM_PROVIDER` + `EVENTSTUDY_LLM_MODEL` → package default (anthropic/claude-sonnet-4-5). Two code paths: OpenAI-compatible endpoint (covers OpenAI, Ollama, LM Studio, any OpenAI-compatible gateway) + native Anthropic Messages API. Custom-provider hook for anything else: `register_es_provider(name, call_fn)`. |
| **Advice type: result interpretation** | Users want help reading their CAR/CAAR and p-values in plain language before deciding what to do next. | LOW | Diagnostics dict (car, caar, p_value columns, n_events, significance threshold) | LLM prompt includes: event window, CAR magnitude, significance, n_events. Output: interpretation field of Advice. Must not state a CAR value not present in diagnostics. |
| **Advice type: test statistic recommendation** | The test-statistic choice is the most common source of mis-specification in event studies; users actively seek guidance on which test to run. | MEDIUM | Diagnostics (shapiro_p, DW, cross-sectional dispersion, n_events, event-window overlap count) | Grounding mapping is fully deterministic — see "Assumption-to-Test Mapping" below. The LLM recommendation is grounded by passing these values; the rule-based mapping also produces a deterministic recommendation that can be used without any LLM call. |
| **Advice type: model and window recommendation** | Model choice (Market vs FF3 vs Carhart vs GARCH) and window length are the second most common specification questions. | MEDIUM | Diagnostics (r2, sigma, acf1, DW, Ljung-Box p, is_fitted flags, estimation window length, event window length) | Model recommendation: low r2 + high sigma → suggest adding factor data (FF3/Carhart); autocorrelation (DW < 1.5 or Ljung-Box p < 0.05) → GARCH or Rolling-Window; very short windows → warn on Patell correction validity. |
| **Advice type: robustness-issue flagging from v0.50.0 contract** | The degenerate-input contract surfaces `is_fitted=FALSE`, NA counts, and zero-variance/insufficient-obs flags — users need to understand what these mean and what to do. | LOW | v0.50.0 contract signals: `is_fitted`, `zero_var_flag`, `insufficient_obs_flag`, NA count per event | This advice type requires no LLM call — it is a pure rule-based interpreter over the contract state. Should be available even in offline mode. Produces a flagged_issues field alongside the LLM Advice. |
| **API key safety** | Users expect that their API key is never logged, bundled, or committed. | LOW | `es_advise()`, provider abstraction | Key comes only from the user's environment (`Sys.getenv`). Never passed through to any log, warning message, or cat() call. No key stored in any R6 object field that serializes. CRAN-mandatory. |
| **CRAN-clean packaging** | Package must pass R CMD check with zero new NOTEs/WARNINGs. All AI/HTTP deps stay in Suggests. | MEDIUM | httr2, jsonlite, httptest2 or vcr (all Suggests) | Offline `es_diagnostics()` must add zero hard dependencies. `es_advise()` guards every httr2/jsonlite call with `requireNamespace(..., quietly=TRUE)` and stops with an informative message. Tests use record/replay (httptest2 or vcr cassettes) so CRAN check never hits the network. |
| **Graceful degradation on API failure** | Network calls fail. Users expect a warning, not a crash, when the API is down or rate-limited. | LOW | httr2 retry/backoff via `req_retry()`, `req_timeout()` | `es_advise()` wraps `httr2::req_perform()` in `tryCatch`; on failure returns `NULL` with one `warning()` naming the error. Retry: `req_retry(max_tries=3, backoff=~2^.x)`. Timeout: `req_timeout(30)`. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Depends On | Notes |
|---------|-------------------|------------|------------|-------|
| **Deterministic rule-based fallback for all advice types** | Unlike pure LLM advisors, every recommendation has a code-verifiable grounding rule. Users can audit why a recommendation was made without an API key. | MEDIUM | Diagnostics dict, assumption→test mapping table | The rule-based engine produces the same structured Advice fields as the LLM path, using if/else logic over diagnostic thresholds. The LLM path enriches the narrative; the rule-based path provides the structure. Both paths populate the same Advice schema — the LLM is additive, not load-bearing. |
| **Assumption-to-test mapping grounding knowledge base** | A curated reference map of statistical assumptions → test statistic choices (with academic citations: MacKinlay 1997, Brown & Warner 1985, Patell 1976, BMP 1991, Kolari-Pynnönen 2010, 2011) injected as grounded system context. This is domain knowledge not present in general LLMs. | LOW | Grounding knowledge base file (R/sysdata or inst/advisordb/) | Injected into the LLM system prompt as a structured citation block. Never injected as raw text — structured as JSON array of {assumption, test_statistic, citation, when_to_use}. |
| **Design discussion mode** | Lets users ask open questions like "should I use a rolling window or OLS?" and get a grounded conversational response that cites the current diagnostic values. | MEDIUM | `es_advise(mode="discuss", question=...)`, diagnostics dict | Multi-turn is out of scope; single-turn question + diagnostics context. The LLM must cite only values from the diagnostics in any quantitative claim. |
| **Report-writing assistance** | Drafts a grounded methods section and results paragraph for `generate_report()`, citing actual computed values. Saves researchers an hour of writing. | MEDIUM | `es_advise(mode="report_section", section=...)`, diagnostics dict, `report.R` `generate_report()` | Returns a character vector of ready-to-paste RMarkdown. Each quantitative claim in the narrative is verified by the grounding guard to cite a diagnostics value. The draft includes CAR/CAAR, significance, model name, test statistic name, estimation window, event window — all from diagnostics. See "Report-Writing Patterns" below. |
| **Claude Code Agent Skill (`es-advisor` SKILL.md)** | Makes the entire advise workflow invocable from Claude Code as `/es-advisor`, enabling a conversational agentic loop: load → run → diagnose → advise → re-run → compare. Researchers using Claude Code get a hands-free event study assistant. | MEDIUM | SKILL.md + references/ directory containing: ASSUMPTIONS.md (assumption→test map), WORKFLOW.md (step-by-step procedure), CITATIONS.md (academic refs) | SKILL.md anatomy: YAML frontmatter (description triggers), dynamic context injection via `!` lines (runs `Rscript -e "..."` to get current diagnostics), instruction body (phases 1–5 with decision branches). See "Agent Skill Anatomy" below. |
| **Waitlist surface for "Advisor Pro"** | Validates commercial demand for a future retrieval-grounded paid tier before building the heavy RAG version. Gathers early adopters. | LOW | None (pure docs + URL) | Pattern: a `?AdvisorPro` help page + a one-liner in `es_advise()` output footer + a `NEWS.md` note. Never contacts any server. Just a URL and a note. No telemetry. CRAN-safe. See "Waitlist Pattern" below. |
| **Offline robustness-issue reporter (no LLM required)** | `es_flag_issues(task)` — a pure rule-based function that reads the v0.50.0 contract state and returns a tibble of human-readable issue descriptions with recommended actions. Available even when no API key is configured. | LOW | v0.50.0 contract signals, diagnostics.R | Returns a tibble: event_id, firm_symbol, issue_type (insufficient_obs / zero_variance / not_fitted / high_na / autocorrelation / non_normality / pre_trend), severity (warning/critical), message, recommended_action. Separable from `es_advise()`. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Streaming LLM responses** | Makes the UI feel faster and more interactive. | In R's single-threaded event loop there is no async I/O; streaming requires either a busy-wait loop (blocking) or a separate process. Adds complexity, is not testable with record/replay mocks, and provides no value for the structured Advice schema which needs the complete JSON before it can be validated. The advisor is a function call, not a chat UI. | Return the complete Advice object synchronously. If users want streaming, they can call the LLM API directly. |
| **Multi-turn conversation state** | Users want to "chat" with the advisor across multiple exchanges. | State management across R sessions is non-trivial; R has no built-in conversation store. A multi-turn API inflates the token cost per call unpredictably. The grounding invariant becomes harder to enforce when the diagnostics may have changed between turns. | Single-turn design discussion mode covers 90% of the use case. For true multi-turn, users should use a dedicated chat interface that calls `es_diagnostics()` fresh each turn. |
| **Auto-calling es_advise() on every es_diagnostics() run** | Convenience — users want one function. | Makes every `es_diagnostics()` call dependent on a network connection and an API key. Breaks the offline guarantee. Violates CRAN policy if it contacts a server without explicit user action. Breaks testability of the offline layer. | Keep `es_diagnostics()` and `es_advise()` as separate steps. Provide a convenience wrapper `es_analyze(task, advise=FALSE)` that chains them, with `advise=FALSE` default. |
| **Hardcoding Anthropic as the only provider** | Simplicity — Anthropic is the author's preference. | Vendor lock-in. Users without Anthropic API keys are excluded. Adds a hard dependency on the Anthropic SDK or native auth scheme. Creates a single point of failure. Harder to test without the specific vendor's sandbox. | Provider abstraction with OpenAI-compatible + Anthropic paths and a custom hook. All three are covered by one record/replay test fixture each. |
| **Phoning home / telemetry / usage analytics** | Product analytics — knowing how the advisor is used. | Explicitly prohibited by CRAN Repository Policy: "Packages should not send information about the R session to the maintainer's or third-party sites without obtaining confirmation from the user." A CRAN submission that phones home will be rejected. | Gather signal through the waitlist URL click-through (passive) and GitHub issues/stars. Never instrument the package itself. |
| **Caching LLM responses to disk by default** | Speed / cost — avoid re-running the LLM on the same diagnostics. | A default disk cache creates files in the user's filesystem without their knowledge. CRAN policy requires packages to respect the user's filesystem. An opt-in cache with an explicit path is fine; a default one is not. Also: caching responses that cite diagnostic values means the cache becomes stale when the task changes. | Make caching opt-in: `es_advise(cache=TRUE, cache_dir=tempdir())`. Default: no cache. |
| **Downloading or embedding a full literature corpus (RAG)** | Better grounding — the LLM could search the full Brown & Warner / MacKinlay corpus. | Heavy dependencies (vector DB, embedding model), unacceptable binary size for CRAN, and the corpus licensing is unclear. This is the "Advisor Pro" scope. Building it in the free tier kills the freemium model. | The curated knowledge base (assumption→test mapping with academic citations) covers the essential methodology grounding. RAG is the Advisor Pro value proposition. |
| **Generating new statistical results inside the LLM** | "Can the advisor re-run the analysis with different parameters?" | The LLM cannot reliably execute R code or reproduce statistical calculations. Any numbers it generates would not be package-computed and would break the grounding invariant. Attempting to use the LLM to compute statistics creates exactly the "silently wrong number" risk that v0.50.0 was built to eliminate. | For re-running with different parameters, use the actual R pipeline. The Agent Skill orchestrates this via Bash tool calls to `Rscript`. |
| **Free-text evidence strings in recommendations** | Richer narrative per recommendation. | Free-text evidence bypasses the grounding guard. If the evidence field is unstructured, the guard cannot reliably check whether the cited value exists in the diagnostics. | Evidence field is a named list: `list(diagnostic_key="shapiro_p", value=0.03, threshold=0.05, direction="below")`. The guard checks `diagnostic_key` exists in the diagnostics dict and `value` matches within floating-point tolerance. |

---

## Assumption-to-Test Mapping (Grounding Knowledge Base)

This mapping is the core of the test-statistic recommendation advice type. Every entry corresponds to a diagnostics dict key and a threshold, producing a deterministic recommendation that the LLM enriches.

| Diagnostic Key | Threshold / Condition | Implication | Recommended Test | Contraindicated Test | Academic Citation |
|---|---|---|---|---|---|
| `shapiro_p` (per firm, aggregated as min across events) | < 0.05 (reject normality) | Residuals are non-normal; parametric tests lose validity | `SignTest`, `KolariPynnonenTest` (rank-based variant) | `PatellZTest`, `ARTTest` / `CARTTest` on small N | Kolari & Pynnönen 2010 |
| `shapiro_p` | ≥ 0.05 (normality not rejected) | Normality assumption plausible | `PatellZTest` or `BMPTest` are valid choices | — | Patell 1976, BMP 1991 |
| Cross-sectional dispersion (IQR of CARs / mean CAR, when N ≥ 5) | IQR/mean > 1 OR N < 10 | High cross-sectional variance; event-induced variance likely | `BMPTest` (robust to event-induced variance) | `PatellZTest` (over-rejects under event-induced variance) | BMP 1991 |
| Event-window overlap count (count of event pairs sharing ≥ 1 calendar date) | > 0 | Cross-sectional correlation from overlapping windows | `KolariPynnonenTest` (corrects for r-bar inflation) | `PatellZTest`, `BMPTest` without KP correction | Kolari & Pynnönen 2010 |
| `acf1` (first-order autocorrelation of estimation residuals) | abs(acf1) > 0.2 | Serial correlation in residuals; OLS standard errors underestimate variance | `BMPTest` (standardization helps), consider GARCH model | `ARTTest` with OLS sigma (understated) | Brown & Warner 1985 |
| `dw_stat` | < 1.5 or > 2.5 | Significant autocorrelation | Same as acf1 > 0.2 | — | Durbin & Watson 1950 |
| `ljung_box_p` | < 0.05 | Residuals are autocorrelated | Consider Rolling-Window or GARCH model; use `BMPTest` | `ARTTest` without autocorrelation correction | Box & Jenkins |
| `r2` (per event, aggregated as median) | < 0.1 | Market model explains little variance; consider multi-factor model | Consider FamaFrench3FactorModel or Carhart4FactorModel | — | MacKinlay 1997 |
| `r2` | ≥ 0.5 | Model fit adequate | Current model appropriate | — | — |
| `is_fitted` (any FALSE) | TRUE for any event | Degenerate input: insufficient obs, zero variance, or upstream NA | `es_flag_issues()` — not a test statistic issue | All parametric tests (NA propagation from unfitted model) | v0.50.0 contract |
| `n_valid_events` (from CSectTTest compute) | < 5 | Too few events for cross-sectional inference | `SignTest` (valid at small N), report with caveat | `CSectTTest`, `PatellZTest` (Central Limit Theorem requires N ≥ 30) | MacKinlay 1997 |
| `pretrend_p` (from pretrend_test) | < 0.05 | Significant pre-event returns; model may be misspecified or contaminated | Extend estimation window, shift it, or use event-day dummies | Any test (results unreliable until pre-trend resolved) | MacKinlay 1997 |

---

## Advice Schema (Structured Output Contract)

The LLM must return a JSON object matching this schema. The grounding guard validates it before the Advice object is returned to the user.

### Table-Stakes Fields (must be present)

```
Advice {
  interpretation: character          # plain-language summary of what the results mean
  recommendations: list of Recommendation {
    action: character                # what to do (imperative, one sentence)
    kind: character                  # one of: test_statistic | model | window | robustness | report_writing | design
    rationale: character             # why this action, referencing diagnostic values by name
    evidence: list {
      diagnostic_key: character      # must be a key present in the diagnostics dict
      value: numeric                 # the actual value from the diagnostics
      threshold: numeric or NULL     # the threshold that triggered this recommendation
      direction: character           # "above" | "below" | "equals" | "present"
    }
    expected_effect: character       # what changes if user takes this action
    priority: character              # "required" | "recommended" | "optional"
  }
  caveats: character vector          # list of limitations and conditions; always non-empty
  model_used: character              # the LLM provider + model id that generated this
  diagnostics_version: character     # SHA or timestamp of the diagnostics dict used
  grounding_violations: integer      # count of recommendations dropped by guard; 0 is expected
}
```

### Optional / Differentiator Fields

```
  flagged_issues: list of FlaggedIssue  # from rule-based es_flag_issues(); present even without LLM
  report_draft: character or NULL       # drafted RMarkdown narrative if mode="report_section"
  raw_response: character or NULL       # raw LLM JSON if user requests it (for debugging)
```

---

## Agent Skill Anatomy (SKILL.md for `es-advisor`)

Stored at `.claude/skills/es-advisor/SKILL.md` in the user's project (or committed to the eventstudy repo itself for maintainer use).

### YAML Frontmatter

```yaml
---
description: >
  Runs an end-to-end EventStudy analysis cycle: loads data, runs the
  pipeline, calls es_diagnostics(), calls es_advise(), interprets the
  Advice object, and can re-run with adjusted parameters for comparison.
  Use when the user wants to analyze event study results, get test
  statistic recommendations, check robustness, or draft report sections.
---
```

### Instruction Body Sections

**Phase 1 — Load & Run (Bash tool):**
The skill checks whether a fitted `EventStudyTask` exists in the session or whether the user needs to run the pipeline. Uses dynamic context injection with `!` lines to introspect the workspace:
```
!`Rscript -e "cat(file.exists('results/task.rds'))"`
```

**Phase 2 — Diagnose:**
Calls `es_diagnostics(task)` via a Bash Rscript call and captures the resulting list as JSON for injection into subsequent context.

**Phase 3 — Advise:**
Calls `es_advise(diag, provider=<from env>, mode=<from user intent>)` and presents the Advice object in a human-readable format, highlighting grounding_violations=0 as a trust signal.

**Phase 4 — Interpret & Recommend:**
Presents each recommendation with its evidence dict. For test-statistic recommendations, the skill additionally shows the deterministic rule-based recommendation (from the grounding knowledge base) alongside the LLM recommendation so the user can compare.

**Phase 5 — Re-run & Compare (optional):**
If the user accepts a model or test recommendation, the skill generates the R code to re-run with the new parameters, runs it, and compares the new diagnostics against the old to show the effect.

### Reference Files (in `.claude/skills/es-advisor/references/`)

- `ASSUMPTIONS.md` — the full assumption-to-test mapping table in human-readable form
- `CITATIONS.md` — academic citation list (MacKinlay 1997, BMP 1991, KP 2010/2011, etc.)
- `WORKFLOW.md` — the 5-phase procedure in detail
- `API-KEYS.md` — how to configure provider credentials

---

## Report-Writing Assistance Patterns

The report_section mode drafts a methods + results paragraph grounded in actual computed values. The pattern:

1. The diagnostics dict is passed as structured JSON context to the LLM.
2. The system prompt includes the sentence: "Every quantitative claim in the drafted text must be traceable to a key in the diagnostics JSON. Do not interpolate, round, or rephrase any numeric value — use it exactly as provided."
3. The LLM drafts a paragraph template with `{diagnostic_key}` placeholders.
4. The grounding guard resolves each placeholder against the diagnostics dict and rejects any that cannot be resolved.
5. The resolved text is returned in `report_draft` and can be pasted directly into the RMarkdown template consumed by `generate_report()`.

Sections supported: `"methods"` (model choice, window parameters, test statistic selection, assumption checks), `"results"` (CAR/CAAR, significance, cross-event summary), `"diagnostics_narrative"` (what the Shapiro-Wilk, DW, Ljung-Box results mean).

---

## Waitlist Pattern (CRAN-Safe)

Pattern: documentation-only surface, zero network calls.

- A `?AdvisorPro` help topic (roxygen2 `@name AdvisorPro`) that describes the future paid tier and includes a static URL: `https://eventstudy.de/advisor-pro` (or equivalent).
- A one-line footer appended to every `es_advise()` print output (the Advice S3 `print` method): `"Advisor Pro (full literature corpus, RAG) — waitlist: https://eventstudy.de/advisor-pro"`.
- A `NEWS.md` entry announcing the waitlist.
- The URL is a static string in the package — it never sends a request. Users choose to visit it.
- This is identical to the pattern used by `renv`, `pak`, and other CRAN packages that advertise commercial services via static documentation.

CRAN policy compliance: the package never sends data to maintainer or third-party sites; the waitlist URL is passive (user-initiated navigation). The `print` footer is informational, not a network call.

---

## Feature Dependencies

```
es_diagnostics(task)
    └──requires──> fitted EventStudyTask (fit_model() complete)
    └──reuses──> diagnostics.R: model_diagnostics(), pretrend_test()
    └──reuses──> v0.50.0 contract: is_fitted, zero_var_flag, insufficient_obs_flag, NA counts

es_advise(diag, ...)
    └──requires──> es_diagnostics() output (diagnostics dict)
    └──requires──> httr2, jsonlite (Suggests-guarded)
    └──uses──> provider abstraction (OpenAI-compat or Anthropic)
    └──uses──> grounding knowledge base (curated assumption→test map)
    └──applies──> grounding runtime guard (post-generation validator)

es_flag_issues(task)
    └──requires──> fitted EventStudyTask
    └──reuses──> v0.50.0 contract signals (is_fitted, flags)
    └──independent of LLM (no es_advise dependency)

report_draft (mode="report_section" in es_advise)
    └──requires──> es_advise() with mode="report_section"
    └──feeds──> generate_report() in report.R (optional integration)

Agent Skill (es-advisor SKILL.md)
    └──orchestrates──> es_diagnostics() → es_advise() → re-run loop
    └──reads──> references/ASSUMPTIONS.md, CITATIONS.md, WORKFLOW.md
    └──uses──> Claude Code Bash tool for Rscript calls
```

---

## MVP Definition

### Launch With (v0.60.0)

- [x] `es_diagnostics(task)` — offline, zero-dep, serializable diagnostics dict harvesting all relevant signals from existing diagnostics.R + v0.50.0 contract — why essential: the grounding contract; everything else depends on it
- [x] `es_advise(diag, ...)` — grounded Advice object with structured schema, runtime grounding guard, and graceful degradation — why essential: the primary user-facing feature; without it there is no advisor
- [x] Provider abstraction — OpenAI-compatible + Anthropic paths + custom hook — why essential: vendor lock-in is an immediate adoption blocker for researchers using non-Anthropic providers
- [x] Rule-based test-statistic recommendation (deterministic, no LLM required) — why essential: answers the most common user question offline; demonstrates the grounding principle without an API key
- [x] Robustness-issue flagging from v0.50.0 contract (`es_flag_issues`) — why essential: direct payoff of the v0.50.0 investment; makes the contract human-readable
- [x] CRAN-clean packaging (zero new hard deps, all AI deps in Suggests, httptest2/vcr test fixtures, skip_on_cran guards) — why essential: CRAN submission must pass
- [x] Agent Skill SKILL.md — why essential: stated in PROJECT.md as a target feature; delivers the conversational loop without MCP complexity

### Add After Validation (v0.60.x)

- [ ] Report-writing assistance (mode="report_section") — trigger: user demand in GitHub issues post-launch; adds report.R integration
- [ ] Design discussion mode (mode="discuss") — trigger: user feedback requesting conversational Q&A
- [ ] `es_analyze()` convenience wrapper — trigger: users report the two-step call is inconvenient

### Future Consideration (v1.0+ / Advisor Pro)

- [ ] Retrieval-grounded "Advisor Pro" (full corpus RAG, vector search over Brown & Warner / MacKinlay / BMP papers) — why defer: requires vector DB, embedding infrastructure, corpus licensing; validate demand via waitlist first
- [ ] MCP server surface — why defer: PROJECT.md explicitly deferred; Agent Skill delivers the same loop with less surface area
- [ ] Multi-turn conversation state — why defer: single-turn covers the use case; multi-turn adds state-management complexity without proportional value

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `es_diagnostics()` | HIGH | MEDIUM | P1 |
| `es_advise()` + Advice schema | HIGH | HIGH | P1 |
| Grounding runtime guard | HIGH | MEDIUM | P1 |
| Rule-based test-statistic recommendation | HIGH | LOW | P1 |
| Provider abstraction (OpenAI-compat + Anthropic) | HIGH | MEDIUM | P1 |
| `es_flag_issues()` from v0.50.0 contract | MEDIUM | LOW | P1 |
| CRAN-clean packaging + test fixtures | HIGH | MEDIUM | P1 |
| Agent Skill SKILL.md | MEDIUM | LOW | P1 |
| Assumption→test grounding knowledge base | HIGH | LOW | P1 |
| Waitlist surface | LOW | LOW | P2 |
| Report-writing assistance | MEDIUM | MEDIUM | P2 |
| Design discussion mode | MEDIUM | LOW | P2 |
| `es_analyze()` convenience wrapper | LOW | LOW | P2 |
| Retrieval-corpus RAG (Advisor Pro) | HIGH | VERY HIGH | P3 |
| Multi-turn conversation | LOW | HIGH | P3 |
| Default disk cache | LOW | MEDIUM | P3 (opt-in only) |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Sources

- [EventStudy test statistic explanations — eventstudytools.com](https://www.eventstudytools.com/significance-tests)
- [Interpreting CAAR and Patell Z — eventstudytools.com](https://www.eventstudytools.com/interpreting-caar-and-patell-z)
- [AAR & CAAR Statistics — eventstudy.de](https://eventstudy.de/docs/aar-caar-statistics)
- [fdars Python package with advisor layer — PyPI](https://pypi.org/project/fdars/0.9.0/)
- [Claude Code Agent Skills documentation](https://code.claude.com/docs/en/skills)
- [Claude Code Skill Anatomy — claudehasskills.com](https://claudehasskills.com/skill-anatomy/)
- [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html)
- [R Packages (2e) — Dependencies in Practice](https://r-pkgs.org/dependencies-in-practice.html)
- [httr2 retry documentation](https://httr2.r-lib.org/reference/req_retry.html)
- [HTTP testing in R — Graceful HTTP packages](https://books.ropensci.org/http-testing/graceful.html)
- [7 LLM Guardrails That Reduce Hallucinations — Medium](https://medium.com/@ThinkingLoop/7-llm-guardrails-that-reduce-hallucinations-3d673677fb3f)
- [Watchdogs and Oracles: Runtime Verification for LLMs — arXiv](https://arxiv.org/pdf/2511.14435)
- [Evidence-based Text Generation — arXiv](https://arxiv.org/pdf/2508.15396)
- [Parametric and Nonparametric Event Study Tests: A Review — CCSENET](https://ccsenet.org/journal/index.php/ibr/article/download/38913/23293)
- Kolari, J. and Pynnönen, S. (2010). "Event study testing with cross-sectional correlation due to partially overlapping event windows." *Review of Financial Studies*, 23(11), 3996–4025.
- Boehmer, E., Musumeci, J. and Poulsen, A.B. (1991). "Event study methodology under conditions of event-induced variance." *Journal of Financial Economics*, 30(2), 253–272.
- MacKinlay, A.C. (1997). "Event studies in economics and finance." *Journal of Economic Literature*, 35(1), 13–39.

---

*Feature research for: Grounded AI Advisor — EventStudy v0.60.0*
*Researched: 2026-09-02*
