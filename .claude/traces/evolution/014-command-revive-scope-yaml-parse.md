---
iteration: 14
date: "2026-04-17"
type: refactor
verdict: pending
files_changed:
  - godot/core/military_system.gd (+resolve_command_revive, +resolve_revive_scope)
  - godot/scripts/game/game_manager.gd (_materialize_army — rank 하드코딩 제거)
  - godot/tests/test_military_system.gd (+10 tests for new helpers)
refs:
  - .claude/handoff.md (옵션 군대 재설계 후속 — "통합사령부 revive scope_override YAML↔코드 일관성")
  - .claude/traces/evolution/012-military-r4-r10-axis-split.md (apply_persistent dead path 수정)
---

## Iteration 14: 통합사령부 revive scope resolver (YAML↔코드 drift 제거)

### Problem

`game_manager._materialize_army`는 ml_command의 YAML에 선언된
`revive_scope_override.target` 문자열(`self_enhanced` / `self_all` /
`self_and_adj_all`)을 **읽지 않고**, `rank` 값으로 scope를 하드코딩으로 재계산했다:

```gdscript
var scope_list: Array[int] = [ci]
var only_enhanced: bool = rank < 4
if rank >= 10:
    if ci > 0: scope_list.append(ci - 1)
    if ci + 1 < active.size(): scope_list.append(ci + 1)
```

결과: YAML target 문자열은 "선언용 문서"로만 기능했고, 설계자가 YAML에서 target을 다른 값(예: `all_military`)으로 바꿔도 코드는 계속 rank 기반 분기로 동일 scope를 생성. iteration 12에서 `apply_persistent` dead path를 제거하면서 "game_manager가 YAML을 직접 평가한다"로 주석을 붙였지만, **실제로는 rank만 평가하고 target string은 버리는 절반의 구현**이었다.

### Change (refactor — 외부 동작은 동일, 내부 drift 위험 제거)

1. **military_system.gd — public helper 2개 추가**
   - `resolve_command_revive(card) -> {target, hp_pct, limit}` — YAML base `revive` + `r_conditional.revive_scope_override`를 순서대로 스캔. rank_gte 조건 충족 시 override가 target을 덮어씀 (R10 > R4 > base).
   - `resolve_revive_scope(target_name, self_idx, board_size) -> {card_indices, only_enhanced}` — YAML target 문자열을 card index 리스트 + flag로 해석.
     - `self_enhanced` → [self], enhanced only
     - `self_all` → [self], all units
     - `self_and_adj_all` → [self ± 1 bounded], all units
     - Unknown → warning + self_enhanced fallback

2. **game_manager._materialize_army — 하드코딩 제거**
   - `mil_sys.resolve_command_revive` + `mil_sys.resolve_revive_scope` 호출로 교체.
   - rank 분기 로직 삭제. scope 결정은 전적으로 YAML target에 의존.

3. **test_military_system.gd — 10개 신규 테스트**
   - `resolve_command_revive`: rank 0/4/9/10 네 구간에서 올바른 target 반환 검증.
   - `resolve_revive_scope`: 3개 지원 target + 보드 좌/우/중간 경계 + unknown fallback 총 6개.

### Why refactor (not additive)

기존 하드코딩을 helper 호출로 대체하는 구조 변경. 다만:
- 외부 관찰 가능한 동작은 YAML의 현재 선언과 완전히 동일하도록 target 해석을 matching (self_enhanced ⟷ 기존 `rank < 4` 경로, self_all ⟷ 기존 `rank < 10` 경로, self_and_adj_all ⟷ 기존 `rank >= 10` 경로).
- 회귀 검증: 기존 `test_combat_revive_integration_smoke`와 rank별 revive HP 테스트 모두 통과.

P5 사다리 기준으로는 **1→2 단계 이동**: 이전에는 "rank 하드코딩을 YAML과 일치시키자"라는 규칙이 암묵적이었고 누수 (일치하지 않아도 코드는 돌아감). 이제는 YAML이 실제 제어 흐름에 직접 연결되어, 설계 문서와 런타임 동작의 drift 자체가 구조적으로 제거됨.

완전한 3단계(구조적 불가능)는 달성 못함 — 새 target 추가 시 `resolve_revive_scope`의 match에 케이스를 추가해야 하므로 YAML↔코드가 여전히 pair로 수정되어야 함. 이를 완전 제거하려면 target 해석 자체를 YAML로 끌어내는 DSL이 필요하지만 현재 단일 소비자(ml_command) 기준 ROI가 낮음 — 추후 다른 카드에 revive_scope가 도입되면 재검토.

### Validation

- `godot --headless ... -gdir=res://tests ... -gexit`:
  - Total 896 tests (이전 886 + 신규 10), 891 passing, 5 pre-existing failing (무관 — 유닛 카운트 stale 2건 + ATK buff 3건).
  - 10 신규 테스트 모두 통과.
- `python3 scripts/codegen_card_db.py --check` → clean (card_db.gd 재생성 불필요).
- 모든 지원 target (self_enhanced / self_all / self_and_adj_all)이 unit test로 커버됨.
- rank 경계 (0/4/9/10)가 test로 검증돼 YAML 스펙과 런타임 path의 일치를 계약으로 고정.

### 남은 위험

- 새 revive scope target이 YAML에 추가되면 `resolve_revive_scope`에 케이스 추가가 필요. 현재는 warning + fallback으로 완만히 실패하지만, 누락 시 기능이 조용히 돌아가지 않을 수 있음. CLAUDE.md의 "코드 ↔ 설계 문서 정합성" 항목이 이를 가드하지만 구조적 강제는 아님.
- `_rank(card)`가 `theme_state.rank`를 읽는데, 이 값이 어떻게 설정되는지는 별도 경로 (rank up 이벤트). 본 리팩터 범위 밖이지만, rank 설정이 잘못되면 여기서 잘못된 override를 선택하게 됨. 현행 경로는 rank-up 로직이 이미 검증됨.
