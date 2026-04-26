---
iteration: 20
date: "2026-04-26"
type: additive
verdict: adopted
files_changed:
  - godot/core/card_instance.gd (absorb_donor + _absorb_theme_state + theme_state key 분류)
  - godot/core/game_state.gd (_try_merge_once → absorb_donor 호출 + activations_used = 0)
  - godot/tests/test_merge_system.gd (정책 RED→GREEN 19 신규 테스트)
  - CLAUDE.md (Build 섹션 cache rebuild 가이드)
  - .claude/traces/search-set.md (SS-008 등재)
  - .claude/traces/failures/010-stale-class-cache-cascade.md (신규 진단)
refs:
  - "user spec: 합산 (유닛/업그레이드/체인강화/나무/multiply_stats), max (tenure/rank/activations_used/threshold_fired), theme_state per-key 정책"
  - "design clarification: floor 표시 시점에만, multiply_stats 통합 곱셈 누적"
---

## Iteration 20: ★ 합성 도너 stat 흡수 정책 통합 + class_cache 가드

### Problem

기존 `_try_merge_once`는 도너 2장의 stat 중 **유닛 count + 업그레이드 어레이만 흡수**하고, 나머지(growth_*_pct, tag_growth_*, theme_state, stack mult, upgrade_def/range/ms, upgrade_as_mult, shield, tenure, rank 등)는 모두 폐기. 결과:
- 보스 보상으로 받은 multiply_stats 값이 합성 시 사라짐
- dr_world의 매 RS 누적된 stack mult 손실
- 군대 카드의 rank, 스팀펑크의 manufacture_counter 등 진행도 리셋
- 체인으로 누적된 growth_*_pct도 survivor 본인 것만 유지

설계 의도("도너 강화 보존")와 어긋나는 비대칭이 다수 존재.

### Approach

**Additive first**: 기존 try_merge 흐름 유지하되, 도너 흡수 로직을 `CardInstance.absorb_donor(donor)` 메서드로 캡슐화하고 그 안에 통합 정책 적용.

| 항목 | 정책 | 근거 |
|------|------|------|
| 유닛 (cap 60), 업그레이드 어레이 (5슬롯) | 합산 (truncate) | 기존 동작 유지 |
| `growth_atk/hp_pct`, `tag_growth_*` | 합산 | 체인강화 누적 보존 |
| theme_state 그룹A (trees/manufacture_counter/attack_stack_pct/range_bonus) | 합산 | 자원/카운터 누적 |
| `upgrade_def/range/move_speed`, `shield_hp_pct` | 합산 | 업그레이드 어레이와 정합 |
| stack `upgrade_atk_mult/hp_mult`, `upgrade_as_mult` | 곱셈 누적 | dr_world/보스/커맨더/% 업그레이드 통합 (분리 필드 over-engineering 회피) |
| `tenure`, theme_state `rank`, `unit_cap_bonus`, `upgrade_slot_bonus` | max | 진행 단계/등급 보너스는 최강 도너 기준 |
| `is_omni_theme`, theme_state 그룹B (`pending_epic_upgrade`, `high_rank_applied`) | OR | 1회 플래그 |
| `activations_used` | 0 리셋 | 합성 직후 같은 라운드 내 추가 발동 허용 (플레이어 이득) |
| `threshold_fired` | false 리셋 | evolve_star가 처리 (★ 진화로 재발동 자연스러움) |
| theme_state 그룹C/D (라운드 한정/전투 한정) | survivor 유지 | 매 라운드/BS에서 재계산 |

**Floor 정책**: stack mult의 0.01 floor는 UI/desc 표시 시점에만 적용. 내부는 full precision 유지 → detach_upgrade 역계산(가역) 보존.

### Verification

- TDD: RED (17 신규 테스트 실패) → GREEN (1000/1000 통과)
- 회귀: 전체 GUT 1000/1000 (cache 재빌드 후)
- search-set: SS-002, SS-006 verify 통과 유지

### Cache cascade discovery (out-of-scope but adopted)

Verification 중 stale class_cache 이슈 발견. commit `8532451` (Phase 3b-2b)에서 도입된 `class_name NeutralSystem`이 fresh worktree에서 등록 누락되어 chain_engine.gd 컴파일 실패 → 카스케이드 149개 false-positive 실패. 작업자 cache warm 환경에서는 통과로 보였음. 본 iteration에서:
- traces/failures/010-stale-class-cache-cascade.md 진단 작성
- search-set SS-008 등재 (verify: cache rebuild 후 GUT 통과 확인)
- CLAUDE.md Build 섹션에 cache rebuild 가이드 명시

### Floor 작업 폐기 (post-implementation 검증)

stack mult의 0.01 floor는 처음 "UI/desc 시점에만 적용" 안으로 결정됐으나, post-impl 검토 결과 **현재 UI 어디에서도 부동소수점 mult를 직접 표시하지 않음** ([card_visual.gd:107](godot/scripts/build/card_visual.gd:107) 모두 `%.0f` 정수, [card_tooltip.gd:122](godot/scripts/ui/card_tooltip.gd:122) `growth_*_pct`는 `%.0f%%` 정수 %, [card_desc_gen.py:355-378](scripts/card_desc_gen.py:355) `desc_multiply_stats`는 YAML 설계 파라미터만 표시). 세계수도 누적 mult 결과를 UI에 노출하지 않으므로 floor 작업 자체 불필요. 본 iteration에서 폐기.

### Out-of-scope (향후) — iter 21에서 처리됨

- ~~드루이드 `low_unit thresh` / `unit_cap` 충돌 카드 재설계~~ → traces/evolution/021
- ~~DESIGN.md / docs/design/upgrade.md ★합성 섹션 동기화~~ → iter 21에서 함께 처리
