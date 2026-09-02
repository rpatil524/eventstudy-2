# Architecture Research: Grounded AI Advisor Integration

**Domain:** LLM-agnostic advisory layer over a mature CRAN R package
**Researched:** 2026-09-02
**Confidence:** HIGH (all findings derived directly from codebase inspection; no external inference)

---

## Standard Architecture

### System Overview

The advisor is a two-layer addendum that sits entirely above the existing pipeline and reads from it — it never modifies the pipeline's internals.

```
┌──────────────────────────────────────────────────────────────────────┐
│                         EXISTING PIPELINE (unchanged)                 │
│  run_event_study() → prepare_event_study() → fit_model()            │
│                     → calculate_statistics()                          │
│  EventStudyTask  |  ParameterSet  |  ModelBase subclasses           │
│  TestStatisticBase subclasses  |  diagnostics.R  |  contract.R      │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │  read-only access (no mutation)
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    LAYER 1: Offline Diagnostics                       │
│  es_diagnostics(task)  →  list with class "es_diagnostics"          │
│  R/advisor_diagnostics.R  (pure base R, zero new deps)              │
│                                                                      │
│  Sources pulled:                                                     │
│  ├── task$data_tbl$model[[i]]$is_fitted          (contract.R)       │
│  ├── task$data_tbl$model[[i]]$statistics         (models.R)         │
│  ├── model_diagnostics(task)                     (diagnostics.R)    │
│  ├── pretrend_test(task)                          (diagnostics.R)    │
│  ├── task$aar_caar_tbl (CSectT / PatellZ / BMP)  (execute.R)       │
│  └── single-event AR/CAR columns in task$data_tbl                   │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │  serializable named list (no R6)
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    LAYER 2: Grounded Advise                          │
│  es_advise(diagnostics, task=, provider=, model=, task_type=)       │
│  R/advisor_advise.R                                                  │
│                                                                      │
│  ┌──────────────────────┐   ┌───────────────────────────────────┐   │
│  │  Grounding Guard     │   │  Provider abstraction (R6)        │   │
│  │  .validate_grounding │   │  AdvisorProvider (base)           │   │
│  │  checks every        │   │  ├── AnthropicProvider            │   │
│  │  evidence key        │   │  ├── OpenAICompatibleProvider     │   │
│  │  against diagnostics │   │  └── CustomProvider               │   │
│  │  before returning    │   │  R/advisor_provider.R             │   │
│  └──────────────────────┘   └───────────────────────────────────┘   │
│                                                                      │
│  Knowledge base (curated, bundled, no API):                         │
│  R/advisor_knowledge.R  (assumption→test map, academic refs)        │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │
                          ┌────────┴────────┐
                          ▼                 ▼
              Advice object (S3)     generate_report()
              print.es_advice()      feeds narrative
              class "es_advice"      section (report.R
                                     unchanged)
```

---

## Component Responsibilities

| Component | Responsibility | New / Modified | File |
|-----------|----------------|----------------|------|
| `es_diagnostics()` | Harvest all computable signals from a fitted task into a serializable named list | NEW | `R/advisor_diagnostics.R` |
| `es_advise()` | Build prompt, call provider, run grounding guard, return Advice S3 object | NEW | `R/advisor_advise.R` |
| `AdvisorProvider` R6 base | Abstract interface: `call(prompt, system_prompt, model)` | NEW | `R/advisor_provider.R` |
| `AnthropicProvider` | Native Anthropic Messages API via `httr2` | NEW | `R/advisor_provider.R` |
| `OpenAICompatibleProvider` | OpenAI-compatible endpoint (also covers Ollama, Mistral, Azure) | NEW | `R/advisor_provider.R` |
| `CustomProvider` | User-supplied function hook | NEW | `R/advisor_provider.R` |
| `.resolve_provider()` | 3-tier config precedence (arg → env → default) | NEW (@noRd) | `R/advisor_provider.R` |
| `.validate_grounding()` | Runtime guard: rejects Advice whose evidence keys are absent from diagnostics | NEW (@noRd) | `R/advisor_advise.R` |
| Grounding knowledge base | Curated assumption→test mappings, academic citations | NEW | `R/advisor_knowledge.R` |
| `print.es_advice()` | S3 print method consistent with `print.es_simulation`, `print.es_cross_sectional` | NEW | `R/advisor_advise.R` |
| `generate_report()` | Accepts optional `advice=` argument; splices grounded narrative into report | MODIFIED | `R/report.R` |
| `DESCRIPTION` | Add `httr2`, `jsonlite` to Suggests | MODIFIED | `DESCRIPTION` |
| `EventStudy-package.R` | Add new exported names to globalVariables() if needed | MODIFIED | `R/EventStudy-package.R` |
| `SKILL.md` | Claude Code Agent Skill orchestrating load→diagnose→advise→re-run loop | NEW | `.claude/skills/eventstudy-advisor/SKILL.md` |

