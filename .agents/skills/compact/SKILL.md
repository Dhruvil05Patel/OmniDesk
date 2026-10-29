---
name: compact
description: Summarizes the full Antigravity conversation history into a structured Markdown document. Automatically parses user requests, architectural decisions, code modifications, bug resolutions, and test results from the conversation trajectory. Use when the user invokes /compact, asks to summarize the conversation, or wants to compact and preserve session state in a markdown file.
---

# Compact Skill: Conversation & Session Summarizer

The **Compact** skill captures the complete history of an Antigravity collaboration session and distills it into a clean, permanent Markdown file. It ensures context is preserved across context resets, compactions, and developer handovers.

## When to Use This Skill
- The user types `/compact` in the chat prompt.
- The user asks to "summarize the conversation", "document what we did", or "save session history to a markdown file".
- Before major context resets or task transitions when a persistent record of changes and decisions is required.

---

## Workflow

### 1. Execute the Transcript Summarizer
Run the helper script provided in this skill to extract the exact chronological trajectory from the local Antigravity transcript:

```bash
python3 .agents/skills/compact/scripts/summarize_conversation.py --output conversation_summary.md
```

*(If running globally, the script is located at `~/.gemini/config/skills/compact/scripts/summarize_conversation.py`)*.

Options:
- `--transcript <path>`: Explicit path to `transcript.jsonl` (auto-detects the active session if omitted).
- `--output <path>`: Target markdown file path (defaults to `conversation_summary.md` in the current workspace).

### 2. Augment the Summary with High-Level Syntheses
Review the generated summary and enhance it with executive-level context:
1. **Goal & Vision**: The overarching objective of the user and project.
2. **Key Architectural Decisions**: Core patterns, library choices, and security considerations decided during the session.
3. **Inventory of Changes**: Specific files modified, created, and deleted.
4. **Bugs & Resolutions**: Root cause analysis and the exact fix for any issues encountered (e.g. API errors, entitlement issues, UI contrast quirks).
5. **Test Status**: Verification commands run and test pass confirmation.
6. **Next Steps**: Actionable tasks remaining on the project roadmap.

### 3. Save & Notify
1. Ensure the markdown file is saved to the workspace root or requested path.
2. Provide a concise, clickable link to the generated summary markdown file in your response.

---

## Markdown Output Structure Standards

Every generated summary must follow this structure:

```markdown
# Session Summary: [Project / Feature Name]

**Date:** YYYY-MM-DD  
**Conversation ID:** `<conversation-id>`  
**Branch:** `<active-git-branch>`  

---

## 1. Executive Summary & Project Goal
[Concise 2-3 sentence overview of what was accomplished]

## 2. Chronological Request History
- **Request 1:** ...
- **Request 2:** ...

## 3. Technical & Architectural Decisions
- [Key decision 1]
- [Key decision 2]

## 4. Key File Modifications
| File Path | Status | Description |
| :--- | :--- | :--- |
| `path/to/file` | Modified / Created | Summary of change |

## 5. Diagnostic & Bug Resolutions
- **Issue:** [Description of problem]
  - **Root Cause:** [Why it happened]
  - **Fix Applied:** [How it was resolved]

## 6. Verification & Test Results
- [List test commands and pass status]

## 7. Next Roadmap Items
- [ ] Task 1
- [ ] Task 2
```

---

## Resources
- **Helper Script:** [scripts/summarize_conversation.py](scripts/summarize_conversation.py)
