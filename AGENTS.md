# Engineering Guardrails (Repo-Wide)

This repo uses a strict anti-regression workflow.

## Non-negotiable workflow
1. Never edit directly on `main`.
2. Before any edits, check if the tree is dirty.
3. If dirty, create a WIP snapshot branch and commit all current changes.
4. Return to `main`, then create a fresh `codex/fix-<single-topic>` branch.
5. Keep each branch focused on one concern only:
   - policy logic
   - UDP/transport
   - VPN lifecycle
   - UI toggle wiring
6. Add or update regression tests in the same change set as code edits.
7. Run the quality gate before handoff.
8. If scope expands, stop and ask for a new branch/task.

## Required reporting format in handoff
- Current branch
- Files changed
- Tests/checks run and pass/fail
- Plain-English summary (minimal jargon)

## Quality gates
Run:
- `./scripts/quality-gate.sh`

Regression expectations are documented in:
- `docs/regression-matrix.md`

## Simple plain-English intent
Fix one thing at a time, lock it with tests, and do not stack unrelated changes in the same branch.
