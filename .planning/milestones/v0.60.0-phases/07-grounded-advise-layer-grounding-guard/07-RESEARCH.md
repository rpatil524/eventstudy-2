# Phase 7: Grounded Advise Layer + Grounding Guard — Research

**Researched:** 2026-09-04
**Domain:** R S3 object design, LLM structured-output JSON schema, runtime grounding guard, rmarkdown integration
**Confidence:** HIGH (primarily in-repo evidence; web research for JSON/S3 idioms only)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

1. **Guard failure mode = drop-and-keep.** Drop only the ungrounded recommendation, keep the rest, append a caveat noting N drops, emit exactly ONE `warning()`. Never `stop()`.
2. **recommend_stat / flag_robustness = KB grounds, LLM interprets.** Provider supplied → KB produces grounded recommendations+evidence; LLM adds prose. No provider → pure Phase 5 offline path.
3. **Structured output = provider `schema` arg → JSON matching the Advice contract.** Malformed/partial/empty JSON or any provider failure degrades to one warning + empty Advice. `jsonlite` is Suggests.
4. **Guard scope = structured evidence[] only (ADV-04 literal).** No prose numeric-token scanning.
5. **Zero new hard deps; LLM path optional (Suggests, requireNamespace-guarded); existing valid-input behavior byte-identical; existing tests stay green; no new R CMD check NOTEs/WARNINGs.**

### Claude's Discretion

Exact `diagnostic_key` path convention and tolerance constants; Advice/evidence internal representation (S3 list per ADV-01); prompt templates per task type; JSON schema passed to provider; print-method formatting; whether guard is one function or a small helper set. Guided by codebase conventions (snake_case public, leading-dot `@noRd` internal, testthat 3e) and Phase 5/6 contracts.

### Deferred Ideas (OUT OF SCOPE)

- Agent Skill orchestrating load→diagnose→advise→re-run→compare → Phase 8
- Retrieval-corpus (RAG) grounding, managed hosting → future waitlist-gated milestone
- Prose numeric-token scanning as a second guard layer — explicitly rejected
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADV-01 | `es_advise()` returns `Advice` S3 object with `interpretation`, `recommendations[]`, `caveats`, `print` method | §Standard Stack + §Advice S3 Design |
| ADV-02 | Each recommendation carries `action`, `kind`, `rationale`, `expected_effect`, `evidence[]` | §Advice S3 Design |
| ADV-03 | Each evidence entry is `{diagnostic_key, value, threshold, direction}` | §Grounding Guard Algorithm |
| ADV-04 | Runtime grounding guard rejects missing key / value mismatch beyond tolerance | §Grounding Guard Algorithm |
| ADV-05 | Six task types: interpret, recommend_stat, recommend_model, flag_robustness, design_discussion, report_writing | §Per-Task-Type Prompt Strategy |
| ADV-06 | Clear error when no provider/key for LLM-required task types | §Per-Task-Type Prompt Strategy |
| ADV-07 | report_writing consumed by `generate_report()` via `advice = NULL` + guarded template section | §generate_report Integration |
</phase_requirements>

---

## Summary

Phase 7 builds the `es_advise()` grounded interpretation layer on top of the Phase 5 offline diagnostics+KB and Phase 6 provider seam. The work is almost entirely in-repo: the contracts are already established and the main engineering challenge is the grounding guard algorithm and the clean wiring of the six task types.

The central insight is that `recommend_stat` and `flag_robustness` already produce grounded KB recommendations (`rules_matched` in `es_advice`). Phase 7 converts those into the new structured `evidence[]` form, then calls the provider for prose interpretation — a thin transformation, not a rewrite. For LLM-only task types (`interpret`, `recommend_model`, `design_discussion`, `report_writing`), the provider returns JSON matching the Advice contract directly; the guard then verifies every `evidence[]` entry.

The `Advice` S3 object is a plain named list (same idiom as `es_advice` and `es_provider_response`). The guard is a small set of `@noRd` helpers that resolves dotted key-paths into the six `es_diagnostics` sections. The `generate_report` integration adds one trailing param and one guarded Rmd chunk — zero changes to existing params.

**Primary recommendation:** Model `Advice` as a plain S3 list; use dotted-path `section.key[index]` as the `diagnostic_key` convention; implement the guard as three focused `@noRd` helpers; inject KB rules (minus `condition` closures) into the LLM system prompt for `recommend_stat`/`flag_robustness`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `Advice` S3 construction + `print.Advice` | R/advise.R (new file) | — | Keeps all es_advise logic in one file, matching es_diagnostics.R pattern |
| Grounding guard `.validate_grounding()` | R/advise.R (internal `@noRd`) | — | Guard is logically part of es_advise; needs direct access to the Advice list |
| Prompt building per task type | R/advise.R (internal `@noRd` helpers) | R/knowledge_base.R (data source) | Prompts are wiring logic, not KB data |
| KB injection into LLM prompt | R/advise.R calls `es_kb()` | R/knowledge_base.R (source) | `es_kb()` already exports the rules; Phase 7 is the consumer |
| `generate_report()` advice param | R/report.R (one new param + template) | inst/rmarkdown/…/skeleton.Rmd | Minimal surgical addition |
| Provider call | R/provider.R (existing Phase 6) | — | No changes needed to provider.R |

---

## Standard Stack

### Core (zero new hard deps — all already Imports or base R)

| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| R6 | existing | Provider R6 classes (ProviderBase hierarchy) | Imports — already wired |
| rlang | existing | `%||%` operator throughout | Imports — already wired |
| stats | base | Numeric tolerance via `.Machine$double.eps` | base |
| jsonlite | existing Suggests | Parse LLM JSON response + serialize diagnostics | Suggests — already in DESCRIPTION from Phase 6 |
| httr2 | existing Suggests | HTTP (used by providers, not by guard) | Suggests — already in DESCRIPTION from Phase 6 |

`[VERIFIED: R/provider.R:1-22]` — Phase 6 already placed `httr2` and `jsonlite` in Suggests with `requireNamespace()` guards. Phase 7 adds no new entries to DESCRIPTION.

### New R file

**`R/advise.R`** — single file containing:
- `es_advise()` public function (`@export`)
- `print.Advice` S3 method (`@export`)
- `.build_advice_object()` internal builder (`@noRd`)
- `.validate_grounding()` guard engine (`@noRd`)
- `.resolve_diag_key()` key-path resolver (`@noRd`)
- `.build_prompt()` per-task-type prompt assembler (`@noRd`)
- `.kb_to_evidence()` KB→evidence[] converter (`@noRd`)

