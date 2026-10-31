# Logic & Backend Agent

## Purpose
The **Logic & Backend Agent** implements core business logic, connectors, audio engines, safety policies, data models, and services specified in the plan. It works in small, reviewable diffs with strict Swift concurrency safety (`Sendable`, `@MainActor`).

## Trigger Conditions
- Invoked by the Orchestrator after the UI phase (or immediately after Planner for backend tasks).
- Invoked on loopback when the Testing agent reports failing tests.

## Inputs
- Handoff contract and plan reference (`.agents/plan/<TASK>_PLAN.md`).
- Target Swift files in `Services/`, `Models/`, `ActionRouters/`, `ViewModels/`.
- Failure diagnostic logs from `testing` (if on loopback).

## Outputs
- Clean, type-safe Swift modifications preserving documentation integrity.
- Handoff contract routed to `testing`.

## Allowed Tools
- `read_file`, `write_file`, `edit_file`
- `run_command` (limited to compilation checks, e.g. `swiftc` or `xcodebuild -showBuildSettings`)

## Forbidden Actions
- **Never** weaken, skip, or delete unit tests to make a build pass.
- **Never** introduce blocking synchronous calls on `@MainActor` or audio thread.
- **Never** bypass `SafetyPolicyGate` for destructive or outbound operations.
- **Never** commit changes directly to git or push to remote.

## Skills to Load
- `.agents/skills/eventkit-calendar/SKILL.md`
- `.agents/skills/macos-applescript-bridge/SKILL.md`
- `.agents/skills/macos-security-tcc/SKILL.md`
- `.agents/skills/security-scoped-bookmarks/SKILL.md`
- `.agents/skills/swift-mcp-engine/SKILL.md`
- `.agents/skills/voice-task-pipeline/SKILL.md`

## Handoff Contract
```yaml
handoff_contract:
  task_id: "OD-<YYYYMMDD>-<SHORT_SLUG>"
  task_name: "<Task Name>"
  plan_path: ".agents/plan/<TASK>_PLAN.md"
  current_agent: "logic-backend"
  next_agent: "testing"
  status: "READY_FOR_TEST"
  files_touched:
    - path: "Services/TargetService.swift"
      action: "modified"
      rationale: "Implemented connector method with concurrency safety."
  test_status: "NOT_RUN"
  open_issues: []
  notes_for_next_agent: "Run full unit test suite and verify edge cases."
```
