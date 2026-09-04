---
phase: 06-provider-abstraction-+-cran-safe-http-harness
reviewed: 2026-09-03T00:00:00Z
depth: deep
files_reviewed: 7
files_reviewed_list:
  - R/provider.R
  - tests/testthat/helper-provider.R
  - tests/testthat/test_provider_custom.R
  - tests/testthat/test_provider_resolution.R
  - tests/testthat/test_provider_openai.R
  - tests/testthat/test_provider_anthropic.R
  - tests/testthat/test_provider_redaction.R
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-09-03
**Depth:** deep
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the Phase 6 provider-abstraction seam against the milestone bar: never
silently wrong, never leak keys, never crash the session, CRAN-safe with the
optional deps uninstalled.

**Key leakage (highest priority): CLEAN.** I traced every path a key can reach a
user-visible surface. Keys are never stored on any R6 field (only `model`,
`base_url`, `max_tokens` are stored; `.resolve_api_key()` reads at call time and
the value lives only in a local `key` inside `complete()`). The Anthropic
`x-api-key` path uses `req_headers_redacted()` on the sole `.perform_request()`
x-api-key branch (line 201); OpenAI uses `req_auth_bearer_token()` (line 199).
`.provider_failure()` reasons are hard-coded strings; the non-2xx reason carries
only `"HTTP <status>"` (line 238), never the body or key. The redaction test
suite includes a control test proving the assertion bites. No key-leak defect
found.

**Never-crash: TWO real crash paths found (CR-01, CR-02).** Most failure modes
degrade correctly to one warning + NA, but (1) `req_body_json()` in
`.perform_request()` sits OUTSIDE the `tryCatch` and throws an uncaught error if
`jsonlite` is absent while `httr2` is present, and (2) `CustomProvider$complete()`
runs `as.character(out)[[1L]]` outside its `tryCatch`, throwing "subscript out of
bounds" when the user function returns `NULL` or `character(0)`.

**CRAN safety: one hole (CR-01).** `jsonlite` is guarded only in
`.extract_anthropic_text`; the request-build path assumes it. httr2 lists
jsonlite in Suggests (not Imports) and `req_body_json`/`resp_body_json` call
`check_installed("jsonlite")`, so httr2-present-jsonlite-absent is a live,
un-degraded error path.

Wire formats, the `es_provider_response` contract, resolution precedence, and
empty-string/NA env handling are otherwise correct and consistent.

## Critical Issues

### CR-01: `req_body_json()` throws uncaught when `jsonlite` absent — crash + CRAN-safety hole

**File:** `R/provider.R:191` (call), `R/provider.R:207-210` (tryCatch scope); entry guards at `R/provider.R:433`, `R/provider.R:581`
**Issue:** Both HTTP providers guard only `requireNamespace("httr2")` before calling
`.perform_request()`. Inside `.perform_request()`, `httr2::req_body_json(req, body)`
(line 191) runs OUTSIDE the `tryCatch` that wraps `req_perform` (lines 207-210).

Verified this session: httr2 lists `jsonlite` in **Suggests**, not Imports
(`packageDescription("httr2")$Imports` has no jsonlite), and `req_body_json` /
`resp_body_json` call `check_installed("jsonlite")`, which **errors** when jsonlite
is not installed. So on a machine with `httr2` present but `jsonlite` absent —
a valid install because both are in EventStudy `Suggests` independently — a call
to `OpenAICompatProvider$complete()` or `AnthropicProvider$complete()` throws an
uncaught error and crashes the session instead of degrading to one warning + NA.
This violates both the never-crash contract (PROV-07) and CRAN-safe
optional-dependency discipline (PROV-08 / CRAN-02).

**Triggering input:** httr2 installed, jsonlite NOT installed, any
`p$complete("hi")` on an HTTP provider with a key set.

**Fix:** Guard `jsonlite` alongside `httr2` at the top of both HTTP `complete()`
methods (it is a hard requirement of the request/parse path, not optional there):

```r
if (!requireNamespace("httr2", quietly = TRUE) ||
    !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Packages 'httr2' and 'jsonlite' are required for the ",
       "OpenAI-compatible provider. Install them with: ",
       "install.packages(c('httr2', 'jsonlite'))")
}
```