**Unchanged:** `R/execute.R`, `R/models.R`, `R/models_time_varying.R`, `R/contract.R`, `R/task.R`, `R/parameter_set.R`, `R/diagnostics.R` (called from new code, never modified), all test statistics files, `R/plotting.R`, `R/export.R`.

---

## Recommended File Layout

```
R/
├── advisor_diagnostics.R   # es_diagnostics() — pure base R, no new deps
├── advisor_provider.R      # AdvisorProvider R6 hierarchy + .resolve_provider()
├── advisor_knowledge.R     # Curated knowledge base (assumption→test, refs)
├── advisor_advise.R        # es_advise() + .validate_grounding() + print.es_advice()
│
│   (existing, unchanged)
├── contract.R
├── diagnostics.R
├── execute.R
├── models.R
├── report.R                # MODIFIED: optional advice= param added
└── ...

.claude/skills/
└── eventstudy-advisor/
    └── SKILL.md            # Agent Skill surface
```

### Structure Rationale

One file per responsibility layer, strictly ordered by dependency. `advisor_diagnostics.R` has no dependency on any of the other new files. `advisor_knowledge.R` has no dependency on providers or advise. `advisor_provider.R` depends on `httr2`/`jsonlite` (Suggests-guarded). `advisor_advise.R` depends on all three. This ordering makes each layer independently testable and mirrors how the existing codebase separates concerns (`diagnostics.R` is independent of `execute.R`).

---

## Question-by-Question Integration Design

### (1) What es_diagnostics() Reads and Its Output Shape

`es_diagnostics(task)` accepts a fitted `EventStudyTask` (after `calculate_statistics()`) and pulls from four sources:

**Source A — Contract signals from `task$data_tbl$model` (R/contract.R, R/models.R):**
Each model object exposes `model$is_fitted` (active binding → `private$.is_fitted`), `model$statistics$sigma`, `model$statistics$degree_of_freedom`, `model$statistics$first_order_auto_correlation`, `model$statistics$residuals`, `model$statistics$r2` (where populated). The advisor reads these with a `purrr::map` over `task$data_tbl`, exactly as `model_diagnostics()` does in `R/diagnostics.R` lines 22-87.

**Source B — Existing diagnostic tests (R/diagnostics.R):**
Call `model_diagnostics(task)` to get the tibble of `{event_id, firm_symbol, is_fitted, shapiro_p, dw_stat, ljung_box_p, acf1, sigma, r2}`. Call `pretrend_test(task)` to get the pre-trend F-test results. These are already-written, already-tested functions — `es_diagnostics()` delegates to them rather than reimplementing.

**Source C — Test statistic results from task$data_tbl and task$aar_caar_tbl (R/execute.R):**
Single-event AR/CAR columns live as named columns on `task$data_tbl` after `calculate_statistics()`. Multi-event results live in `task$aar_caar_tbl` — a grouped tibble where each row's statistic column holds a tibble (e.g., `CSectT` column holds a tibble with `{relative_index, aar, caar, aar_t, caar_t, n_events, car_window}`). `es_diagnostics()` unnests these and summarises: peak AAR, peak CAAR, day-0 t-statistic, max p-value across the event window, n_events, fraction of events with `is_fitted = FALSE`.

**Source D — Parameter-level context (R/parameter_set.R):**
The ParameterSet object is not stored on the task — the task carries results, not configuration. `es_diagnostics()` should accept an optional `parameter_set=` argument to capture model name, test statistic names, and degenerate mode for inclusion in the diagnostics list. These become metadata fields.

**Output shape — a named list with class `"es_diagnostics"`:**

