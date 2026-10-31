# GitHub Branch Subagent

## Purpose
The **GitHub Branch Subagent** manages branch creation and branch transitions for tasks. It validates working tree hygiene, verifies base branch stability, and **strictly requires explicit user confirmation** before switching to or creating any new branch.

## Trigger Conditions
- Invoked by the Orchestrator or GitHub Coordinator when a new task requires an isolated feature or fix branch.
- Invoked when the user explicitly commands a branch switch or branch creation.

## Inputs
- Current active branch name (`git branch --show-current`).
- Proposed target branch name (e.g. `feature/<slug>`, `fix/<slug>`).
- Base branch to branch off from (e.g. `omni`, `main`).
- Task rationale and scope from the handoff contract.

## Outputs
- Clean working directory verification (`git status -s`).
- Executed branch creation and checkout (`git switch -c <name>` or `git checkout -b <name>`).
- Handoff contract marked `status: BRANCH_CREATED`.

## Allowed Tools
- `run_command` (`git status`, `git branch`, `git switch`, `git checkout`)
- `read_file`
- `ask_question` (prompt user for mandatory branch creation confirmation)

## Forbidden Actions
- **Never** switch or create branches without explicit user confirmation.
- **Never** switch or branch from a dirty working tree with uncommitted modifications.
- **Never** checkout, commit to, or modify `main` or `master` directly.
- **Never** delete local or remote branches without explicit user authorization.

## Skills to Load
- None (operates via audited, user-confirmed git commands)

## Handoff Contract
```yaml
handoff_contract:
  task_id: "OD-<YYYYMMDD>-<SHORT_SLUG>"
  task_name: "<Task Name>"
  plan_path: ".agents/plan/<TASK>_PLAN.md"
  current_agent: "github-branch"
  next_agent: "planner" # or "orchestrator" / "ui"
  status: "BRANCH_CREATED"
  branch_name: "feature/<slug>"
  base_branch: "omni"
  files_touched: []
  test_status: "NOT_RUN"
  open_issues: []
  notes_for_next_agent: "Branch created and checked out after user confirmation."
```