(Same for the Anthropic provider message.) This turns the crash into the same
clear, actionable error the phase already uses for a missing httr2, and keeps
CRAN clean. `.extract_anthropic_text` already guards jsonlite correctly.

### CR-02: `CustomProvider$complete()` crashes on `NULL` / empty-vector return from the user fn

**File:** `R/provider.R:351-360` (`complete`), specifically line 359
**Issue:** The user function is run inside `tryCatch` (lines 352-355), but the
success coercion `as.character(out)[[1L]]` (line 359) is OUTSIDE that `tryCatch`.
Verified this session: when the user fn returns `NULL` or `character(0)`,
`as.character(out)` is `character(0)` and `[[1L]]` throws
`"subscript out of bounds"`. Because this is outside any trap, the error escapes
`complete()` and crashes the session — the exact failure mode the never-crash
contract forbids. A `NULL` return from a user callback is entirely plausible (an
early `return()`, a function whose last expression is `invisible(NULL)`, etc.).

**Triggering input:** `CustomProvider$new(function(prompt, schema) NULL)$complete("hi")`
or a fn returning `character(0)`.

**Fix:** Validate the coerced result and route empties through `.provider_failure`
so they degrade to one warning + NA like every other path:

```r
complete = function(prompt, schema = NULL, ...) {
  out <- tryCatch(private$.fn(prompt, schema, ...), error = function(e) e)
  if (inherits(out, "condition")) {
    return(.provider_failure("custom", "custom function errored"))
  }
  text <- tryCatch(as.character(out), error = function(e) character(0))
  if (length(text) < 1L || is.na(text[[1L]]) || !nzchar(text[[1L]])) {
    return(.provider_failure("custom", "custom function returned no text"))
  }
  .provider_success("custom", text[[1L]])
}
```

There is no test covering a `NULL`/empty custom return (see IN-01); the existing
custom tests only exercise a string return and a throwing fn.

## Warnings

### WR-01: empty `tool_use$input` yields `"[]"` / `"{}"` as a "successful" completion

**File:** `R/provider.R:489-505` (`.extract_anthropic_text` tool_use branch)
**Issue:** When the model returns a `tool_use` block whose `input` is an empty
list, `jsonlite::toJSON(list(), auto_unbox = TRUE)` produces `"[]"` (verified),
and an empty *named* list produces `"{}"`. Both are length-1, non-NA, non-empty
strings, so they pass the `.finish_response` text guard (line 248) and are
returned as a *successful* `es_provider_response` with `text = "[]"`. That is a
plausible-looking but content-free completion handed to Phase 7 — a soft version
of "silently wrong": the caller believes it got structured advice when the tool
call carried no payload.
**Fix:** After rendering, treat an empty structured payload as failure. Guard on
`length(input) == 0L` before the toJSON branch and fall through to the text
fallback / return `NA_character_`:

```r
if (identical(block$type, "tool_use") && !is.null(block$input) &&
    length(block$input) > 0L) {
  ...
}
```

### WR-02: OpenAI `content` extractor does not defend against a non-scalar / structured `content`

**File:** `R/provider.R:458` (`function(p) p$choices[[1]]$message$content`)
**Issue:** The extractor assumes `message$content` is a scalar string. Newer
OpenAI-compatible responses (and some gateways) can return `content` as an array
of parts or `null` with the text under a different key. A `null`/missing content
yields `NULL`, which the guard correctly rejects (verified), so no crash — but an
array-valued `content` would produce a multi-element or list value. The guard's
`length(text) != 1L` rejects a multi-element vector (degrades to failure), but a
length-1 *list* passes the guard (verified: `is.na(list("x"))` is `FALSE`) and
would store a list in `text`, breaking the "text is character scalar" contract
Phase 7 relies on and the JSON-serializability assumption.
**Fix:** Coerce and constrain in the extractor, mirroring the Anthropic one:

```r
function(p) {
  ct <- p$choices[[1]]$message$content
  if (is.null(ct) || length(ct) != 1L || !is.character(ct)) return(NA_character_)
  ct
}
```

This is defense-in-depth; the common OpenAI shape works today, but the seam
should not depend on the happy shape given the explicit "any OpenAI-compatible
gateway" scope.

