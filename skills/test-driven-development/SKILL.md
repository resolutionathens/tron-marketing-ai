---
name: test-driven-development
model: sonnet
effort: medium
description: "Drive behavior changes and bug fixes with tests first. Use when implementing new logic, changing behavior, adding edge cases, or fixing a bug: 'write the test first', 'do TDD', 'add a regression test', 'test this behavior', 'reproduce this bug in a test', or 'red green refactor'. Discovers the repository's test stack before running commands and complements browser, accessibility, and CI skills."
allowed-tools:
  - Bash
  - Read
scout:
  surface: developer
  effects: [report]
---

# Test-Driven Development

Use tests as durable proof of behavior. This skill governs implementation work, not documentation,
static content, or configuration that cannot change runtime behavior.

## Before writing a test

1. Inspect the repository's package or build manifest, existing neighboring tests, README, and CI
   configuration. Identify the focused-test, full-suite, typecheck, and build commands. Do not assume
   `npm test` or install a test framework.
2. State the behavior to prove in one sentence. For a bug, state the reported failure and the expected
   result.
3. Pick the highest useful seam. Prefer a small unit test for pure logic, an integration test for a
   system boundary, and a browser test only for a critical user flow. Use the available browser tooling for
   runtime inspection; route WCAG checks to `tron:a11y-scan`.

## Red, green, refactor

1. Write one descriptive test for the behavior or bug reproduction.
2. Run the focused test and confirm it fails for the expected reason. A test that passes before the
   implementation does not prove the change.
3. Make the smallest production change that makes the test pass.
4. Run the focused test again.
5. Refactor only while the test stays green. Test observable outputs and state rather than implementation
   details. Prefer real implementations or fakes over interaction mocks.
6. Repeat one behavior at a time. Keep test setup readable; duplication is acceptable when it makes each
   case explain itself.

## Bug fixes

For a reproducible bug, add a regression test that fails before the fix and passes after it. If a test
cannot express the issue, document why and preserve alternate evidence such as a browser reproduction,
request trace, or deterministic script output. Do not claim a regression guard exists when it does not.

## Verification

After the last code change, run the repository's relevant focused checks and its full applicable suite.
Run typecheck, build, and browser verification when the repository uses them and the change warrants them.
Report the exact commands and results. Do not rerun unchanged checks merely for reassurance.

### Performance and Bun spy conventions

- Keep listing-performance assertions independent of the host. Do not set a pass/fail threshold from
  elapsed time or a fixed filesystem `stat` count: machine load, filesystem behavior, fixtures, and
  implementation details make those benchmarks flaky. Assert a stable work invariant instead, such as
  the number of queries or requests, page-size bounds, or a comparison within the same controlled run.
  Treat elapsed-time measurements as diagnostic evidence unless the repository provides a calibrated,
  repeatable benchmark harness.
- With a Bun spy, read every needed call count or call argument from `spy.mock.calls` **before**
  calling `spy.mockRestore()`. Store those values first, then restore the original implementation and
  make assertions from the captured values; restoring can make the spy history unavailable.

## Rules

- Do not disable, skip, or weaken a test to make the suite pass.
- Test behavior at the same level of abstraction as the repository's existing suite.
- Keep tests isolated from time, ordering, network, and production data where practical.
- If the repository has no test harness, report the gap and propose the smallest verification path instead
  of inventing an unapproved framework.
- This skill does not commit, open a PR, or replace `tron:git-commit`, `tron:git-pr`, or `tron:circleci`.

## When dispatched

Run available repository checks autonomously. If a missing test strategy, destructive fixture operation,
or external dependency requires a product or security decision, report the blocker and stop.