### Package Legitimacy Audit

No new external packages are introduced. All dependencies are already present. Audit not required.

---

## Architecture Patterns

### System Architecture Diagram

```
es_advise(diagnostics, task_type, provider, model)
    │
    ├─[no provider, KB task types]─────────────────────────────────────────┐
    │   recommend_stat.es_diagnostics() / flag_robustness.es_diagnostics() │
    │   (existing Phase 5 path — unchanged)                                │
    │   returns es_advice S3 as before                                     │
    └──────────────────────────────────────────────────────────────────────┘
    │
    ├─[no provider, LLM-only task types]──► stop("No provider for task_type X", call.=FALSE)
    │
    └─[provider present]─────────────────────────────────────────────────┐
         │                                                                │
         ├─[recommend_stat / flag_robustness]                            │
         │   1. run KB (Phase 5) → rules_matched                        │
         │   2. .kb_to_evidence() → grounded recommendations+evidence[] │
         │   3. .build_prompt(task_type, diagnostics, kb_context)       │
         │   4. provider$complete(prompt, schema)                        │
         │   5. parse JSON → Advice list                                 │
         │   6. .validate_grounding(advice, diagnostics) [GUARD]        │
         │   7. return Advice S3                                         │
         │                                                               │
         └─[interpret / recommend_model / design_discussion /           │
            report_writing]                                              │
             1. .build_prompt(task_type, diagnostics)                   │
             2. provider$complete(prompt, schema)                        │
             3. parse JSON → Advice list                                 │
             4. .validate_grounding(advice, diagnostics) [GUARD]        │
             5. return Advice S3                                         │
                                                                        │
         On any JSON parse failure / provider NA:                       │
             .build_empty_advice(source_label) + warning() [one only]  │
```

### Recommended Project Structure

```
R/
├── advise.R            # NEW: es_advise(), print.Advice, all @noRd guards
├── advise_offline.R    # UNCHANGED (Phase 5)
├── knowledge_base.R    # UNCHANGED (Phase 5)
├── provider.R          # UNCHANGED (Phase 6)
├── report.R            # SURGICAL: +advice param, +guarded template call
inst/rmarkdown/templates/event_study_report/skeleton/
└── skeleton.Rmd        # SURGICAL: +one guarded chunk for advice section
tests/testthat/
└── test_advise.R       # NEW: deterministic guard regression tests
```

---

## Research Finding 1: Advice S3 Object Design

### Shape (compatible with es_advice and es_provider_response)

The `es_advice` S3 object (`advise_offline.R:221-229`) uses fields `source`, `is_deterministic`, `rules_matched`, `diagnostics_ref`. The `es_provider_response` uses `source`, `is_deterministic`, `text`, `error`. The new `Advice` S3 must share `source` and `is_deterministic` with both.

`[VERIFIED: R/advise_offline.R:221-229]` — verbatim structure:
```r
structure(
  list(
    source          = "offline_kb",
    is_deterministic = TRUE,
    rules_matched   = matched,
    diagnostics_ref = diag
  ),
  class = "es_advice"
)
```

The `Advice` S3 is a DIFFERENT class (`"Advice"`) from `"es_advice"`, holding the new structured contract. It does NOT replace `es_advice` — `es_advice` remains the offline path output.

**Concrete `Advice` structure:**

```r
structure(
  list(
    source           = "openai",           # provider label or "offline_kb"
    is_deterministic = FALSE,              # TRUE only on pure KB path
    task_type        = "recommend_stat",   # one of the six task types
    interpretation   = "...",              # character(1) — prose summary
    recommendations  = list(              # list of recommendation lists
      list(
        action          = "Use BMP test",
        kind            = "stat_choice",
        rationale       = "...",
        expected_effect = "...",
        evidence        = list(            # list of evidence lists
          list(
            diagnostic_key = "cross_sectional.car_iqr",
            value          = 0.142,
            threshold      = 0.10,
            direction      = "above"
          )
        )
      )
    ),
    caveats          = character(),        # character vector, may be empty
    n_dropped        = 0L                  # guard bookkeeping
  ),
  class = "Advice"
)
```

**Key design choices:**

1. **`recommendations` as a list-of-lists, NOT a data.frame.** The `evidence[]` sub-list has variable length per recommendation; a flat data.frame would require list-columns within a data.frame, adding complexity with no gain. `[ASSUMED]` — consistent with `rules_matched` in `es_advice` (`advise_offline.R:203-211`).

2. **`evidence[]` as a list-of-lists.** Each entry is `list(diagnostic_key, value, threshold, direction)` — all scalars, so they round-trip cleanly through `jsonlite::fromJSON(simplifyVector = FALSE)`. `[ASSUMED]` based on JSON idiom for variable-depth structures.

3. **JSON-serialization:** `jsonlite::toJSON(unclass(advice), auto_unbox = TRUE, null = "null")` works because all values are plain scalars, character vectors, or nested named lists. The `condition` closure problem (present in KB rules) does NOT apply here — `Advice` contains no functions.

4. **`print.Advice` pattern:** Follow `print.es_advice` (`advise_offline.R:145-169`) — `cat()` based, `invisible(x)` return.

**`print.Advice` sketch:**

```r
print.Advice <- function(x, ...) {
  cat("Event Study Advice\n")
  cat("==================\n")
  cat("Source:        ", x$source, "\n")
  cat("Task type:     ", x$task_type, "\n")
  cat("Deterministic: ", x$is_deterministic, "\n")
  n_recs <- length(x$recommendations)
  cat("Recommendations:", n_recs, "\n")
  if (!is.null(x$n_dropped) && x$n_dropped > 0L) {
    cat("[GUARD]", x$n_dropped, "recommendation(s) dropped as ungrounded.\n")
  }
  cat("\n")
  if (nzchar(x$interpretation %||% "")) {
    cat("Interpretation:\n ", x$interpretation, "\n\n")
  }
  for (i in seq_along(x$recommendations)) {
    r <- x$recommendations[[i]]
    cat(sprintf("[%d] %s\n", i, r$action))
    cat("    Kind:   ", r$kind, "\n")
    cat("    Effect: ", r$expected_effect, "\n")
    cat("    Evidence:\n")
    for (ev in r$evidence) {
      cat(sprintf("      %s = %s (threshold %s, %s)\n",
                  ev$diagnostic_key, ev$value, ev$threshold, ev$direction))
    }
    cat("\n")
  }
  if (length(x$caveats) > 0L) {
    cat("Caveats:\n")
    for (cv in x$caveats) cat(" -", cv, "\n")
  }
  invisible(x)
}
```

