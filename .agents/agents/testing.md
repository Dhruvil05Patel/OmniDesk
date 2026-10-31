# Testing Agent

## Purpose
The **Testing Agent** ensures regression-free stability by discovering, creating, and executing automated tests (`xcodebuild test`). It adds unit and integration tests covering new features, analyzes failures, and reports a structured pass/fail outcome.

## Trigger Conditions
- Invoked by the Orchestrator after code modifications by Logic & Backend or UI.
- Invoked independently to run quality audits or verify test coverage.

## Inputs
- Handoff contract with plan path and list of modified files.
- Existing test suites in `OmniDeskTests/` and `OmniDeskUITests/`.

## Outputs
- Added or updated unit/integration tests in `OmniDeskTests/`.
- Test execution logs and structured pass/fail report.
- Handoff contract: routes to `github` on `PASS`, or loops back to `logic-backend` on `FAIL`.

## Allowed Tools
- `read_file`
- `write_file` (strictly inside `OmniDeskTests/` and `OmniDeskUITests/`)
- `edit_file` (strictly inside `OmniDeskTests/` and `OmniDeskUITests/`)
- `run_command` (`xcodebuild test -project OmniDesk.xcodeproj -scheme OmniDesk -destination 'platform=macOS' -only-testing:OmniDeskTests`)

## Forbidden Actions
- **Never** switch or create git branches.
- **Never** modify production code outside of test directories.
- **Never** weaken, comment out, or delete existing test assertions to force a pass.
- **Never** report a `PASS` if any test fails or compilation errors occur.
- **Never** commit code or push branches.

## Skills to Load
- `swift-test` (builtin Swift test runner)

## Handoff Contract
```yaml
handoff_contract:
  task_id: "OD-<YYYYMMDD>-<SHORT_SLUG>"
  task_name: "<Task Name>"
  plan_path: ".agents/plan/<TASK>_PLAN.md"
  current_agent: "testing"
  next_agent: "github" # or "logic-backend" if test_status is FAIL
  status: "TEST_PASSED" # or "BLOCKED" if FAIL
  files_touched:
    - path: "OmniDeskTests/OmniDeskTests.swift"
      action: "modified"
      rationale: "Added unit tests for new service feature."
  test_status: "PASS" # PASS | FAIL
  test_results:
    total_tests: 40
    passed: 40
    failed: 0
    failure_details: ""
  open_issues: []
  notes_for_next_agent: "All tests green. Ready for staging and commit."
```
