# External Integrations

**Analysis Date:** 2026-09-02

## APIs & External Services

**Financial Data Sources:**
- Yahoo Finance - Stock price data (historical adjusted close prices)
  - SDK/Client: `tidyquant` (preferred) or `quantmod` (fallback)
  - No API key required (public data)
  - Used in: `R/data_download.R` - `download_stock_data()` function

- Kenneth French Data Library - Fama-French factor data
  - Connection: HTTPS download from `https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/`
  - No API key required (public CSV/ZIP files)
  - Used in: `R/data_download.R` - `download_factor_data()` and `download_risk_free_rate()` functions
  - Supported models: FF3 (daily/monthly), FF5 (daily/monthly), momentum factors (daily/monthly)

## Data Storage

**Databases:**
- Not used - Package is analysis-focused, not persistence-focused
- Input data provided as R data frames/tibbles by user
- Results stored in R6 task objects or exported to external formats

**File Storage:**
- Local filesystem only - Users manage their own data files
- Results can be exported to: CSV, Excel (.xlsx), LaTeX (.tex)
  - Export handled by `R/export.R` - `export_results()` function
  - Excel export requires optional `openxlsx` package

**Caching:**
- Not applicable - All computations are deterministic based on input data

## Authentication & Identity

**Auth Provider:**
- None - Package requires no authentication
- All data sources (Yahoo Finance, Kenneth French) are publicly accessible
- No user login or API keys needed

## Monitoring & Observability

**Error Tracking:**
- Not used - Package is standalone library, not a service

**Logs:**
- Base R `warning()` and `stop()` functions for error handling
- Example: data download errors caught and reported in `R/data_download.R` (lines 51-56, 205-206)
- No external logging service integration

## CI/CD & Deployment

**Hosting:**
- GitHub repository: `https://github.com/sipemu/eventstudy`
- CRAN distribution (official R package repository)

**CI Pipeline:**
- GitHub Actions: `.github/workflows/R-CMD-check.yaml`
- Runs on: Ubuntu (latest), macOS (latest), Windows (latest), Ubuntu devel
- Test coverage: Codecov integration
  - Coverage report generated via `covr` package
  - Uploaded to `https://codecov.io/gh/sipemu/eventstudy`
  - Uses `CODECOV_TOKEN` secret

## Environment Configuration

**Required env vars:**
- None - Package operates with no environment variables

**Recommended for CI/CD:**
- `GITHUB_PAT`: GitHub Personal Access Token (set automatically in Actions via `${{ secrets.GITHUB_TOKEN }}`)
- `CODECOV_TOKEN`: For uploading coverage to codecov.io (optional)

**Build environment:**
- `R_KEEP_PKG_SOURCE=yes` - Keeps original source during build (set in CI)

**Secrets location:**
- GitHub Actions secrets configured in repository settings
- No local `.env` files used

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None - Package is not a service

## Data Download Patterns

**Stock Data Download:**
- Function: `download_stock_data()` in `R/data_download.R` (lines 17-74)
- Source: Yahoo Finance via tidyquant/quantmod
- Data format: Adjusted close prices
- Returns: Tibble with columns `symbol`, `date` (dd.mm.yyyy format), `adjusted`

**Factor Data Download:**
- Function: `download_factor_data()` in `R/data_download.R` (lines 90-211)
- Source: Kenneth French Data Library (ZIP archives containing CSV)
- Models: Fama-French 3-factor, 5-factor, momentum
- Frequencies: Daily or monthly
- Returns: Tibble with date and factor columns (normalized to decimal)
- Parsing: Custom CSV parser handling Kenneth French format quirks

**Risk-Free Rate Download:**
- Function: `download_risk_free_rate()` in `R/data_download.R` (lines 226-242)
- Source: Extracted from Fama-French factor data
- Returns: Tibble with `date` and `risk_free_rate` columns

---

*Integration audit: 2026-09-02*
