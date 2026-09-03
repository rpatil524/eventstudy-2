# =============================================================================
# Provider seam for the Grounded AI Advisor (Phase 6)
# =============================================================================
#
# This file defines the uniform LLM-provider seam. It mirrors the package's
# existing ModelBase / TestStatisticBase strategy-pattern idiom (R/models.R):
# an abstract R6 base (`ProviderBase`) defines the uniform
# `complete(prompt, schema, ...)` contract, and concrete subclasses implement it.
#
# In this plan (06-1) only `CustomProvider` (an in-process user-function hook
# that needs NO network) is fully wired. The two HTTP providers
# (OpenAICompatProvider in 06-2, AnthropicProvider in 06-3) expand out from this
# proven skeleton. `httr2`/`jsonlite` live in Suggests and are only touched by
# those later HTTP providers; CustomProvider and the resolution helpers need
# neither, so this whole plan runs with them uninstalled.
#
# Failure discipline mirrors .handle_degenerate() in R/contract.R: every
# provider failure routes through the SINGLE point `.provider_failure()`, which
# emits EXACTLY ONE warning(msg, call. = FALSE) and returns an
# `es_provider_response` carrying text = NA_character_ — it never lets an
# uncaught error escape and never returns a plausible-looking wrong completion.

# ---------------------------------------------------------------------------
# es_provider_response builders (the single success / failure plumbing)
# ---------------------------------------------------------------------------

#' Build a successful es_provider_response
#'
#' The field names (`source`, `is_deterministic`, `text`, `error`) are LOCKED to
#' match the Phase 5 `es_advice` shape (see R/advise_offline.R:221-229) so that
#' Phase 7's `es_advise()` wrapper slots the online path next to the offline path
#' without reshaping. The provider path is never deterministic
#' (`is_deterministic = FALSE`) and returns raw completion `text` for Phase 7 to
#' ground-check.
#'
#' @param source_label Character provider label, e.g. "custom", "openai".
#' @param text Character completion text.
#' @return An `es_provider_response` S3 object.
#' @noRd
.provider_success <- function(source_label, text) {
  structure(
    list(
      source           = source_label,
      is_deterministic = FALSE,
      text             = text,
      error            = NULL
    ),
    class = "es_provider_response"
  )
}

