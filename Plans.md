# Warforge Harness Plans

Status legend: TODO, DOING, DONE, SKIPPED.
Last updated: 2026-07-02

## Completed Plan: Playable Prototype Completion After Difficulty

Done when: Warforge has a coherent player-facing loop after the current
difficulty pass: the player can understand run progress/unlocks, make upgrade
attachment decisions without guessing, learn the main build actions in context,
and read growth-chain feedback during play. Difficulty tuning is intentionally
paused except for bug fixes.

Source: `.claude/backlog.md` P1 residuals, `docs/design/replay.md`,
`docs/design/upgrade.md`, and the 2026-07-02 handoff.

Operating rules:
- Keep difficulty numbers frozen unless a regression makes a run unplayable.
- Prefer player-facing clarity before additional sim or balance work.
- Use focused GUT tests for each UI/flow slice; run full GUT before closing a
  feature slice that touches shared scenes, autoloads, or run flow.
- Preserve the existing `.claude/traces/` history and Tier 0 sim protections.

| ID | Status | Task | Done When | Suggested Verification |
|----|--------|------|-----------|------------------------|
| G6 | DONE | Detailed meta progression screen | RunStartScreen can show all commander/talisman unlock states, completed achievements, and locked goals without starting a run. | PASS `test_meta_progress.gd`; PASS `test_run_start_screen.gd` |
| G7 | DONE | Upgrade attachment comparison UX | Buying an upgrade surfaces eligible field targets with current slot count, affordability/eligibility feedback, and a concise value preview before attach. | PASS `test_build_phase_upgrade_shop.gd` |
| G8 | DONE | In-run tutorial overlay | First-run guidance appears at the relevant build actions and can be dismissed/saved without blocking experienced players. | PASS `test_build_phase_tutorial.gd` |
| G9 | DONE | Growth-chain readability pass | Chain feedback highlights trigger count, source/target, and reward events clearly enough to explain why the board grew. | PASS `test_chain_visual.gd`; PASS `test_chain_engine.gd`; PASS full GUT 1124/1124 |
| G10 | DONE | Sim ON_REROLL parity fix | Headless sim reroll path triggers ON_REROLL effects that live `game_manager.gd` already fires. | PASS `test_sim_shop_logic.gd`; PASS `test_headless_runner.gd`; PASS `test_steampunk_system.gd`; PASS `test_pawnbroker_reroll.gd`; PASS full GUT 1129/1129 |
| G11 | DONE | Stale design backlog cleanup | Design backlog no longer lists already-implemented boss reward/system decisions as unresolved. | PASS doc review; PASS `git diff --check` |

## Active Plan: Prototype Hardening After Player-Facing Loop

Done when: the current playable run loop has fewer misleading UI descriptions and
the remaining sim parity gaps are explicitly separated from completed live/sim
paths. This plan keeps difficulty tuning paused unless a defect is found.

Source: `docs/design/backlog.md` technical debt, `.claude/backlog.md` P2/P3/P4,
and the completed G6-G11 playable loop work.

Operating rules:
- Keep changes narrow and testable; prefer one user-visible or parity issue per
  slice.
- Do not change card data values while fixing description or parity plumbing.
- For generated descriptions, change codegen inputs/scripts and regenerate output.

| ID | Status | Task | Done When | Suggested Verification |
|----|--------|------|-----------|------------------------|
| H1 | DONE | desc_gen multi-block listen separation | `pr_transcend` and future multi-OE cards render separate reaction prefixes per listen target instead of merging under one misleading prefix. | PASS `python3 -m unittest scripts.tests.test_card_desc_codegen`; PASS `python3 scripts/codegen_card_db.py --check`; PASS `git diff --check` |
| H2 | DONE | Sim pending free-reroll parity | Headless sim can represent live free-reroll generation/consumption separately from paid ON_REROLL triggers. | PASS `test_sim_shop_logic.gd`; PASS `test_headless_runner.gd`; PASS `test_pawnbroker_reroll.gd`; PASS `test_neutral_system.gd`; PASS full GUT 1133/1133 |
| H3 | DONE | Combat talisman regression coverage | Combat-level tests pin 금간 해골/전쟁 북 live behavior, not only query/data helpers. | PASS `test_talisman.gd` 38/38; PASS full GUT 1136/1136 |
| H4 | DONE | Merge/chain polish pass | BuildPhase shows the latest merge result/reward state, and ChainVisual line labels include trigger order beside the board animation. | PASS `test_build_phase_merge_bonus.gd` 5/5; PASS `test_chain_visual.gd` 5/5; PASS full GUT 1137/1137 |
| H5 | DONE | Sim diversity next-slice triage | Re-measured current non-difficulty sim baseline and identified focused-strategy variance as the next measurable weakness. | PASS 140-run batch: weighted 0.4850, coverage 0.2175, soft_steampunk 1/20, soft_druid 2/20 |
| H6 | DONE | AI bench-space sale bug fix | AI no longer sells board cards while trying to create bench space for a purchase; the fix improves the 140-run sim snapshot without touching difficulty numbers. | PASS `test_ai_agent.gd` 14/14; PASS 140-run batch weighted 0.4903; PASS full GUT 1139/1139 |
| H7 | DONE | Military target warning cleanup | Military `r_conditional` no longer pre-resolves revive-scope-only targets (`self_all`, `self_and_adj_all`) in the generic dispatcher. | PASS `test_military_system.gd` 81/81; PASS 1-run batch smoke with no `[military r_conditional]` warnings; PASS full GUT 1141/1141 |
| H8 | DONE | GUT warning-noise cleanup | Remaining full-suite warnings are either expected explicitly or eliminated, so future warning regressions are easier to see. | PASS `test_genome.gd` 10/10; PASS `test_military_system.gd` 81/81; PASS full GUT 1141/1141 with no GUT warning total |
| H9 | TODO | Next playability slice selection | Choose and execute the next completion-oriented slice after warning cleanup, prioritizing a playable-game gap over more balance tuning. | inspect handoff/backlog; focused tests for selected slice |

## Completed Plan: AI Agent Meta-Harness V2 Adapter Migration

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