```r
# Produced by es_diagnostics(task, parameter_set = NULL)
list(
  # Metadata (for grounding key → value validation)
  meta = list(
    n_events         = integer,       # total events in task$data_tbl
    n_fitted         = integer,       # events where is_fitted = TRUE
    n_degenerate     = integer,       # events where is_fitted = FALSE
    model_name       = character,     # from parameter_set$return_model$model_name or NA
    stat_names       = character[],   # multi-event stat names or character(0)
    return_calc      = character,     # "SimpleReturn" / "LogReturn" / NA
    degenerate_mode  = character      # "lenient" / "strict"
  ),

  # Per-event model diagnostics (from model_diagnostics())
  model_diag = tibble,  # columns: event_id, firm_symbol, is_fitted,
                        # shapiro_p, dw_stat, ljung_box_p, acf1, sigma, r2

  # Aggregate model fit summary (scalars for grounding)
  fit_summary = list(
    mean_r2          = numeric,
    min_r2           = numeric,
    mean_sigma       = numeric,
    frac_ac_flagged  = numeric,  # fraction with |acf1| > 0.2
    frac_normality_rejected = numeric  # fraction with shapiro_p < 0.05
  ),

  # Pre-trend test (from pretrend_test())
  pretrend = tibble,    # columns: group, n_pre_periods, n_events,
                        # mean_pre_ar, sd_pre_ar, t_stat, p_value

  # Multi-event test statistic summaries (from task$aar_caar_tbl)
  # One entry per group × stat_name
  aar_caar = list(
    # keyed by group
    "<group>" = list(
      "<stat_name>" = list(
        day0_aar       = numeric,
        day0_aar_t     = numeric,
        day0_caar      = numeric,
        day0_caar_t    = numeric,
        peak_aar       = numeric,
        peak_aar_day   = integer,
        n_events       = integer,
        full_table     = tibble   # full unnested result for reference
      )
    )
  ),

  # Single-event CAR summary (from task$data_tbl AR/CAR columns)
  car_summary = list(
    mean_car         = numeric,
    sd_car           = numeric,
    frac_positive    = numeric,
    n_events_with_ar = integer
  ),

  # Contract signals (direct from model$is_fitted flags)
  contract = list(
    any_degenerate        = logical,
    degenerate_event_ids  = character[],  # event_ids where is_fitted = FALSE
    zero_variance_flagged = logical,      # inferred from sigma == 0 or NA
    na_fraction           = numeric       # fraction of AR values that are NA
  ),

  # Serialisation timestamp
  computed_at = character  # format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)
```

All scalar values use base R types only (no R6, no S3 subobjects except tibbles). The list is JSON-serialisable via `jsonlite::toJSON(diagnostics, auto_unbox = TRUE)` when `jsonlite` is available — useful for caching, logging, and testing. The `full_table` fields can be excluded for JSON export. Every key at every nesting level has a stable, documented name — this is the reference surface for the grounding guard.

The function signature:

```r
es_diagnostics <- function(task, parameter_set = NULL) {
  # Validates task inherits "EventStudyTask"
  # Validates "model" column exists in task$data_tbl
  # All computation is pure base R + existing package functions
  # Returns named list with class c("es_diagnostics", "list")
}
```

---

### (2) Provider Abstraction: R6 Class Hierarchy

**Decision: R6 class hierarchy with `AdvisorProvider` base, matching the codebase's established convention.**

**Rationale:** The existing codebase uses R6 for every polymorphic abstraction with a common interface: `ModelBase` → `MarketModel`/`GARCHModel`/etc.; `TestStatisticBase` → `CSectTTest`/`PatellZTest`/etc.; `ReturnCalculation` → `SimpleReturn`/`LogReturn`. The strategy pattern via R6 is the codebase's only polymorphism mechanism. Provider dispatch follows the exact same shape: a base class defines the interface; concrete subclasses implement it; a factory/resolver function selects the concrete instance. Using closure-based dispatch instead would be inconsistent with every other extensibility point in the package and would make it harder for users to inspect which provider is active via `inherits()`, which is the existing idiom (e.g., `inherits(obj, "ModelBase")` is used throughout).

**Design:**

```r
# R/advisor_provider.R

AdvisorProvider <- R6Class("AdvisorProvider",
  public = list(
    provider_name = "",
    # @param prompt  character(1) — user/content message
    # @param system_prompt character(1) — system/grounding context
    # @param model character(1) — LLM model identifier
    # @return character(1) — raw text response
    call = function(prompt, system_prompt = "", model = NULL) {
      stop("AdvisorProvider$call() is abstract", call. = FALSE)
    }
  )
)

AnthropicProvider <- R6Class("AnthropicProvider",
  inherit = AdvisorProvider,
  public = list(
    provider_name = "anthropic",
    initialize = function(api_key = NULL, base_url = "https://api.anthropic.com/v1") {
      # api_key: NULL → read ANTHROPIC_API_KEY env var at call time (never stored in pkg)
      private$.api_key_source <- if (!is.null(api_key)) "arg" else "env"
      private$.base_url <- base_url
    },
    call = function(prompt, system_prompt = "", model = "claude-opus-4-5") {
      # requireNamespace("httr2") + requireNamespace("jsonlite") checks here
      # Uses Anthropic Messages API: POST /messages
      # system_prompt → system parameter; prompt → user message content
    }
  ),
  private = list(.api_key_source = "env", .base_url = NULL)
)

OpenAICompatibleProvider <- R6Class("OpenAICompatibleProvider",
  inherit = AdvisorProvider,
  public = list(
    provider_name = "openai_compatible",
    initialize = function(api_key = NULL,
                          base_url = "https://api.openai.com/v1",
                          default_model = "gpt-4o") {
      # Covers: OpenAI, Ollama (http://localhost:11434/v1), Mistral, Azure OAI
      # api_key NULL → reads OPENAI_API_KEY env var; Ollama typically needs no key
    },
    call = function(prompt, system_prompt = "", model = NULL) {
      # POST /chat/completions with messages = [{role:"system",...},{role:"user",...}]
    }
  ),
  private = list(.api_key_source = "env", .base_url = NULL, .default_model = NULL)
)

CustomProvider <- R6Class("CustomProvider",
  inherit = AdvisorProvider,
  public = list(
    provider_name = "custom",
    initialize = function(fn) {
      # fn: function(prompt, system_prompt, model) → character(1)
      if (!is.function(fn)) stop("fn must be a function", call. = FALSE)
      private$.fn <- fn
    },
    call = function(prompt, system_prompt = "", model = NULL) {
      private$.fn(prompt, system_prompt, model)
    }
  ),
  private = list(.fn = NULL)
)
```