#' Build a failing es_provider_response (the SINGLE warning-emitting point)
#'
#' Every provider failure path routes through here so that exactly ONE warning is
#' emitted per failure (mirroring `.handle_degenerate()` in R/contract.R). Never
#' call `warning()` for a provider failure anywhere else. The returned object
#' carries `text = NA_character_` — never a fabricated completion — preserving the
#' package's "never silently wrong" core value at the LLM layer.
#'
#' Secrets are NEVER placed into `reason`, the warning, or the returned object.
#'
#' @param source_label Character provider label.
#' @param reason Character, short human-readable failure reason (no secrets).
#' @return An `es_provider_response` S3 object with `text = NA_character_`.
#' @noRd
.provider_failure <- function(source_label, reason) {
  warning(
    sprintf("Advisor provider '%s' failed: %s. Returning NA.",
            source_label, reason),
    call. = FALSE
  )
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

# ---------------------------------------------------------------------------
# ProviderBase — abstract R6 contract
# ---------------------------------------------------------------------------

#' @title ProviderBase
#' @description Abstract base class for Grounded AI Advisor providers. Defines the
#'   uniform `complete(prompt, schema, ...)` contract, mirroring the package's
#'   `ModelBase` / `TestStatisticBase` strategy-pattern idiom. Concrete providers
#'   (`CustomProvider`, and the HTTP `OpenAICompatProvider` / `AnthropicProvider`
#'   delivered in later plans) inherit from this base and implement `complete()`.
#'
#'   `ProviderBase` itself is abstract: calling `complete()` on it errors. It
#'   stores only non-secret configuration (`model`, `base_url`); API keys are
#'   NEVER read at construction — they are resolved at call time inside each
#'   concrete provider's `complete()`.
#' @export
ProviderBase <- R6::R6Class(
  "ProviderBase",
  public = list(
    #' @field model Character model identifier (or NULL for provider default).
    model = NULL,
    #' @field base_url Character base URL for HTTP providers (or NULL).
    base_url = NULL,

    #' @description Construct a provider. Stores non-secret config only; never
    #'   reads or stores API keys (keys are resolved at call time).
    #' @param model Optional character model identifier.
    #' @param base_url Optional character base URL (HTTP providers only).
    #' @param ... Ignored; accepted for subclass forward-compatibility.
    initialize = function(model = NULL, base_url = NULL, ...) {
      self$model <- model
      self$base_url <- base_url
      invisible(self)
    },

    #' @description Complete a prompt. Abstract on the base class — concrete
    #'   providers override this.
    #' @param prompt Character prompt to send to the provider.
    #' @param schema Optional structured-output schema (list) or NULL.
    #' @param ... Provider-specific arguments.
    #' @return An `es_provider_response` S3 list with fields:
    #'   \code{source} (character provider label),
    #'   \code{is_deterministic} (always \code{FALSE} for provider output),
    #'   \code{text} (character completion, or \code{NA_character_} on failure),
    #'   \code{error} (\code{NULL} on success, character reason on failure).
    #'   These field names match the Phase 5 \code{es_advice} shape so the Phase 7
    #'   wrapper slots in trivially.
    complete = function(prompt, schema = NULL, ...) {
      stop("ProviderBase is abstract; use a concrete provider.", call. = FALSE)
    }
  )
)

# ---------------------------------------------------------------------------
# CustomProvider — in-process user-function hook (NO HTTP)
# ---------------------------------------------------------------------------

#' @title CustomProvider
#' @description A provider that wraps a user-supplied
#'   \code{function(prompt, schema, ...) -> list | character}. This is the
#'   offline end-to-end seam and the escape hatch for backends the built-in HTTP
#'   providers do not cover. It uses NO network and needs neither \code{httr2}
#'   nor \code{jsonlite}.
#'
#'   The user function is run inside \code{tryCatch}: if it errors, the provider
#'   degrades to exactly one \code{warning()} plus an `es_provider_response` with
#'   \code{text = NA_character_} — it never crashes the session.
#' @export
#' @examples
#' # In-process, no network: the user function supplies the completion text.
#' p <- CustomProvider$new(function(prompt, schema) "canned advice")
#' res <- p$complete("Summarise these diagnostics")
#' res$text
#' res$source
CustomProvider <- R6::R6Class(
  "CustomProvider",
  inherit = ProviderBase,
  public = list(
    #' @description Construct a CustomProvider.
    #' @param fn A function of \code{(prompt, schema, ...)} returning a list or a
    #'   character completion. Required.
    #' @param model Optional character model identifier (informational only).
    #' @param ... Ignored; forwarded for forward-compatibility.
    initialize = function(fn, model = NULL, ...) {
      stopifnot(is.function(fn))
      super$initialize(model = model, base_url = NULL)
      private$.fn <- fn
      invisible(self)
    },

    #' @description Run the wrapped user function and wrap its result in an
    #'   `es_provider_response`. A throwing function degrades to one warning + NA.
    #' @param prompt Character prompt passed to the user function.
    #' @param schema Optional structured-output schema passed through to the user
    #'   function.
    #' @param ... Additional arguments forwarded to the user function.
    #' @return An `es_provider_response` (see \code{ProviderBase$complete}).
    complete = function(prompt, schema = NULL, ...) {
      out <- tryCatch(
        private$.fn(prompt, schema, ...),
        error = function(e) e
      )
      if (inherits(out, "condition")) {
        return(.provider_failure("custom", "custom function errored"))
      }
      .provider_success("custom", as.character(out)[[1L]])
    }
  ),
  private = list(
    .fn = NULL
  )
)
