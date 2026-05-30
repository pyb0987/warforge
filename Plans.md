# Warforge Harness Plans

Status legend: TODO, DOING, DONE, SKIPPED.
Last updated: 2026-05-30

## Active Plan: AI Agent Meta-Harness V2 Adapter Migration

Done when: Warforge has a v2 contract/plan surface, keeps existing `.claude`
history intact, and passes the focused harness/card-spawn guards after
migration. Source: `pyb0987/ai-agent-meta-harness`.

| ID | Status | Task | Evidence |
|----|--------|------|----------|
| 1 | DONE | Inspect existing Warforge harness history and project instructions. | `.claude/traces/`, `AGENTS.md`, `CLAUDE.md`, and README read. |
| 2 | DONE | Keep `.claude/traces/` as the active trace root. | Existing evolution, failure, experiment, review, and active search-set history is meaningful. |
| 3 | DONE | Add v2 operating surface without replacing design memory. | `spec.md`, `Plans.md`, and `AGENTS.md` source guidance. |
| 4 | DONE | Add argv-safe surface verification for pyb runner. | `SS-012` in `.claude/traces/search-set.md`; `python3 scripts/check_harness_v2_surface.py`. |
| 5 | DONE | Record the migration in harness evolution history. | `.claude/traces/evolution/025-ai-agent-meta-harness-v2.md`. |
| 6 | DONE | Run post-change focused guards. | PASS `python3 scripts/check_harness_v2_surface.py`; PASS pyb `run-search-set.py --case SS-012`; PASS `python3 scripts/lint_card_spawn.py`; PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` - 10 tests OK. |

## Backlog

| ID | Status | Task | Notes |
|----|--------|------|-------|
| B1 | TODO | Convert legacy Active search-set commands to argv-safe scripts. | Existing SS-001/002/006/007/008/009/011 use shell syntax; preserve them until each is migrated carefully. Full pyb `run-search-set.py` over all Active cases is intentionally not used yet. |
| B2 | TODO | Decide whether to migrate traces from `.claude/traces/` to `.harness/traces/`. | Only if Codex becomes primary runtime and a reviewed copy/move plan exists. |
| B3 | TODO | Install autoresearch protection assets if a new fixed-evaluator loop resumes. | Keep Tier 0 evaluator/protected file policy intact. |

## Completed Follow-up: Codex Review Finding Remediation

Done when: review findings from the v2 migration are addressed without changing
the active trace root or broadening the harness migration scope.

| ID | Status | Task | Evidence |
|----|--------|------|----------|
| R1 | DONE | Exclude local Claude worktrees from commit surface. | `.gitignore` ignores `.claude/worktrees/`; `git status --short` no longer lists that tree. |
| R2 | DONE | Port `.agents/skills/btw` away from Claude-only model/role names. | No `opus`, `subagent_type`, or `Explore` markers remain under `.agents/skills`. |
| R3 | DONE | Port `.agents/skills/card-designer` away from `haiku` and missing `~/.Codex` reference. | Skill points to repo docs/memory and Codex-compatible review-pass language. |
| R4 | DONE | Strengthen the v2 surface guard. | Guard checks active `SS-012` verify stanza and fails on competing `.harness/traces` files. |
