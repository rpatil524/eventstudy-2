# Shared fixtures for the provider suite.
#
# Automatically loaded by testthat before running tests. This file is EXTENDED by
# the HTTP-provider plans (06-2 OpenAI-compatible, 06-3 Anthropic) with
# httr2::with_mocked_responses mock-response builders (mock_200 / mock_status /
# mock_malformed / mock_timeout) and the mandatory key-redaction fixtures. In
# 06-1 it carries only the dummy-key / env-var constants used by the CustomProvider
# and resolution tests — none of which touch the network.

# A dummy API key used with withr::local_envvar in tests. It is intentionally
# obvious so a leak assertion (added with the HTTP providers) is unambiguous.
# NEVER a real key.
DUMMY_OPENAI_KEY    <- "sk-DUMMYKEY-openai-should-never-print"
DUMMY_ANTHROPIC_KEY <- "sk-ant-DUMMYKEY-should-never-print"
