---
iteration: 24
date: "2026-05-28"
type: additive
verdict: neutral
files_changed: ["AGENTS.md", ".claude/traces/evolution/024-codex-meta-harness-routing.md"]
refs: [".claude/traces/search-set.md", "CLAUDE.md"]
---

## Iteration 024: Codex meta-harness routing 적용

### Trigger
사용자가 작성자가 아닌 일반 사용자 관점에서 이 프로젝트에 meta-harness를 적용해보고 싶다고 요청했다.

### Diagnosis
프로젝트에는 이미 풍부한 `.claude/traces/` history와 Active search-set이 있다. Codex용 `.harness/traces/`를 새로 만들면 기존 failures/evolution/experiments evidence가 갈라질 위험이 있다.

Codex가 기본으로 읽는 `AGENTS.md`가 없었으므로, 기존 Claude harness 정책을 Codex가 사용할 수 있는 프로젝트 지시 표면으로 얇게 반영하는 것이 가장 작은 적용이다.

### Change
- `AGENTS.md`를 추가해 Codex가 기존 `.claude/traces/`를 trace root로 재사용하도록 했다.
- 자연어 기반 routing 규칙을 추가해 사용자가 skill 이름을 몰라도 반복 실패, 리뷰, 실험 루프를 agent가 판단할 수 있게 했다.
- 기존 Active search-set은 유지했다.

### Result
- Trace root: `.claude/traces/` 유지.
- Active verify: `.claude/traces/search-set.md`의 기존 SS-001/SS-002/SS-006/SS-007/SS-008/SS-009/SS-011 유지.
- Verification: PASS `python3 scripts/lint_card_spawn.py`; PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` — 10 tests OK.

### Lesson
의미 있는 trace history가 많은 프로젝트에서는 meta-harness 적용의 핵심이 새 history를 만드는 것이 아니라 기존 history를 새 agent runtime이 자연스럽게 읽도록 routing surface를 추가하는 것이다.
