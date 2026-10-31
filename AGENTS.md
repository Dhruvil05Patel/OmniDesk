# OmniDesk — Multi-Agent Development Instructions & System Guidelines
**Document Location:** `AGENTS.md` (Repository Root)  
**Target Assistant:** OmniDesk (Native macOS "Jarvis-Style" Operating Layer)  
**Active Environment:** macOS 14 (Sonoma), macOS 15 (Sequoia)+ | Swift 5.10 / Swift 6  

---

## 1. Project Overview & Architectural Stack

**OmniDesk** is an ambient, personal macOS Assistive Operating Layer designed to unify communication, scheduling, and desktop task automation with an extensible voice AI copilot.

- **Frontend / Client**: Pure Swift + SwiftUI (macOS native). Glassmorphic rendering, zero Electron overhead, `@MainActor` UI thread safety.
- **Audio & Speech Pipeline**: Apple `AVAudioEngine` + `SFSpeechRecognizer` continuous dictation. Low-latency RMS metering and state-guarded audio unit taps.
- **AI Inference Engine**: Groq Cloud API (`llama-3.1-8b-instant`) with strict JSON Schema intent classification and structured tool calling.
- **Desktop Connectors**: In-process Swift services interfacing with `EventKit` (Calendar), `NSAppleScript` (Mail), Security-Scoped Bookmarks (Obsidian), and `NSWorkspace`/POSIX signals (App Control).
- **Zero-Trust Safety & Audit Gate**: `SafetyPolicyGate` with continuation-based task suspension for destructive/outbound operations, hands-free voice confirmation, and append-only SHA-256 hashed audit logging.
- **Extensibility Protocol**: Native Model Context Protocol (MCP) JSON-RPC 2.0 server over `stdio` (`MCPServerEngine`).
- **macOS Security Model**: Developer ID / Hardened Runtime with explicit TCC entitlements (`ENABLE_APP_SANDBOX = NO`).

---

## 2. Build, Test & Run Commands

All commands are executed via standard Xcode command-line tools from the repository root:

### Build Application
```bash
xcodebuild -project OmniDesk.xcodeproj -scheme OmniDesk -destination 'platform=macOS' build
```

### Run Unit Test Suite
```bash
xcodebuild test -project OmniDesk.xcodeproj -scheme OmniDesk -destination 'platform=macOS' -only-testing:OmniDeskTests
```

### Run Single Unit Test
```bash
xcodebuild test -project OmniDesk.xcodeproj -scheme OmniDesk -destination 'platform=macOS' -only-testing:OmniDeskTests/OmniDeskTests/<testMethodName>
```

---

## 3. Code Style & Engineering Standards

1. **Swift Concurrency**: Enforce Swift 6 readiness. All UI models must be annotated with `@MainActor`. Data structures crossing concurrency boundaries must conform to `Sendable`.
2. **No Force Unwrapping**: Avoid `!` force-unwraps; always use `guard let` or `if let` with meaningful logging or typed error throws.
3. **Design Tokens**: Never hardcode raw hex colors or magic spacing dimensions in SwiftUI views. Always reference semantic design tokens in `Utilities/DesignTokens.swift` (e.g., `Color.omniCardSurface`, `Color.omniBorder`, `Spacing.md`).
4. **Zero-Trust Interception**: Any connector method that performs an outbound send, data deletion, or process termination must route through `SafetyPolicyGate.shared.evaluatePolicy(action:payload:)`.
5. **Documentation Integrity**: Preserve existing comments, pragmas, and docstrings unless explicitly refactoring that specific component.

---

## 4. Multi-Agent Development Team Roster

OmniDesk utilizes a team of specialized subagents located in `.agents/agents/`. Each agent has a single, strictly bounded responsibility:

| Agent Name | Definition File | Role & Trigger |
| :--- | :--- | :--- |
| **Orchestrator** | `.agents/agents/orchestrator.md` | Top-level dispatcher. Ingests tasks, sequences agents, and handles loopback loops. |
| **Planner** | `.agents/agents/planner.md` | Converts user requests into architectural plans in `.agents/plan/<TASK>_PLAN.md`. Read-only on source code. |
| **UI/UX** | `.agents/agents/ui.md` | Researches Apple HIG, writes design rationales citing sources, and implements SwiftUI views. |
| **Logic & Backend** | `.agents/agents/logic-backend.md` | Implements Swift services, connectors, data models, and audio pipes in small, reviewable diffs. |
| **Testing** | `.agents/agents/testing.md` | Runs `xcodebuild test`, writes new unit tests, and validates regressions. Never touches production code. |
| **GitHub Coordinator** | `.agents/agents/github.md` | Coordinates staging, diff comparison, pre-flight review, and confirmed remote pushes. |
| **GitHub Branch** | `.agents/agents/github-branch.md` | Verifies clean working tree and creates/switches branches **only after explicit user confirmation**. |
| **GitHub Commit** | `.agents/agents/github-commit.md` | Stages changes file-wise and writes Conventional Commit messages (`feat`, `fix`, `test`). |
| **GitHub Push** | `.agents/agents/github-push.md` | Pushes branch to origin **only after explicit user confirmation**. Never pushes to `main`. |
| **GitHub Compare** | `.agents/agents/github-compare.md` | Compares and summarizes cumulative diffs against base branch (`origin/main`). |
| **GitHub PR Review** | `.agents/agents/github-pr-review.md` | Audits diff for bugs and secrets; drafts markdown Pull Request description. |
| **GitHub PR** | `.agents/agents/github-pr.md` | Verifies mergeability and creates Pull Request **only after explicit user confirmation**. |