**Empty-recommendations edge case:** When `length(x$recommendations) == 0L`, the `for` loop body never executes — no special-casing needed.

---

## Research Finding 2: JSON Schema for Structured Output

### Schema definition

The `schema` arg to `provider$complete(prompt, schema)` is consumed by:
- **OpenAICompatProvider:** placed in `body$response_format$json_schema$schema` (`provider.R:471-478`)
- **AnthropicProvider:** placed in `body$tools[[1]]$input_schema` + `body$tool_choice` (`provider.R:629-638`)

`[VERIFIED: R/provider.R:471-478, 629-638]`

Both paths accept a plain R list representing a JSON Schema object. The schema must be a JSON Schema draft-7 compatible object.

**Advice schema (R list):**

```r
.advice_schema <- function() {
  list(
    type = "object",
    properties = list(
      interpretation = list(type = "string"),
      recommendations = list(
        type = "array",
        items = list(
          type = "object",
          properties = list(
            action          = list(type = "string"),
            kind            = list(type = "string"),
            rationale       = list(type = "string"),
            expected_effect = list(type = "string"),
            evidence = list(
              type = "array",
              items = list(
                type = "object",
                properties = list(
                  diagnostic_key = list(type = "string"),
                  value          = list(type = "number"),
                  threshold      = list(type = "number"),
                  direction      = list(type = "string",
                                        enum = list("above", "below", "equal", "na"))
                ),
                required = list("diagnostic_key", "value", "threshold", "direction")
              )
            )
          ),
          required = list("action", "kind", "rationale", "expected_effect", "evidence")
        )
      ),
      caveats = list(type = "array", items = list(type = "string"))
    ),
    required = list("interpretation", "recommendations", "caveats"),
    additionalProperties = FALSE
  )
}
```

**Note on `direction` values:** `"na"` is included for cases where a diagnostic key is NA in the data — the guard will catch the NA-vs-present mismatch regardless, but allowing `"na"` in the schema prevents the LLM from fabricating a direction string that breaks `enum` validation before the guard runs.

### JSON parsing from provider response

`provider$complete()` returns `es_provider_response` with `text` field containing raw JSON string (from `AnthropicProvider` via `.extract_anthropic_text()`, from `OpenAICompatProvider` via `choices[[1]]$message$content`). `[VERIFIED: R/provider.R:482, 505-535]`

**Robust parse pattern:**

```r
.parse_advice_json <- function(resp, source_label) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    warning("jsonlite required to parse LLM advice. Returning empty Advice.", call. = FALSE)
    return(.empty_advice(source_label))
  }
  if (is.na(resp$text) || !nzchar(resp$text %||% "")) {
    warning(sprintf("Provider '%s' returned no text. Returning empty Advice.", source_label),
            call. = FALSE)
    return(.empty_advice(source_label))
  }
  parsed <- tryCatch(
    jsonlite::fromJSON(resp$text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed) || !is.list(parsed)) {
    warning(sprintf("Provider '%s' returned malformed JSON. Returning empty Advice.", source_label),
            call. = FALSE)
    return(.empty_advice(source_label))
  }
  parsed
}
```

**JSON round-trip coercion traps:**

- `jsonlite::fromJSON(simplifyVector = TRUE)` (the default) collapses single-element arrays into scalars, breaking `recommendations[[1]]$evidence`. **Must use `simplifyVector = FALSE`.**
- Integer vs double: `jsonlite` will parse `"value": 5` as numeric `5.0` (double), not `5L`. The guard tolerance comparison is on doubles — this is fine.
- NA: JSON has no native `null`-as-NA mapping. If the LLM emits `"value": null`, `fromJSON` gives R `NULL`. The guard must coerce: `is.null(ev$value) || is.na(ev$value)` → treat as NA → mismatch.
- `[ASSUMED]` — JSON round-trip behavior of `jsonlite::fromJSON(simplifyVector = FALSE)`.

---

## Research Finding 3: Grounding Guard Algorithm

### Diagnostic key-path convention

The `es_diagnostics` object has six named sections `[VERIFIED: R/es_diagnostics.R:83-96]`:

```r
list(
  meta               = list(n_events_total, n_events_shown, n_events_summarized, event_ids_shown),
  estimation_window  = list(r2, sigma, degree_of_freedom, acf1, shapiro_p, dw_stat, ljung_box_p),
  event_window       = list(ar_t, ar_p, car_t, car_p, final_car),
  cross_sectional    = list(n_events, n_valid_events, car_iqr, car_sd, n_overlap_pairs, any_overlap),
  contract_state     = list(is_fitted, na_ar_count, na_est_count, insufficient_obs, zero_var_index),
  aggregate_summary  = list(n_summarized, mean_r2, median_r2, mean_final_car, n_fitted, n_degenerate)
)
```