The `CustomProvider` hook gives users a zero-friction escape hatch for self-hosted or proprietary endpoints without requiring a new subclass.

**Provider resolution (`.resolve_provider()` @noRd):**

```r
.resolve_provider <- function(provider = NULL, model = NULL) {
  # 3-tier precedence: arg → env var → default
  # Tier 1: explicit R6 object or string tag passed as arg
  if (inherits(provider, "AdvisorProvider")) return(provider)
  if (is.character(provider)) {
    return(.build_provider_from_tag(provider, model))
  }
  # Tier 2: environment variables
  if (nchar(Sys.getenv("ANTHROPIC_API_KEY")) > 0)
    return(AnthropicProvider$new())
  if (nchar(Sys.getenv("OPENAI_API_KEY")) > 0)
    return(OpenAICompatibleProvider$new())
  # Tier 3: no key available — offline-only mode (return NULL; es_advise errors clearly)
  NULL
}
```

This mirrors `.resolve_degenerate_mode()` in `R/contract.R` lines 51-61 — the same precedence pattern (argument → option → default) is already the codebase's convention for configuration resolution.

---

### (3) Grounding Guard Placement and Mechanics

**Placement:** Inside `es_advise()`, after the LLM response is parsed, before the `Advice` object is returned. The guard is `.validate_grounding(advice_raw, diagnostics)` — a private @noRd function in `R/advisor_advise.R`.

**Why here and not at the prompt level:** The system prompt instructs the LLM to cite only keys from the diagnostics, but a prompt constraint alone cannot prevent hallucination. The guard operates on the parsed response and provides a deterministic, testable contract — analogous to how `model_diagnostics()` wraps every computation in `tryCatch` rather than assuming `shapiro.test` won't fail.

**What the guard checks:**

The `Advice` schema includes a `recommendations` list where each recommendation has an `evidence` field — a named list of `{key: character, value: numeric_or_character}` pairs citing specific diagnostic values. The guard:

1. Flattens the diagnostics list into a flat key→value lookup (using a helper `.flatten_diagnostics(diag)` that produces a character vector of dotted paths, e.g. `"fit_summary.mean_r2"`, `"meta.n_events"`, `"contract.any_degenerate"`).
2. For each evidence entry in the parsed advice, checks that the cited `key` exists in the flat lookup.
3. Optionally checks that the cited `value` is within a configurable tolerance of the actual diagnostic value (default: numeric within 5% or exact match for character).
4. If any evidence entry fails: either drops that recommendation with a warning (lenient) or stops with an error (strict) — reusing the `mode` concept from `contract.R`.

```r
.validate_grounding <- function(advice_raw, diagnostics, mode = "lenient") {
  flat_diag <- .flatten_diagnostics(diagnostics)
  # advice_raw$recommendations is a list of recommendation objects
  # each has advice_raw$recommendations[[i]]$evidence = list of {key, value}
  valid_recs <- purrr::keep(advice_raw$recommendations, function(rec) {
    all(purrr::map_lgl(rec$evidence, function(ev) {
      cited_key <- ev$key
      if (!cited_key %in% names(flat_diag)) {
        msg <- paste0("Grounding guard: evidence key '", cited_key,
                      "' not found in diagnostics")
        if (mode == "strict") stop(msg, call. = FALSE)
        warning(msg, call. = FALSE)
        return(FALSE)
      }
      TRUE
    }))
  })
  advice_raw$recommendations <- valid_recs
  advice_raw
}
```

The guard runs in pure base R + purrr (already an Import) — no LLM call is needed for validation. This makes the guard independently unit-testable without a provider.

**Key structural rule:** The flat diagnostics key space is the source of truth. `es_diagnostics()` is responsible for producing it deterministically; the guard is responsible for enforcing that the LLM's output references only keys that exist in it. Neither has knowledge of the other — they communicate only through the `diagnostics` list and the key-space contract.

---

### (4) The Advice S3 Object

**Decision: S3 list with class `"es_advice"` and a `print.es_advice()` method, consistent with `print.es_cross_sectional` (R/cross_sectional.R:182) and `print.es_simulation` (R/simulation.R:146).**