---

## 5. Standard Development Workflow

Every task follows a strict five-phase quality pipeline:

```
[User Request] 
      │
      ▼
0. Branch (GitHub Branch) ──► Confirms & creates feature branch (if not on one)
      │
      ▼
1. Plan (Planner) ──────────► Outputs .agents/plan/<TASK>_PLAN.md
      │
      ▼
2. Design (UI/UX) ──────────► Researches HIG & updates SwiftUI Views (if applicable)
      │
      ▼
3. Logic (Logic & Backend) ─► Implements Swift connectors/services in small diffs
      │
      ▼
4. Test (Testing) ──────────► Executes xcodebuild test (Loopback to Logic on FAIL)
      │ (PASS: 0 Failures)
      ▼
5. GitHub Coordinator ──────► Commit ➔ Compare ➔ Review ➔ Push (confirmed) ➔ PR (confirmed)
```

### Loopback Rule
If `Testing` reports any failed assertions or compiler errors, the `Orchestrator` returns the handoff contract and failure diagnostics directly to `Logic & Backend` (or `UI/UX`). No code moves to version control while tests are failing.

---

## 6. Zero-Trust & GitHub Safety Rules

### GitHub Safety Guardrails
- **Mandatory Branch Change Confirmation**: Agents must NEVER switch branches (`git checkout`, `git switch`), create a new branch (`git checkout -b`, `git switch -c`), or change the current active working branch without asking for and receiving explicit user confirmation first. The confirmation prompt must specify the current branch, proposed target branch, and rationale. Use `github-branch` to safely execute confirmed branch transitions.
- **Branch Protection**: Never commit or push directly to `main` or `master`. Always work on a confirmed feature or fix branch.
- **No Force Pushing**: `git push --force` and `git push --force-with-lease` are permanently forbidden.
- **Mandatory User Confirmation for Push & PR**: The agent must ask for and receive explicit user confirmation before the first push of any branch and before creating or submitting a Pull Request.
- **Conflict-Free PR Verification**: Before opening a Pull Request, `github-pr` must verify zero merge conflicts against the target base branch using `git merge-tree`.
- **Secret Sanitization**: Never stage or commit `Secrets.xcconfig`, `.env`, API keys, or private tokens. Always check `git diff --cached` before committing.
- **No Monolithic Commits**: Commit phase-wise and file-wise with Conventional Commit messages.

---

## 7. Knowledge Base & System Pointers

- **Architectural Plans**: [`.agents/plan/`](.agents/plan/)
  - Master Multi-Agent Architecture: [`.agents/plan/AGENT_SYSTEM_PLAN.md`](.agents/plan/AGENT_SYSTEM_PLAN.md)
  - Connector Architecture: [`.agents/plan/CONNECTOR_PLAN.md`](.agents/plan/CONNECTOR_PLAN.md)
  - Intent Routing & Safety: [`.agents/plan/INTENT_ROUTING_AND_MODAL_FIX_PLAN.md`](.agents/plan/INTENT_ROUTING_AND_MODAL_FIX_PLAN.md)
  - UI Modal Wiring: [`.agents/plan/WIRING_PLAN.md`](.agents/plan/WIRING_PLAN.md)
- **Domain Skills**: [`.agents/skills/`](.agents/skills/)
  - EventKit Calendar: [`.agents/skills/eventkit-calendar/SKILL.md`](.agents/skills/eventkit-calendar/SKILL.md)
  - AppleScript Bridge: [`.agents/skills/macos-applescript-bridge/SKILL.md`](.agents/skills/macos-applescript-bridge/SKILL.md)
  - Security & TCC: [`.agents/skills/macos-security-tcc/SKILL.md`](.agents/skills/macos-security-tcc/SKILL.md)
  - Accessibility Automation: [`.agents/skills/macos-accessibility-automation/SKILL.md`](.agents/skills/macos-accessibility-automation/SKILL.md)
  - Security-Scoped Bookmarks: [`.agents/skills/security-scoped-bookmarks/SKILL.md`](.agents/skills/security-scoped-bookmarks/SKILL.md)
  - Swift MCP Engine: [`.agents/skills/swift-mcp-engine/SKILL.md`](.agents/skills/swift-mcp-engine/SKILL.md)
  - Voice Pipeline: [`.agents/skills/voice-task-pipeline/SKILL.md`](.agents/skills/voice-task-pipeline/SKILL.md)
  - Compact & Summary: [`.agents/skills/compact/SKILL.md`](.agents/skills/compact/SKILL.md)
- **System Specifications**: [`.agents/summary.md`](.agents/summary.md)
