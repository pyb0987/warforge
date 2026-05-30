---
iteration: 26
date: "2026-05-30"
type: additive
verdict: improved
files_changed: [".gitignore", ".agents/skills/btw/SKILL.md", ".agents/skills/card-designer/SKILL.md", "scripts/check_harness_v2_surface.py", "Plans.md", ".claude/traces/evolution/026-codex-review-fixes.md"]
refs: [25, ".claude/traces/search-set.md", "AGENTS.md"]
---

## Iteration 026: Codex review finding fixes

### Trigger
Review of the AI Agent Meta-Harness v2 migration found four follow-up issues:
local Claude worktrees were visible to `git status`, copied `.agents` skills
still used Claude-only model/role names, the card-designer skill referenced a
missing `~/.Codex` methodology file, and the v2 surface guard did not directly
assert active `SS-012` or absence of competing trace roots.

### Diagnosis
The v2 migration direction was coherent, but the Codex adapter surface had two
artifact-boundary risks:

- `.claude/worktrees/` contained local scratch worktrees with machine-local
  `.git` pointer files and should not be staged with the harness migration.
- `.agents/skills/` had been copied from Claude skill content and still named
  `opus`, `haiku`, `subagent_type`, and a non-existent `~/.Codex` reference.

The guard also relied on broad marker checks. That allowed the surface to pass
even if `SS-012` was removed from the Active search-set section or if a
competing `.harness/traces` tree appeared later.

### Change
- Added `.claude/worktrees/` to `.gitignore`.
- Reworded `.agents/skills/btw/SKILL.md` to use Codex `explorer`/`default`
  roles only when the user explicitly asks for delegation.
- Reworded `.agents/skills/card-designer/SKILL.md` to use Codex-compatible
  independent review-pass language and repo-local checklist references.
- Strengthened `scripts/check_harness_v2_surface.py` to verify active `SS-012`,
  verify the exact `SS-012` command, and reject competing `.harness/traces`
  files.
- Updated `Plans.md` with the completed review remediation follow-up.

### Result
- Post-change verification: PASS
  `python3 scripts/check_harness_v2_surface.py`
  - PASS: Warforge AI Agent Meta-Harness v2 surface is coherent.
- Post-change verification: PASS
  `python3 /Users/fainders/personal/claude-code-harness/scripts/run-search-set.py --search-set .claude/traces/search-set.md --cwd . --case SS-012`
  - SS-012 PASS.
  - run-search-set: PASS (1 Active case(s)).
- Focused guard verification: PASS
  `python3 scripts/lint_card_spawn.py`
  - command exited 0.
- Focused guard verification: PASS
  `python3 -m unittest scripts.tests.test_lint_card_spawn`
  - Ran 10 tests in 0.007s, OK.
- Skill marker sanity check: PASS
  `rg -n "model:|subagent_type|haiku|opus|~/.Codex|~/.claude|Agent 도구|Explore" .agents/skills`
  - No matches.
- Worktree status check: PASS
  `git status --short`
  - `.claude/worktrees/` no longer appears.
- Full GUT suite: SKIPPED
  `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
  - This follow-up changed harness docs, Codex skills, `.gitignore`, and a
    Python surface guard only. No Godot gameplay/card data/generated code was
    touched.

### Lesson
Codex adapter migrations should treat copied runtime skills as executable
surface, not documentation. Search-set guards should assert the specific Active
case they depend on, and local scratch worktrees should stay outside the commit
surface.