The existing pattern: `cross_sectional_regression()` returns `structure(list(...), class = "es_cross_sectional")`, then a standalone `print.es_cross_sectional()` function is exported. `simulate_event_study()` uses `class(result) <- "es_simulation"` then a standalone `print.es_simulation()`. The advisor follows the same idiom — no R6 for result objects, only for providers.

**Schema:**

```r
# Internal structure of es_advice return value
structure(
  list(
    task_type     = character,   # "interpret" | "recommend_stat" | "recommend_model"
                                 # | "flag_robustness" | "design_discussion"
                                 # | "report_writing"
    summary       = character,   # 1-3 sentence overall interpretation
    recommendations = list(      # ordered list
      list(
        text      = character,   # human-readable recommendation
        evidence  = list(        # grounding citations (validated by guard)
          list(key = "fit_summary.mean_r2", value = 0.43)
        ),
        priority  = character,   # "high" | "medium" | "low"
        reference = character    # academic citation or NA
      )
      # ...
    ),
    caveats       = character[], # free-text robustness warnings
    citations     = character[], # BibTeX keys or formatted refs from knowledge base
    provider_used = character,   # provider_name of the AdvisorProvider used
    model_used    = character,   # LLM model identifier
    grounding_passed = logical,  # TRUE if all evidence keys validated
    computed_at   = character
  ),
  class = c("es_advice", "list")
)
```

**Print method:**

```r
#' @export
print.es_advice <- function(x, ...) {
  cat("EventStudy AI Advisor\n")
  cat("  Task type:  ", x$task_type, "\n")
  cat("  Provider:   ", x$provider_used, "/", x$model_used, "\n")
  cat("  Grounding:  ", if (x$grounding_passed) "PASSED" else "PARTIAL", "\n\n")
  cat("Summary:\n")
  cat(" ", x$summary, "\n\n")
  cat("Recommendations:\n")
  for (i in seq_along(x$recommendations)) {
    rec <- x$recommendations[[i]]
    cat(sprintf("  [%s] %s\n", toupper(rec$priority), rec$text))
    if (length(rec$evidence) > 0) {
      ev_str <- paste(purrr::map_chr(rec$evidence,
                                     ~paste0(.x$key, "=", .x$value)),
                      collapse = ", ")
      cat("      Evidence:", ev_str, "\n")
    }
  }
  if (length(x$caveats) > 0) {
    cat("\nCaveats:\n")
    for (cv in x$caveats) cat(" -", cv, "\n")
  }
  invisible(x)
}
```

---

### (5) Conversational Modes and Report-Writing Integration

**Design decision: All modes flow through `es_advise()` via the `task_type` argument. The function is not overloaded into separate entry points.**

The `task_type` parameter controls which system prompt fragment and knowledge base entries are injected:

| task_type | Behaviour |
|-----------|-----------|
| `"interpret"` (default) | Interpret current results; cites day-0 AAR, t-stats, model fit |
| `"recommend_stat"` | Recommend which test statistic to use given n_events, distribution |
| `"recommend_model"` | Recommend return model and window lengths given data characteristics |
| `"flag_robustness"` | Focus on contract signals, autocorrelation, pre-trend, degenerate events |
| `"design_discussion"` | Interactive: LLM asks clarifying questions before recommending model/window; conversational — caller loops `es_advise()` multiple times with accumulated `context=` |
| `"report_writing"` | Produce a grounded narrative paragraph suitable for injection into `generate_report()` |

The `design_discussion` mode is the only stateful one: the caller (the Agent Skill or user code) accumulates an optional `context` character vector and passes it back on successive calls. `es_advise()` itself is stateless — it receives the full context each time. This avoids any session state in the R package and is consistent with how R6 models are deep-cloned rather than mutated.

**Report-writing integration with `generate_report()`:**

```r
# User workflow:
advice <- es_advise(diag, task_type = "report_writing", provider = "anthropic")
generate_report(task, advice = advice, sections = c("summary", "diagnostics", ...))
```

`generate_report()` is modified minimally: one new optional parameter `advice = NULL`. When non-NULL, it passes `advice$summary` and the formatted recommendations as a `params$advice_narrative` variable to the RMarkdown template. The template already uses parameterized rendering via `rmarkdown::render(params = list(...))` (report.R lines 86-103). The Rmd template gains an optional section that renders `params$advice_narrative` if non-NULL. No structural change to `generate_report()` — one new param, template gets a guarded section.

---

### (6) File Layout and Build Order

The build order respects the strict dependency chain: each phase depends only on what the previous phase produced.

**Phase 1 — Offline Diagnostics (zero external deps)**

New file: `R/advisor_diagnostics.R`
- `es_diagnostics(task, parameter_set = NULL)` — exported
- `print.es_diagnostics()` — exported S3 method
- `summary.es_diagnostics()` — optional exported S3 method (scalar summary for human)
- `.flatten_diagnostics()` — @noRd internal