### WR-03: `.finish_response` guard can be handed a non-character `text`; `nzchar` on a list errors inside no-trap zone

**File:** `R/provider.R:247-250`
**Issue:** `text <- tryCatch(extract_fn(parsed), ...)` traps errors *inside*
`extract_fn`, but the subsequent guard `length(text) != 1L || is.na(text) || !nzchar(text)`
runs outside any trap. For a length-1 list value (see WR-02), `is.na()` returns
`FALSE` and `nzchar()` on a list raises
`"nzchar() requires a character vector"` — an uncaught error. Today no extractor
returns a length-1 list on the success path (`.extract_anthropic_text` coerces
with `as.character(...)[[1L]]`; OpenAI returns a scalar or NULL), so this is
latent rather than live, but it is one refactor away from a crash and pairs with
WR-02.
**Fix:** Constrain to character before the string checks:

```r
if (length(text) != 1L || !is.character(text) || is.na(text) || !nzchar(text)) {
  return(.provider_failure(source_label, "no completion text in response"))
}
```

Fixing the extractors (WR-02) also closes this; doing both is belt-and-suspenders.

### WR-04: `provider("custom")` with `fn = NULL` produces a raw `stopifnot` error, not the package's clear-message idiom

**File:** `R/provider.R:660-667` (factory) → `R/provider.R:338` (`stopifnot(is.function(fn))`)
**Issue:** `provider()` defaults `fn = NULL`; when `type` resolves to `"custom"`
(the documented default) and no `fn` is supplied, construction hits
`stopifnot(is.function(fn))` producing `"is.function(fn) is not TRUE"`. The
package convention (per CLAUDE.md error-handling section, `stop()` with a
descriptive message) is an actionable message. A user who runs `provider()` with
no arguments — the documented zero-config path — gets a cryptic error.
**Fix:** Validate in the factory's custom branch with a clear message:

```r
if (identical(type, "custom")) {
  if (!is.function(fn)) {
    stop("provider(type = 'custom') requires a function `fn` of ",
         "(prompt, schema, ...). ", call. = FALSE)
  }
  return(CustomProvider$new(fn = fn, model = cfg$model, ...))
}
```

## Info

### IN-01: No test covers a `NULL` / empty return from a CustomProvider fn (the CR-02 path)

**File:** `tests/testthat/test_provider_custom.R` (whole file)
**Issue:** Custom tests cover a string return and a throwing fn, but not a `NULL`
or `character(0)` return — precisely the uncovered crash in CR-02.
**Fix:** Add `expect_warning(res <- CustomProvider$new(function(prompt, schema) NULL)$complete("hi"))`
plus `expect_true(is.na(res$text))` once CR-02 is fixed.

### IN-02: No jsonlite-absent test asserts the HTTP providers degrade rather than crash

**File:** `tests/testthat/test_provider_openai.R`, `test_provider_anthropic.R`
**Issue:** The CRAN-safety hole in CR-01 is untested. All HTTP tests run with
jsonlite present. A test that mocks jsonlite-absent (or at least documents the
guard) would lock the regression once CR-01 is fixed. A full uninstalled-dep
simulation is awkward in-process; at minimum add a comment/skip test asserting
the guard message includes jsonlite.
**Fix:** After CR-01, add a test that stubs `requireNamespace` to return FALSE
for `"jsonlite"` and asserts `complete()` raises the clear install message (not a
`check_installed` error), or covers it via the guard directly.

### IN-03: `max_tokens` accepted without validation; a non-numeric value fails only at wire time

**File:** `R/provider.R:563-568` (`AnthropicProvider$initialize`)
**Issue:** `max_tokens` is stored verbatim with no type/positivity check. A caller
passing `max_tokens = "lots"` or `-5` builds a body that the API rejects (a 4xx,
which degrades cleanly — so no crash), but the error is opaque. Minor, since it
degrades safely.
**Fix:** Optional: `stopifnot(is.numeric(max_tokens), length(max_tokens) == 1L, max_tokens > 0)`
in `initialize`, consistent with the package's `stopifnot` validation idiom.

---

_Reviewed: 2026-09-03_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
