# Prompt Templates (Low-Intervention Workflow)

## 1) Safe single-bug fix

Use this with Codex:

```text
Task: <single specific bug>

Apply Execution rules strictly.
If repo is dirty, snapshot first.
If baseline is unclear, compare against origin/main and report before edits.
Do not continue if scope expands; stop and ask for a new branch/task.
```

## 2) Hands-off mode

```text
Task: <single specific bug>

Operate in low-intervention mode:
- choose safe defaults without asking me unless blocked
- create snapshot branch if dirty
- create one fix branch for one concern
- run ./scripts/quality-gate.sh before handoff
- report branch, changed files, tests/checks, and plain-English outcome
```

## 3) Start a safe fix branch from terminal

```bash
./scripts/safe-fix.sh "<single specific bug>"
```

This automatically:
- snapshots dirty work to `codex/wip-*`
- returns to `main`
- creates a fresh `codex/fix-YYYY-MM-DD-<topic>` branch