Reads from: `task$data_tbl`, `task$aar_caar_tbl`, `model_diagnostics()` (diagnostics.R), `pretrend_test()` (diagnostics.R), `task$data_tbl$model[[i]]$statistics` (models.R), `task$data_tbl$model[[i]]$is_fitted` (contract.R active binding).

No dependency on advisor_provider.R, advisor_advise.R, or advisor_knowledge.R. Testable with the existing mock data helpers (`helper-mock-data.R`) and no API key.

**Phase 2 — Provider Layer (httr2/jsonlite in Suggests)**

New file: `R/advisor_provider.R`
- `AdvisorProvider` R6 base class — exported
- `AnthropicProvider` R6 subclass — exported
- `OpenAICompatibleProvider` R6 subclass — exported
- `CustomProvider` R6 subclass — exported
- `.resolve_provider()` — @noRd
- `.build_provider_from_tag()` — @noRd

Depends on: `httr2` and `jsonlite` (both Suggests, `requireNamespace()`-guarded inside `call()`). No dependency on advisor_diagnostics.R or advisor_advise.R. Testable in isolation via `CustomProvider` with a mock function — no real API call required.

**Phase 3 — Knowledge Base (pure R, zero deps)**

New file: `R/advisor_knowledge.R`
- `.get_knowledge_base()` — @noRd, returns a named list of methodology texts and academic refs
- `assumption_test_map` — named character vector: assumption name → relevant diagnostic key(s)
- `academic_references` — named list of formatted citations (MacKinlay 1997, Brown & Warner 1985, Patell 1976, BMP 1991, Kolari-Pynnönen 2010, etc.)

This is a pure data file. No functions to call, no deps. Can be written once and extended. It serves as the grounded system-prompt context injected into `es_advise()`.

**Phase 4 — Advise Layer + Grounding Guard**

New file: `R/advisor_advise.R`
- `es_advise(diagnostics, task = NULL, provider = NULL, model = NULL, task_type = "interpret", context = character(), mode = "lenient")` — exported
- `print.es_advice()` — exported S3 method
- `.validate_grounding()` — @noRd
- `.build_system_prompt()` — @noRd (assembles system prompt from knowledge base + diagnostics schema)
- `.build_user_prompt()` — @noRd (assembles user message from diagnostics values + task_type)
- `.parse_llm_response()` — @noRd (JSON parse of structured LLM output + fallback)

Depends on: advisor_diagnostics.R (for `es_diagnostics` class check and `.flatten_diagnostics`), advisor_provider.R (for `AdvisorProvider` base class and `.resolve_provider()`), advisor_knowledge.R (for knowledge base). This is the last R/ file added — all dependencies are already built.

**Phase 5 — Report Integration**

Modified file: `R/report.R` — add `advice = NULL` parameter, pass to render params.
Modified file: `DESCRIPTION` — add `httr2`, `jsonlite` to Suggests.
Modified file: `R/EventStudy-package.R` — add any new globalVariables() entries if NSE warnings appear.

**Phase 6 — Agent Skill**

New file: `.claude/skills/eventstudy-advisor/SKILL.md`
Orchestration script describing the advise loop: load data → `run_event_study()` → `es_diagnostics()` → `es_advise()` → inspect → optionally modify ParameterSet → re-run → compare. References `es_advise()` task types, explains provider config, and documents the waitlist pointer for Advisor Pro.

---

### (7) Integration Points and What Stays Unchanged

**Integration points (read-only access into existing code):**

| New code reads | Existing symbol | Location | Read pattern |
|---------------|-----------------|----------|--------------|
| `task$data_tbl` | `EventStudyTask` public field | `R/task.R` | Direct field access, no mutation |
| `task$data_tbl$model[[i]]$is_fitted` | `ModelBase` active binding | `R/models.R:57` | Loop over `task$data_tbl`, read `is_fitted` |
| `task$data_tbl$model[[i]]$statistics` | `ModelBase` active binding | `R/models.R:39` | Loop, read `statistics$sigma`, `$r2`, `$residuals`, etc. |
| `model_diagnostics(task)` | Exported function | `R/diagnostics.R:13` | Delegate call, consume tibble output |
| `pretrend_test(task)` | Exported function | `R/diagnostics.R:104` | Delegate call, consume tibble output |
| `task$aar_caar_tbl` | `EventStudyTask` public field | `R/task.R:20` | Direct field access, unnest statistics column |
| `task$data_tbl$model[[i]]$statistics$r2` | `private$.statistics$r2` | `R/models.R:76` | Via the `$statistics` active binding |
| `.resolve_degenerate_mode()` | @noRd internal | `R/contract.R:51` | Pattern reference only — advisor replicates the precedence pattern, does not call this function |

**What is guaranteed to stay unchanged:**

