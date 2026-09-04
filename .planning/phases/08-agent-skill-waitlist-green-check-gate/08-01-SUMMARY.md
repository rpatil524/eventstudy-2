---
phase: 08-agent-skill-waitlist-green-check-gate
plan: "01"
subsystem: advisor-surface
tags: [agent-skill, advisor-pro, waitlist, footer, cran-compliance]
status: complete

dependency_graph:
  requires: [07-01, 07-02]
  provides: [es-advisor-skill, advisor-pro-waitlist, advisor-pro-footer]
  affects: [R/advise.R, R/advise_offline.R, README.md]

tech_stack:
  added: []
  patterns:
    - opt-in package option (getOption guard)
    - @noRd internal helper
    - roxygen doc-only topic (@name / NULL pattern)
    - Agent Skill (SKILL.md + reference/) with zero new R code

key_files:
  created:
    - .claude/skills/es-advisor/SKILL.md
    - .claude/skills/es-advisor/reference/workflow.md
    - .claude/skills/es-advisor/reference/function-map.md
    - .claude/skills/es-advisor/reference/interpreting-diagnostics.md
    - R/advisor_pro.R
    - tests/testthat/test_advisor_pro_footer.R
  modified:
    - R/advise.R (footer hook before invisible(x) in print.Advice)
    - R/advise_offline.R (footer hook before invisible(x) in print.es_advice)
    - README.md (Advisor Pro waitlist section added)

decisions:
  - "Agent Skill uses zero new R code — SKILL.md + 3 reference markdown files only"
  - "Footer helper .advisor_pro_footer() uses cat() of a constant string — no network, CRAN-safe"
  - "?advisor_pro implemented via @name advisor_pro / NULL roxygen pattern (mirrors knowledge_base.R)"
  - "Footer tests use capture.output(ret_val <- print(obj)) pattern to assert invisible return"
  - "README Advisor Pro section placed before ## Roadmap"

metrics:
  duration_minutes: 25
  completed: "2026-09-04"
  tasks_completed: 3
  commits: 2

actuals:
  tokens: 18000
  tasks: 3
  commits: 2
---

# Phase 08 Plan 01: Agent Skill + Advisor Pro Waitlist Summary

**One-liner:** Claude Code Agent Skill driving the full advisor loop via existing exports only, plus a CRAN-safe opt-in Advisor Pro waitlist footer with `?advisor_pro` doc topic and README section.

## What Was Built

### Task 1: Agent Skill (SKILL-01/02/03)

Created `.claude/skills/es-advisor/` with:

- **SKILL.md** — frontmatter trigger + full load→run→diagnose→advise→re-run→compare overview, quick entry points for online and offline modes
- **reference/workflow.md** — concrete Rscript one-liners for all 6 stages; provider 3-tier resolution documented
- **reference/function-map.md** — exported function table covering pipeline, diagnostics, advisor, and report functions; all symbols verified against NAMESPACE (`FUNCTION_MAP_GROUNDED`)
- **reference/interpreting-diagnostics.md** — field-by-field guide for `es_diagnostics()` output + no-key offline degrade decision tree

No new R code added. Every cited function name resolves to a real NAMESPACE export.

### Task 2: Advisor Pro Waitlist (BIZ-01/BIZ-02)

- **R/advisor_pro.R** — `?advisor_pro` roxygen doc topic (BIZ-01) advertising the future paid tier + `.advisor_pro_footer()` `@noRd` internal helper (pure `cat()` of a constant string, zero network calls)
- **R/advise.R** — `.advisor_pro_footer()` hooked immediately before `invisible(x)` in `print.Advice`
- **R/advise_offline.R** — `.advisor_pro_footer()` hooked immediately before `invisible(x)` in `print.es_advice`
- **README.md** — `## Advisor Pro (Waitlist)` section with static URL and `options(eventstudy.advisor_pro_footer = TRUE)` snippet

Footer is silent by default; prints a static URL only when the option is TRUE; makes zero network calls (CRAN no-phone-home).

### Task 3: Footer Regression Test + Full-Suite Gate

- **tests/testthat/test_advisor_pro_footer.R** — 21 tests covering:
  - (a) Default-silent for both `print.Advice` and `print.es_advice` (option unset and FALSE)
  - (b) Opt-in prints URL exactly once for both print methods
  - (c) No-network: static body assertion + httr2 mock guard (skipped if httr2 absent)
  - (d) Invisible return preserved in both option states

Full suite result: **1913 PASS, 0 FAIL, 1 WARN (pre-existing), 31 SKIP**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Invisible-return test pattern**
- **Found during:** Task 3 first run
- **Issue:** `withVisible({...sink/close...})` block returned visible=TRUE because `close(conn)` was the last expression
- **Fix:** Replaced with `capture.output(ret_val <- print(obj))` + `expect_identical(ret_val, obj)` — correctly asserts the print return value without testing `withVisible` on a block
- **Files modified:** tests/testthat/test_advisor_pro_footer.R
- **Commit:** 9e3d041

## Self-Check

- [x] `.claude/skills/es-advisor/SKILL.md` exists
- [x] `.claude/skills/es-advisor/reference/` contains 3 .md files
- [x] `R/advisor_pro.R` exists
- [x] `tests/testthat/test_advisor_pro_footer.R` exists
- [x] Commits fd2a6b3 (Task 1) and 9e3d041 (Tasks 2+3) exist in git log
- [x] Full suite green: 1913 PASS 0 FAIL

## Self-Check: PASSED
