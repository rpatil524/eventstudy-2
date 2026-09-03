# =============================================================================
# OpenAI-compatible provider + shared httr2 request/response helpers (Phase 6-2)
# =============================================================================
#
# Every test here is OFFLINE: httr2 responses are constructed directly or driven
# through httr2::local_mocked_responses() with a dummy key set via withr. No
# network call is made and no real key is read, so the suite is CRAN-safe and
# passes with httr2/jsonlite present (all references are requireNamespace-guarded
# in the provider code itself).

# ---------------------------------------------------------------------------
# Task 1: .finish_response never-throw discipline (helper-level, no provider)
# ---------------------------------------------------------------------------

test_that(".finish_response degrades a transport/timeout condition to one warning + NA", {
  cond <- structure(
    class = c("httr2_failure", "error", "condition"),
    list(message = "timed out")
  )
  expect_warning(
    res <- .finish_response(cond, function(p) p$choices[[1]]$message$content, "openai"),
    "network|timeout"
  )
  expect_true(is.na(res$text))
  expect_equal(res$source, "openai")
  expect_false(is.null(res$error))
})

test_that(".finish_response degrades a non-2xx (401) to one warning + NA, no body/key", {
  resp <- httr2::response(status_code = 401L)
  expect_warning(
    res <- .finish_response(resp, function(p) p$choices[[1]]$message$content, "openai"),
    "HTTP 401"
  )
  expect_true(is.na(res$text))
  # The reason must carry ONLY "HTTP 401" — no body, no key.
  expect_match(res$error, "^HTTP 401$")
})

test_that(".finish_response traps a malformed 200 body -> one warning + NA", {
  resp <- httr2::response(status_code = 200L, body = charToRaw("{not json"))
  expect_warning(
    res <- .finish_response(resp, function(p) p$choices[[1]]$message$content, "openai"),
    "malformed"
  )
  expect_true(is.na(res$text))
})

test_that(".finish_response on a 200 whose extract yields empty -> one warning + NA", {
  resp <- httr2::response_json(
    status = 200L,
    body = list(choices = list(list(message = list(content = ""))))
  )
  expect_warning(
    res <- .finish_response(resp, function(p) p$choices[[1]]$message$content, "openai"),
    "no completion text"
  )
  expect_true(is.na(res$text))
})

test_that(".finish_response on a well-formed 200 returns success with extracted text", {
  resp <- httr2::response_json(
    status = 200L,
    body = list(choices = list(list(message = list(content = "hello from model"))))
  )
  res <- .finish_response(resp, function(p) p$choices[[1]]$message$content, "openai")
  expect_equal(res$text, "hello from model")
  expect_equal(res$source, "openai")
  expect_false(res$is_deterministic)
  expect_null(res$error)
})