**Key-path convention (Claude's discretion → recommended):**

```
section.key              → scalar or entire vector
section.key[i]           → element i of a vector (1-based, matching R)
```

Examples:
- `"cross_sectional.car_iqr"` → `diagnostics$cross_sectional$car_iqr` (scalar)
- `"estimation_window.shapiro_p[3]"` → `diagnostics$estimation_window$shapiro_p[[3]]`
- `"meta.n_events_total"` → `diagnostics$meta$n_events_total`

**Why dotted-path:** The six section names are never nested more than two levels deep in `es_diagnostics`. A two-part path (section.key) covers all scalar and aggregate keys; an index suffix handles per-event vectors. This is the minimal convention that resolves all keys without a recursive descent parser.

### Key-path resolver

```r
# @noRd
.resolve_diag_key <- function(diag, key_path) {
  # Parse "section.key[i]" → section, key, optional index
  # Returns the resolved value or NA_real_ if path is absent/invalid
  m <- regmatches(key_path, regexpr("^([^.]+)\\.([^\\[]+)(?:\\[(\\d+)\\])?$", key_path, perl = TRUE))
  if (length(m) == 0L || nchar(m) == 0L) return(NA_real_)

  parts   <- strsplit(key_path, "\\.")[[1L]]
  section <- parts[[1L]]
  rest    <- paste(parts[-1L], collapse = ".")

  # Extract index if present
  idx <- NULL
  idx_match <- regmatches(rest, regexpr("\\[(\\d+)\\]$", rest, perl = TRUE))
  if (length(idx_match) > 0L && nchar(idx_match) > 0L) {
    idx  <- as.integer(gsub(".*\\[(\\d+)\\].*", "\\1", idx_match))
    rest <- sub("\\[\\d+\\]$", "", rest)
  }

  # Navigate section
  sec_val <- diag[[section]]
  if (is.null(sec_val)) return(NA_real_)

  val <- sec_val[[rest]]
  if (is.null(val)) return(NA_real_)

  if (!is.null(idx)) {
    if (idx < 1L || idx > length(val)) return(NA_real_)
    val <- val[[idx]]
  }
  val
}
```

### Numeric tolerance comparison

**Rule:** `abs(reported - actual) <= max(abs_tol, rel_tol * abs(actual))` where:
- `abs_tol = 1e-6` (catches floating-point rounding)
- `rel_tol = 1e-4` (0.01% relative tolerance for values like IQR = 0.142)

These constants are Claude's discretion. They should be package options so users can adjust: `getOption("EventStudy.guard_abs_tol", 1e-6)` / `getOption("EventStudy.guard_rel_tol", 1e-4)`. `[ASSUMED]` — tolerance values are not specified in requirements.

**NA semantics:** If `actual` is `NA` and `reported` is not `NA`, that is a mismatch (LLM fabricated a number for a missing diagnostic). If `actual` is not `NA` and `reported` is `NA` (or `NULL`), also a mismatch. If both are `NA`, treat as match (consistent NA).

### Drop-and-keep mechanics

```r
# @noRd
.validate_grounding <- function(advice_list, diagnostics,
                                abs_tol = getOption("EventStudy.guard_abs_tol", 1e-6),
                                rel_tol = getOption("EventStudy.guard_rel_tol", 1e-4)) {
  recs    <- advice_list$recommendations
  kept    <- list()
  n_drop  <- 0L
  reasons <- character(0L)

  for (rec in recs) {
    ev_list  <- rec$evidence %||% list()
    all_good <- TRUE

    for (ev in ev_list) {
      key  <- ev$diagnostic_key %||% ""
      if (!nzchar(key)) { all_good <- FALSE; break }

      actual   <- .resolve_diag_key(diagnostics, key)
      reported <- ev$value

      # --- NA handling ---
      actual_na   <- length(actual) == 0L || is.null(actual) || (length(actual) == 1L && is.na(actual))
      reported_na <- is.null(reported) || (length(reported) == 1L && is.na(reported))

      if (actual_na && !reported_na) { all_good <- FALSE; break }  # key absent, LLM has value
      if (!actual_na && reported_na) { all_good <- FALSE; break }  # key present, LLM says NA
      if (actual_na && reported_na)  next                          # both NA — OK

      # --- Numeric tolerance ---
      if (!is.numeric(actual) || !is.numeric(reported)) {
        # Non-numeric (logical, character) — exact match only
        if (!identical(actual, reported)) { all_good <- FALSE; break }
        next
      }

      tol  <- max(abs_tol, rel_tol * abs(actual))
      if (abs(reported - actual) > tol) { all_good <- FALSE; break }
    }

    if (all_good) {
      kept[[length(kept) + 1L]] <- rec
    } else {
      n_drop <- n_drop + 1L
    }
  }

  # One warning if any drops
  if (n_drop > 0L) {
    warning(
      sprintf(
        "Grounding guard: %d recommendation(s) dropped — evidence cited absent or mismatched diagnostic values.",
        n_drop
      ),
      call. = FALSE
    )
  }

  advice_list$recommendations <- kept
  advice_list$n_dropped       <- n_drop

  # Append caveat recording drops
  if (n_drop > 0L) {
    drop_caveat <- sprintf(
      "%d recommendation(s) were dropped by the grounding guard: evidence cited a diagnostic key absent from the computed diagnostics or a value mismatching beyond tolerance.",
      n_drop
    )
    advice_list$caveats <- c(advice_list$caveats %||% character(), drop_caveat)
  }

  advice_list
}
```

**Critical:** The single `warning()` call happens inside `.validate_grounding()`, not in `es_advise()`. This follows the `.provider_failure()` pattern from Phase 6 (`provider.R:66-81`) where one function is the single warning-emitting point. `[VERIFIED: R/provider.R:66-81]`

---

## Research Finding 4: Per-Task-Type Prompt Strategy

### Task type routing

```
interpret         → LLM-required; errors without provider
recommend_stat    → KB → evidence[], LLM adds prose interpretation
recommend_model   → LLM-required; errors without provider
flag_robustness   → KB → evidence[], LLM adds prose interpretation
design_discussion → LLM-required; errors without provider
report_writing    → LLM-required; errors without provider
```

**LLM-only error (ADV-06):**

```r
LLM_ONLY_TYPES <- c("interpret", "recommend_model", "design_discussion", "report_writing")

if (task_type %in% LLM_ONLY_TYPES && is.null(provider)) {
  stop(
    sprintf(
      "es_advise(): task_type '%s' requires a provider. Supply provider= or use recommend_stat()/flag_robustness() for the offline path.",
      task_type
    ),
    call. = FALSE
  )
}
```

**This is a `stop()`, not a warning** — per ADV-06 "errors clearly". The drop-and-keep warning-not-stop rule applies only to guard failures, not to missing provider.

### KB injection into prompt (KB-04 — Phase 7 deliverable)

`es_kb()` returns the KB rules. The `condition` closure is not JSON-serializable; everything else is. Strip `condition` before injection:

```r
.kb_for_prompt <- function(category = NULL) {
  rules <- es_kb()
  if (!is.null(category)) {
    rules <- Filter(function(r) r$category == category, rules)
  }
  lapply(rules, function(r) {
    list(
      id             = r$id,
      category       = r$category,
      recommendation = r$recommendation,
      citation       = r$citation,
      severity       = r$severity
      # condition OMITTED — not serializable
    )
  })
}
```

`[VERIFIED: R/knowledge_base.R:420-421]` — the KB docs note: "Any consumer that serializes the KB must drop the `condition` field from each rule record before encoding to JSON."

### Prompt structure (per task type)

All prompts follow the same structure:
1. **System context:** "You are an event-study methodology expert. Cite only diagnostic values provided below. Do not invent numbers."
2. **Diagnostics block:** `jsonlite::toJSON(unclass(diagnostics), auto_unbox = TRUE, null = "null")` (omit `aggregate_summary` for brevity unless truncation occurred)
3. **KB context (recommend_stat / flag_robustness only):** serialized KB rules for that category
4. **KB-pre-grounded recommendations (recommend_stat / flag_robustness with provider):** the evidence[] objects already built from KB matching
5. **Task instruction:** task-specific instruction paragraph
6. **Schema reminder:** "Return ONLY valid JSON matching the provided schema."

**For `recommend_stat` / `flag_robustness` with provider:** inject the KB-pre-grounded evidence as the `recommendations[]` starting point and instruct LLM to fill in `rationale`, `expected_effect`, and `interpretation` prose only — never new `diagnostic_key` values. This keeps the evidence grounded on the KB side.

**For `report_writing`:** instruct to produce prose paragraphs suitable for a Methods/Results section of an academic paper. The `recommendations[]` in this output type are paragraph-form narrative recommendations, not actionable code changes. Caveats should flag statistical limitations.

### Evidence structure for KB-sourced recommendations

When a KB rule fires, convert it to the structured evidence format:

```r
# @noRd
.kb_to_evidence <- function(kb_rule, diagnostics) {
  # Build evidence entries from the rule's condition trigger
  # This is where we must map each KB rule to the diagnostic key it reads
  # KB-NORM-PATELL reads: estimation_window.shapiro_p
  # KB-NONNORM-NONPAR reads: estimation_window.shapiro_p
  # KB-VAR-INCREASE-BMP reads: cross_sectional.car_iqr, cross_sectional.car_sd
  # KB-OVERLAP-KP reads: cross_sectional.n_overlap_pairs
  # KB-AC-WARN reads: estimation_window.dw_stat
  # KB-LOWFIT-WARN reads: estimation_window.r2
  # KB-DEGEN-EVENTS reads: meta.n_events_total, cross_sectional.n_valid_events
  # KB-SMALL-N reads: cross_sectional.n_valid_events
  # [VERIFIED: R/knowledge_base.R:153-393 — condition function bodies]
  KB_KEY_MAP <- list(
    "KB-NORM-PATELL"       = list(list(key = "estimation_window.shapiro_p", threshold = 0.05, direction = "above")),
    "KB-NONNORM-NONPAR"    = list(list(key = "estimation_window.shapiro_p", threshold = 0.05, direction = "below")),
    "KB-VAR-INCREASE-BMP"  = list(
      list(key = "cross_sectional.car_iqr", threshold = 0.10, direction = "above"),
      list(key = "cross_sectional.car_sd",  threshold = 0.15, direction = "above")
    ),
    "KB-OVERLAP-KP"        = list(list(key = "cross_sectional.n_overlap_pairs", threshold = 0L, direction = "above")),
    "KB-AC-WARN"           = list(list(key = "estimation_window.dw_stat", threshold = 1.5, direction = "below")),
    "KB-LOWFIT-WARN"       = list(list(key = "estimation_window.r2", threshold = 0.05, direction = "below")),
    "KB-DEGEN-EVENTS"      = list(list(key = "cross_sectional.n_valid_events", threshold = 0.8, direction = "below")),
    "KB-SMALL-N"           = list(list(key = "cross_sectional.n_valid_events", threshold = 10L, direction = "below"))
  )
  key_specs <- KB_KEY_MAP[[kb_rule$id]] %||% list()
  lapply(key_specs, function(spec) {
    actual_val <- .resolve_diag_key(diagnostics, spec$key)
    list(
      diagnostic_key = spec$key,
      value          = if (length(actual_val) == 0L || is.null(actual_val)) NA_real_
                       else if (is.numeric(actual_val) && length(actual_val) > 1L) mean(actual_val, na.rm = TRUE)
                       else actual_val,
      threshold      = spec$threshold,
      direction      = spec$direction
    )
  })
}
```

**Note on vector-valued keys:** `estimation_window.shapiro_p` is a vector (one per shown event). When used as evidence, summarize to a scalar (e.g., median or proportion). The guard must then compare the reported scalar against the same summarization. For KB-pre-grounded evidence, the summarization is done in `.kb_to_evidence()` and the guard will find the scalar matches.

---

## Research Finding 5: generate_report Integration

### Existing signature `[VERIFIED: R/report.R:23-34]`

```r
generate_report <- function(task,
                            output_file = "event_study_report.html",
                            format = c("html", "pdf"),
                            title = "Event Study Report",
                            author = NULL,
                            sections = c("summary", "data", "diagnostics",
                                         "single_event", "multi_event",
                                         "cross_sectional", "appendix"),
                            cross_sectional = NULL,
                            confidence_level = 0.95,
                            interactive = TRUE,
                            ...)
```

### Minimal backward-compatible change

Add `advice = NULL` as a **trailing** param before `...`:

```r
generate_report <- function(task,
                            output_file = "event_study_report.html",
                            format = c("html", "pdf"),
                            title = "Event Study Report",
                            author = NULL,
                            sections = ...,
                            cross_sectional = NULL,
                            confidence_level = 0.95,
                            interactive = TRUE,
                            advice = NULL,    # NEW — trailing, NULL default
                            ...)
```

Existing callers using positional args are unaffected because `advice` is added AFTER `interactive` — but since `...` already absorbed unknown args, there is no positional conflict. Named-arg callers are unaffected.

Add `advice` to the `params` list passed to `rmarkdown::render()` `[VERIFIED: R/report.R:92-100]`:

```r
params = list(
  task             = task,
  title            = title,
  author           = author %||% "",
  sections         = sections,
  cross_sectional  = cross_sectional,
  confidence_level = confidence_level,
  interactive      = interactive,
  advice           = advice    # NEW
)
```

Add validation before the render call:

```r
if (!is.null(advice) && !inherits(advice, "Advice")) {
  warning("generate_report(): 'advice' is not an Advice object — advice section will be skipped.",
          call. = FALSE)
  advice <- NULL
}
```

### skeleton.Rmd change

Add one new param declaration and one new guarded chunk. The Rmd `params:` block `[VERIFIED: inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd:11-18]` gains:

```yaml
params:
  ...
  advice: NULL    # NEW
```

Add a new chunk at the end (before or after appendix):

```r
```{r advice-section, results='asis', eval=!is.null(params$advice) && inherits(params$advice, "Advice")}
cat("\n## AI Advisor Interpretation\n\n")
advice <- params$advice
cat(sprintf("*Source: %s | Deterministic: %s*\n\n", advice$source, advice$is_deterministic))

if (nzchar(advice$interpretation %||% "")) {
  cat("### Interpretation\n\n")
  cat(advice$interpretation, "\n\n")
}

if (length(advice$recommendations) > 0L) {
  cat("### Recommendations\n\n")
  for (i in seq_along(advice$recommendations)) {
    r <- advice$recommendations[[i]]
    cat(sprintf("**%d. %s**\n\n", i, r$action))
    cat(r$rationale %||% "", "\n\n")
    cat("*Expected effect:*", r$expected_effect %||% "", "\n\n")
  }
}

if (length(advice$caveats) > 0L) {
  cat("### Caveats\n\n")
  for (cv in advice$caveats) cat("-", cv, "\n")
}
```​
```

**Backward-compatibility guarantee:** The chunk's `eval=` condition is `FALSE` when `params$advice` is `NULL` (the default). The existing render path is byte-identical. `[VERIFIED: R/report.R:23-108 — existing render logic unchanged]`

---

## Research Finding 6: Testing Seam

### CustomProvider for deterministic guard tests

`[VERIFIED: R/provider.R:336-380]` — `CustomProvider$new(fn)` wraps a user function and returns `es_provider_response` with `text = as.character(fn(prompt, schema))[[1L]]`. This is the offline seam.

**Test fixture pattern:**

```r
# In tests/testthat/test_advise.R

# Build a minimal diagnostics object for testing
.make_test_diag <- function() {
  structure(
    list(
      meta              = list(n_events_total = 5L, n_events_shown = 5L,
                               n_events_summarized = 0L, event_ids_shown = 1:5),
      estimation_window = list(r2 = c(0.4, 0.5, 0.3, 0.6, 0.45),
                               shapiro_p = c(0.12, 0.08, 0.15, 0.20, 0.10),
                               dw_stat = c(1.9, 2.1, 2.0, 1.8, 2.2),
                               sigma = c(0.01, 0.01, 0.01, 0.01, 0.01),
                               degree_of_freedom = c(120L, 120L, 120L, 120L, 120L),
                               ljung_box_p = c(0.3, 0.4, 0.5, 0.3, 0.4),
                               acf1 = c(0.01, 0.02, -0.01, 0.03, 0.01)),
      event_window      = list(ar_t = c(1.2, 0.8, 2.1, -0.3, 1.5),
                               ar_p = c(0.23, 0.42, 0.04, 0.77, 0.13),
                               car_t = c(2.1, 1.5, 3.0, 0.2, 2.5),
                               car_p = c(0.04, 0.13, 0.003, 0.84, 0.01),
                               final_car = c(0.03, 0.02, 0.05, 0.001, 0.04)),
      cross_sectional   = list(n_events = 5L, n_valid_events = 5L,
                               car_iqr = 0.025, car_sd = 0.018,
                               n_overlap_pairs = 0L, any_overlap = FALSE),
      contract_state    = list(is_fitted = c(TRUE, TRUE, TRUE, TRUE, TRUE),
                               na_ar_count = c(0L, 0L, 0L, 0L, 0L),
                               na_est_count = c(0L, 0L, 0L, 0L, 0L),
                               insufficient_obs = c(FALSE, FALSE, FALSE, FALSE, FALSE),
                               zero_var_index = c(FALSE, FALSE, FALSE, FALSE, FALSE)),
      aggregate_summary = NULL
    ),
    class = "es_diagnostics"
  )
}

# Canned JSON: one valid rec, one missing-key rec, one out-of-tolerance rec
CANNED_JSON_THREE_RECS <- jsonlite::toJSON(list(
  interpretation = "The study shows significant abnormal returns.",
  recommendations = list(
    # Rec A: VALID — key exists, value within tolerance
    list(action = "Use BMP test", kind = "stat_choice",
         rationale = "High CAR dispersion.", expected_effect = "Robust p-values.",
         evidence = list(
           list(diagnostic_key = "cross_sectional.car_iqr",
                value = 0.025, threshold = 0.10, direction = "below")
         )),
    # Rec B: INVALID — key does not exist in diagnostics
    list(action = "Check tail risk", kind = "robustness",
         rationale = "Heavy tails.", expected_effect = "Better size control.",
         evidence = list(
           list(diagnostic_key = "cross_sectional.kurtosis",  # ABSENT key
                value = 4.2, threshold = 3.0, direction = "above")
         )),
    # Rec C: INVALID — value mismatches beyond tolerance
    list(action = "Switch to FF3", kind = "recommend_model",
         rationale = "Low R2.", expected_effect = "Better fit.",
         evidence = list(
           list(diagnostic_key = "estimation_window.r2",
                value = 0.99,  # ACTUAL mean is ~0.45, way off
                threshold = 0.05, direction = "above")
         ))
  ),
  caveats = list("This is AI-generated advice.")
), auto_unbox = TRUE)

test_that("grounding guard: only valid rec survives, caveat records 2 drops, one warning", {
  diag <- .make_test_diag()
  p <- CustomProvider$new(function(prompt, schema) CANNED_JSON_THREE_RECS)

  result <- expect_warning(
    es_advise(diag, task_type = "recommend_stat", provider = p),
    "Grounding guard"
  )

  expect_s3_class(result, "Advice")
  expect_equal(length(result$recommendations), 1L)       # only rec A
  expect_equal(result$recommendations[[1]]$action, "Use BMP test")
  expect_equal(result$n_dropped, 2L)
  expect_true(any(grepl("2 recommendation", result$caveats)))
})

test_that("no-provider error for LLM-only task types", {
  diag <- .make_test_diag()
  expect_error(
    es_advise(diag, task_type = "interpret", provider = NULL),
    "requires a provider"
  )
})
```

**Warning count assertion:** `expect_warning(..., "Grounding guard")` captures exactly one warning matching the pattern. A second spurious warning would cause test failure. This is the correct way to assert the one-warning contract in testthat 3e. `[ASSUMED]` — standard testthat 3e idiom.

### Offline path compatibility test

```r
test_that("es_advise with no provider + KB task type returns es_advice (Phase 5 path)", {
  diag <- .make_test_diag()
  result <- es_advise(diag, task_type = "recommend_stat", provider = NULL)
  expect_s3_class(result, "es_advice")   # NOT Advice — offline path unchanged
})
```

---

## Research Finding 7: Common Pitfalls

### Pitfall 1: CRAN Suggests-guard trap with jsonlite

**What goes wrong:** `jsonlite::fromJSON()` is called at the top level of a function without a `requireNamespace()` guard. When jsonlite is absent, `R CMD check` does not flag it (because it's in Suggests), but the function crashes at runtime with "there is no package called 'jsonlite'".

**How to avoid:** Every call path that touches `jsonlite` must be inside a guard:
```r
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  warning("jsonlite required...", call. = FALSE)
  return(.empty_advice(source_label))
}
```

`[VERIFIED: R/provider.R:448-460, 608-616]` — Phase 6 already shows the correct pattern for httr2+jsonlite.

**Note:** `R CMD check --as-cran` with `_R_CHECK_DEPENDS_ONLY_=true` will install only hard deps and catch unguarded Suggests use. Add this to the Phase 8 check gate.

### Pitfall 2: globalVariables for NSE (not applicable here)

`es_advise()` uses no dplyr/ggplot2 NSE. The `Advice` object is a plain list, not a tibble pipeline. No `globalVariables()` additions needed. `[ASSUMED]` — based on reviewing the implementation sketch above.

### Pitfall 3: jsonlite default simplifyVector = TRUE breaks nested lists

**What goes wrong:** `jsonlite::fromJSON('{"evidence":[{"key":"x","value":1.5}]}')` with the default `simplifyVector = TRUE` returns `evidence` as a data.frame, not a list-of-lists. Then `rec$evidence[[1]]$diagnostic_key` fails because data.frame column access works differently.

**How to avoid:** Always `jsonlite::fromJSON(text, simplifyVector = FALSE)`. Document this in a comment next to the call. `[ASSUMED]` — standard jsonlite pitfall, independently known.

### Pitfall 4: Integer vs double in evidence value comparison

**What goes wrong:** LLM emits `"value": 5` (integer in JSON), diagnostics holds `n_overlap_pairs = 5L` (R integer). After `fromJSON`, `value = 5` is a double `5.0`. `identical(5L, 5.0)` is `FALSE`.

**How to avoid:** Use `abs(reported - actual) <= tol` for all numeric comparisons in the guard, never `identical()` for numerics. The tolerance approach naturally handles integer-vs-double. `[ASSUMED]` — R numeric type behavior is well-known.

### Pitfall 5: print.Advice for empty recommendations list

**What goes wrong:** `for (i in seq_along(x$recommendations))` when `x$recommendations` is `list()` — `seq_along(list())` returns `integer(0)`, loop body never executes, no crash. But the output looks confusing without a message.

**How to avoid:** Add an explicit `if (n_recs == 0L) cat("(No recommendations.)\n")` branch in `print.Advice`.

### Pitfall 6: is_deterministic semantics on KB+LLM hybrid path

**What goes wrong:** When `recommend_stat` uses KB for evidence AND a provider for prose, `is_deterministic` should be `FALSE` (provider was involved). Setting it `TRUE` because the evidence is from KB is misleading.

**How to avoid:** `is_deterministic = TRUE` ONLY when the pure offline `es_advice` S3 is returned (no provider call). Any path that calls a provider sets `is_deterministic = FALSE` in the returned `Advice` object. `[VERIFIED: R/advise_offline.R:222-223]` — offline path returns `is_deterministic = TRUE`.

### Pitfall 7: Advice class name collision risk

The class name `"Advice"` is generic. If another CRAN package defines `print.Advice`, there will be a dispatch conflict. Convention: use `"es_Advice"` or just test with `inherits(x, "Advice")` (which is fine since it's the user's own class in their session). The CONTEXT.md says "Advice S3" — use class name `"Advice"` per the spec. `[ASSUMED]` — CRAN namespace conflict risk is LOW given the package's specialized domain.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | custom string parser | `jsonlite::fromJSON(simplifyVector = FALSE)` | JSON edge cases (escaping, unicode, null, nested arrays) are innumerable |
| HTTP to LLM APIs | raw `curl` or `connections` | Existing `provider$complete()` seam (Phase 6) | Already handles auth redaction, retries, degradation |
| Key-path navigation deeper than 2 levels | recursive descent | Dotted 2-part path + index suffix | `es_diagnostics` is only 2 levels deep; YAGNI |
| Rmd templating | custom report generation | Guarded `eval=` chunk in existing skeleton.Rmd | Already works; zero new infrastructure |
| Provider schema validation | R-side JSON Schema validator | Trust the LLM's output shape then guard in R | The guard already catches wrong values; schema is advisory to the LLM, not a hard constraint enforced in R |

---

## Code Examples

### Verified: es_diagnostics six-section structure

`[VERIFIED: R/es_diagnostics.R:83-96]`
```r
result <- list(
  meta               = list(n_events_total, n_events_shown, n_events_summarized, event_ids_shown),
  estimation_window  = list(r2, sigma, degree_of_freedom, acf1, shapiro_p, dw_stat, ljung_box_p),
  event_window       = list(ar_t, ar_p, car_t, car_p, final_car),
  cross_sectional    = list(n_events, n_valid_events, car_iqr, car_sd, n_overlap_pairs, any_overlap),
  contract_state     = list(is_fitted, na_ar_count, na_est_count, insufficient_obs, zero_var_index),
  aggregate_summary  = list(n_summarized, mean_r2, median_r2, mean_final_car, n_fitted, n_degenerate)
)
class(result) <- "es_diagnostics"
```

### Verified: .handle_degenerate pattern (the guard mirrors)

`[VERIFIED: R/contract.R:74-97]`
```r
# Mode lenient: one warning, return FALSE
warning(msg, call. = FALSE)
invisible(FALSE)
```

Guard mirrors: one `warning(..., call. = FALSE)`, drop recs, continue.

### Verified: CustomProvider offline seam for tests

`[VERIFIED: R/provider.R:359-375]`
```r
p <- CustomProvider$new(function(prompt, schema) '{"interpretation":"...","recommendations":[],"caveats":[]}')
res <- p$complete("prompt")
res$text  # the JSON string
```

### Verified: es_advice structure (Phase 5, backward-compat anchor)

`[VERIFIED: R/advise_offline.R:221-229]`
```r
structure(list(source = "offline_kb", is_deterministic = TRUE,
               rules_matched = matched, diagnostics_ref = diag),
          class = "es_advice")
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-coded free-text interpretation in paper | Grounded LLM layer + structured evidence | Phase 7 (this) | Reproducible, auditable interpretation |
| KB rules as the only advice | KB + LLM prose on top | Phase 7 (this) | Richer rationale, same grounding guarantee |
| `es_advice` S3 (Phase 5) | New `Advice` S3 with evidence[] | Phase 7 (this) | Structured evidence enables runtime guard |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `recommendations` as list-of-lists (not data.frame) is the right representation | Advice S3 Design | Minor: could use data.frame with list-columns, but would complicate guard iteration |
| A2 | `abs_tol = 1e-6`, `rel_tol = 1e-4` as default guard tolerances | Guard Algorithm | Guard may be too strict or too lenient for specific diagnostic values; mitigated by making them package options |
| A3 | Dotted path `section.key[i]` is a sufficient key-path convention | Guard Algorithm | No risk: es_diagnostics is only 2 levels deep, confirmed by reading the source |
| A4 | KB rule → diagnostic key mapping in `.kb_to_evidence()` is correct | KB→evidence conversion | Low: derived directly from reading the `condition` function bodies in knowledge_base.R:153-393 |
| A5 | `direction = "na"` enum value in schema prevents LLM from fabricating directions for NA diagnostics | JSON schema | LLM may still violate the enum; guard catches the NA-vs-present mismatch regardless |
| A6 | `jsonlite::fromJSON(simplifyVector = FALSE)` behaviour for nested arrays | JSON parsing | Well-documented jsonlite behaviour; LOW risk |
| A7 | Class name `"Advice"` has no CRAN collision | S3 design | Very low risk given domain specificity |

---

## Open Questions

1. **Vector-valued evidence summary strategy**
   - What we know: `estimation_window.shapiro_p` is a per-event vector; the LLM must cite a scalar
   - What's unclear: Should the prompt instruct the LLM to cite the median, proportion, or individual event index?
   - Recommendation: For KB-pre-grounded recs, `.kb_to_evidence()` summarizes to median/proportion (matching KB rule logic); for LLM-generated recs, instruct the model to use index notation `section.key[i]` and the guard checks the indexed value. Both are implementable.

2. **report_writing Rmd chunk placement**
   - What we know: skeleton.Rmd has `appendix` as the last chunk
   - What's unclear: Should the advice chunk appear before or after appendix?
   - Recommendation: Before appendix (advice is a first-class section, appendix is metadata).

---

## Environment Availability

Step 2.6: SKIPPED (no new external dependencies — all deps already present from Phase 5/6; no new CLI tools or services required).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | testthat 3e |
| Config file | `tests/testthat.R` |
| Quick run command | `testthat::test_file("tests/testthat/test_advise.R")` |
| Full suite command | `devtools::test()` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADV-01 | `es_advise()` returns `Advice` S3 with correct fields | unit | `testthat::test_file("tests/testthat/test_advise.R")` | ❌ Wave 0 |
| ADV-02 | Each recommendation has action/kind/rationale/expected_effect/evidence | unit | same | ❌ Wave 0 |
| ADV-03 | Each evidence entry has diagnostic_key/value/threshold/direction | unit | same | ❌ Wave 0 |
| ADV-04 | Guard drops missing-key rec; guard drops out-of-tolerance rec; one warning; caveat records N drops | unit (deterministic, CustomProvider) | same | ❌ Wave 0 |
| ADV-05 | All six task types routed correctly | unit | same | ❌ Wave 0 |
| ADV-06 | LLM-only types stop() with no provider | unit | same | ❌ Wave 0 |
| ADV-07 | generate_report(advice=NULL) path unchanged; with Advice renders section | unit + integration | `devtools::test()` | ❌ Wave 0 |

### Wave 0 Gaps
- [ ] `tests/testthat/test_advise.R` — covers ADV-01..07
- [ ] `tests/testthat/helper-advice-fixtures.R` — canned JSON + test diagnostics object

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | `.validate_grounding()` rejects ungrounded evidence; JSON schema validation by LLM provider |
| V6 Cryptography | no | — |
| V7 Error Handling | yes | One-warning-never-crash; `tryCatch` at all provider call sites |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| LLM fabricated values in advice | Spoofing | Grounding guard rejects evidence with absent/mismatched keys |
| API key leakage via error messages | Information Disclosure | `.provider_failure()` never includes key in reason; `req_headers_redacted()` used in HTTP providers |
| Prompt injection via diagnostic values | Tampering | Diagnostics are serialized as JSON (not string interpolation); structural injection is harder |
| Malformed JSON DoS | Denial of Service | `tryCatch(jsonlite::fromJSON(...))` returns NULL → `.empty_advice()`, never crashes |

---

## Sources

### Primary (HIGH confidence — in-repo, read this session)
- `R/advise_offline.R:1-231` — es_advice S3 contract, print.es_advice, .build_offline_advice
- `R/es_diagnostics.R:1-98` — six-section structure, all key names verbatim
- `R/knowledge_base.R:146-394` — all 8 KB rules with condition bodies (KB key mapping)
- `R/provider.R:1-718` — ProviderBase, CustomProvider, OpenAICompatProvider, AnthropicProvider, schema arg, es_provider_response shape
- `R/report.R:23-108` — generate_report signature, params list, rmarkdown::render call
- `R/contract.R:74-97` — .handle_degenerate one-warning pattern
- `inst/rmarkdown/templates/event_study_report/skeleton/skeleton.Rmd:1-194` — existing Rmd structure, chunk eval pattern

### Secondary (ASSUMED — training knowledge)
- jsonlite `simplifyVector = FALSE` behavior for nested arrays
- testthat 3e `expect_warning()` captures exactly one matching warning
- JSON Schema draft-7 `required` / `additionalProperties` / `enum` fields

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all deps verified in-repo
- Architecture: HIGH — derived directly from reading Phase 5/6 source code
- Guard algorithm: HIGH — diagnostic key names verified verbatim from es_diagnostics.R:83-96
- KB key mapping: HIGH — derived from reading condition function bodies in knowledge_base.R:153-393
- Pitfalls: HIGH for jsonlite/CRAN traps (verified from provider.R patterns), MEDIUM for tolerance constants (assumed)
- report.R integration: HIGH — verified existing signature and params list

**Research date:** 2026-09-04
**Valid until:** 2026-10-04 (stable internal contracts; Phase 8 does not change es_advise)