- `run_event_study()`, `prepare_event_study()`, `fit_model()`, `calculate_statistics()` — signatures, behaviour on valid input, behaviour on degenerate input — no modification.
- All 13 return model classes (`ModelBase` and subclasses) — no modification.
- All test statistic classes (`TestStatisticBase` and subclasses) — no modification.
- `ParameterSet` — no modification (advisor does not add new fields to it; it reads existing ones).
- `R/diagnostics.R` — no modification (called by the new advisor, never modified).
- `R/contract.R` — no modification (advisor reads `is_fitted` via ModelBase's existing active binding).
- The 1378-test existing suite — all tests must remain green; the advisor adds no observable side effects to the pipeline.
- `R CMD check` — the offline layer adds zero new hard dependencies; only Suggests grow.

---

## Architectural Patterns

### Pattern 1: Strategy via R6 Inheritance (Provider Abstraction)

**What:** `AdvisorProvider` base defines `call(prompt, system_prompt, model)` as abstract; concrete subclasses implement HTTP dispatch per vendor. Caller holds an `AdvisorProvider` reference and calls `provider$call()` polymorphically.

**When to use:** Whenever there are 2+ interchangeable implementations of the same interface. This is the only polymorphism mechanism in this codebase (all models, all test statistics, all return calculations use it). Using anything else here would be a convention break.

**Trade-offs:** More boilerplate than closures; gains `inherits()` inspection, `print()` dispatch, and easy extension without modifying `es_advise()`.

### Pattern 2: Pure Serializable Diagnostic Object

**What:** `es_diagnostics()` returns a plain named list (not an R6 object) so it can be serialized to JSON, written to disk, logged, and tested without the R6 runtime. The provider layer and advise layer only consume this list — they do not depend on the full `EventStudyTask` R6 object.

**When to use:** Whenever the output of a computation needs to cross a process, session, or test boundary. The diagnostics list is the "currency" that the LLM layer operates on. By keeping it as a plain list, it can be created in one R session, saved, and fed to `es_advise()` in another — useful for caching expensive diagnostic runs and for testing the advisor without a full pipeline run.

**Trade-offs:** No method dispatch on the list (only S3 print/summary methods); adding new diagnostic fields requires manual doc updates rather than class evolution. Acceptable because the diagnostics schema is intentionally stable and versioned.

### Pattern 3: Two-Layer Grounding (Prompt + Runtime Guard)

**What:** System prompt instructs the LLM to cite only keys from the diagnostics. The runtime guard `.validate_grounding()` independently verifies the output. Neither layer trusts the other.

**When to use:** Whenever LLM output is presented to users as factual. Prompt alone is insufficient; guard alone cannot prevent bad data from reaching the LLM. Both are needed.

**Trade-offs:** Grounding guard can reject valid but oddly-formatted LLM output if evidence keys don't match exactly — requires the system prompt's key schema to be precisely consistent with `es_diagnostics()` output structure. Mitigated by generating the key schema from `.flatten_diagnostics()` dynamically at prompt-build time.

### Pattern 4: Lenient/Strict Mode Reuse

**What:** `es_advise()` accepts a `mode` argument that propagates to `.validate_grounding()`, following the exact same "lenient drops with warning, strict stops with error" contract established in `R/contract.R`.

**When to use:** Whenever the package has a new code path that can fail in a recoverable way. Consistent use of this pattern means users who are already familiar with `ParameterSet(degenerate_handling = "strict")` will immediately understand `es_advise(mode = "strict")`.

---

## Data Flow

### Advisor Flow (Happy Path)

```
task (fitted EventStudyTask)
    │
    ▼  es_diagnostics(task, parameter_set)
named list "es_diagnostics"
    │  (serializable, no R6)
    ├──→ optionally saved to disk / logged / tested standalone
    │
    ▼  es_advise(diagnostics, task_type = "interpret", provider = "anthropic")
         │
         ├── .resolve_provider("anthropic")   → AnthropicProvider$new()
         ├── .flatten_diagnostics(diagnostics) → flat key→value map
         ├── .get_knowledge_base()             → assumption→test map + refs
         ├── .build_system_prompt(flat_keys, knowledge_base, task_type)
         ├── .build_user_prompt(diagnostics, task_type)
         ├── provider$call(user_prompt, system_prompt, model)
         │       └── httr2 POST → LLM API → JSON response
         ├── .parse_llm_response(raw_text)    → advice_raw list
         ├── .validate_grounding(advice_raw, diagnostics, mode)
         │       └── drops/errors on ungrounded evidence keys
         └── structure(advice_raw, class = c("es_advice", "list"))
                 │
                 ▼  print.es_advice(x)
                 Human-readable output
```

### Report-Writing Sub-Flow

```
es_advise(diagnostics, task_type = "report_writing", ...)
    → es_advice object with summary = "grounded narrative paragraph"
         │
         ▼  generate_report(task, advice = advice, ...)
         rmarkdown::render(params = list(..., advice_narrative = advice$summary))
         → HTML/PDF with grounded interpretation section
```

### Design Discussion Sub-Flow (Stateless Multi-Turn)

```
# Turn 1
diag <- es_diagnostics(task)
advice1 <- es_advise(diag, task_type = "design_discussion")
# LLM asks: "What is your hypothesis about the event effect?"

# Turn 2 — caller appends user response to context
context <- c(format(advice1), "User: I expect a 2-day drift effect")
advice2 <- es_advise(diag, task_type = "design_discussion", context = context)
# LLM recommends specific window + model given context
```

No session state in the package — context is accumulated by the caller (the Agent Skill or user script).

---

## Anti-Patterns

### Anti-Pattern 1: Modifying the Existing Pipeline for the Advisor

**What people do:** Add an `advice_tbl` field to `EventStudyTask`, or add advisor logic inside `calculate_statistics()`.

**Why it's wrong:** The advisor is additive; the pipeline must remain unchanged for the 1378 existing tests to stay green. Any mutation of the pipeline introduces regression risk and violates the constraint "behavior on valid inputs must not change."

**Do this instead:** `es_diagnostics()` reads from the task; it does not write to it. The advisor is a pure consumer.

### Anti-Pattern 2: Storing API Keys in the Package

**What people do:** Add `api_key = getOption("EventStudy.api_key")` as a package option read at load time.

**Why it's wrong:** Keys stored as package options appear in `options()` output, can be accidentally logged, and persist across R sessions. CRAN does not permit packages that store credentials.

**Do this instead:** `AnthropicProvider$call()` reads `Sys.getenv("ANTHROPIC_API_KEY")` at call time, inside the function body, and never stores the value. The key is never assigned to any R variable that outlives the call stack.

### Anti-Pattern 3: Hard-Coding the Diagnostics Key Schema in the Guard

**What people do:** Write `.validate_grounding()` with a hard-coded list of valid key names.

**Why it's wrong:** The key schema is defined by `es_diagnostics()` output. Hard-coding it in the guard creates two sources of truth that will diverge when the diagnostics schema evolves.

**Do this instead:** `.validate_grounding(advice_raw, diagnostics)` calls `.flatten_diagnostics(diagnostics)` dynamically at runtime, deriving the valid key set from the actual diagnostics object passed in. The guard is schema-agnostic.

### Anti-Pattern 4: Using Closures for Provider Dispatch

**What people do:** Define provider dispatch as a list of closures (e.g., `providers <- list(anthropic = function(prompt, ...) {...})`).

**Why it's wrong:** Inconsistent with codebase conventions where every pluggable abstraction is an R6 class. Makes `inherits()` checks impossible; makes provider inspection and printing inconsistent with how users inspect models and test statistics.

**Do this instead:** Use the R6 hierarchy defined above; let the existing `print()` S3 dispatch handle display.

---

## Integration Points Summary

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `es_diagnostics` → `ModelBase` | Reads `is_fitted`, `statistics` via active bindings | Read-only; no mutation |
| `es_diagnostics` → `diagnostics.R` | Calls `model_diagnostics()`, `pretrend_test()` | Delegate; reuse tested code |
| `es_diagnostics` → `task$aar_caar_tbl` | Reads the nested tibble column, unnests per statistic | Read-only |
| `es_advise` → `AdvisorProvider` | Calls `provider$call(prompt, sys, model)` | Strategy pattern; provider is injected |
| `es_advise` → `es_diagnostics` result | Consumes named list; no R6 | Serializable boundary |
| `AdvisorProvider$call` → LLM API | `httr2` POST, `jsonlite` parse | Both in Suggests; `requireNamespace()` guarded |
| `generate_report` → `es_advice` | Reads `advice$summary` as character string | Optional param; backwards-compatible |
| Agent Skill → exported functions | Calls `es_diagnostics()`, `es_advise()`, `run_event_study()` | Public API only |

---

## Sources

- Codebase inspection: `R/contract.R`, `R/diagnostics.R`, `R/models.R`, `R/execute.R`, `R/task.R`, `R/parameter_set.R`, `R/report.R`, `R/cross_sectional.R`, `R/simulation.R`, `R/export.R` — direct read, confidence HIGH
- Pattern reference: pyfda/fdars (github.com/sipemu/eventstudy) two-layer diagnostic+advise pattern — described in PROJECT.md context, confidence MEDIUM (not independently verified this session)
- R package conventions: CRAN policy on Suggests vs Imports, `requireNamespace()` guard pattern — confirmed in existing `DESCRIPTION` and usage in `report.R`, `export.R`, confidence HIGH

---

*Architecture research for: EventStudy v0.60.0 Grounded AI Advisor integration*
*Researched: 2026-09-02*
