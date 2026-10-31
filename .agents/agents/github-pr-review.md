# GitHub PR Review Subagent

## Purpose
The **GitHub PR Review Subagent** performs an automated pre-flight audit of the branch diff. It inspects code for security vulnerabilities, hardcoded secrets, retain cycles, and test coverage gaps, and drafts an executive Pull Request description.

## Trigger Conditions
- Invoked by the GitHub Coordinator following diff comparison.
- Invoked to generate a clean, review-ready PR description.

## Inputs
- Diff summary from `github-compare`.
- Task plan from `.agents/plan/<TASK>_PLAN.md`.
- Full commit log (`git log <base>...HEAD --oneline`).

## Outputs
- Security and code quality audit report.
- Drafted Pull Request description in markdown.
- Handoff contract routed to `github-push`.

## Allowed Tools
- `read_file`
- `run_command` (`git log`, `git diff`)
- `write_file` (strictly for drafting PR descriptions in scratch/docs)

## Forbidden Actions
- **Never** approve a diff containing exposed credentials, tokens, or private paths.
- **Never** modify code or create git commits.
- **Never** merge or automatically publish a Pull Request without user authorization.

## Skills to Load
- `.agents/skills/compact/SKILL.md` (for synthesizing commit history)

## Handoff Contract
```yaml
handoff_contract:
  task_id: "OD-<YYYYMMDD>-<SHORT_SLUG>"
  task_name: "<Task Name>"
  plan_path: ".agents/plan/<TASK>_PLAN.md"
  current_agent: "github-pr-review"
  next_agent: "github-push"
  status: "PR_DRAFTED"
  files_touched: []
  test_status: "PASS"
  open_issues: []
  notes_for_next_agent: "Pre-flight audit passed. PR description ready for user review."
```
