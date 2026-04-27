---
iteration: 21
date: "2026-04-26"
type: additive
verdict: adopted
files_changed:
  - data/cards/druid.yaml (생명의 맥동/오래된 근원/뿌리깊은 자 thresh, 태고의 분노 cap)
  - godot/core/data/card_db.gd (codegen)
  - godot/core/data/card_descs.gd (codegen)
  - godot/core/card_instance.gd (unique_*_mult 필드 + multiply_unique_stats + absorb_donor max + eff_*_for layer_unique)
  - godot/core/druid_system.gd (dr_world → multiply_unique_stats + unique_as_mult)
  - godot/scripts/game/game_manager.gd (effective AS = upgrade × unique × temp)
  - godot/sim/headless_runner.gd (effective AS 동일)
  - godot/tests/test_druid_system.gd (★3 cap 28 검증, world AS unique 검증)
  - godot/tests/test_merge_system.gd (unique mult max 5 신규 테스트)
  - godot/tests/test_game_economy.gd, test_game_manager_logic.gd (AS 계산)
  - docs/design/upgrade.md (★합성 도너 stat 흡수 정책 명시)
  - docs/design/cards-druid.md (소수정예 임계값 표 갱신)
refs:
  - "iter 20: merge absorption policy 통합 → 도너 유닛 3배 흡수가 드루이드 '소수 정예' 정체성 무력화 발견"
  - "user spec: 임계값을 합성 후 유닛에 맞춰 상향 (옵션 a 즉시 발동) + 세계수 [고유효과] max 합성"
---

## Iteration 21: 드루이드 임계값 + 세계수 [고유효과] 분리

### Problem

iter 20의 merge absorption policy 통합으로 도너 유닛이 모두 survivor에 합산(★1×3 → 6u, ★2×3 → 18u)되면서 발생한 두 가지 부작용:

1. **드루이드 "소수 정예" 임계값 무력화**:
   - 생명의 맥동 thresh 3/4/5: ★2 합성 직후 6u → ≤4 보너스 OFF
   - 오래된 근원 동일
   - 뿌리깊은 자 thresh 3 (전 ★ 동일): ★2부터 영구 OFF
   - 태고의 분노 cap 5/6/7: ★2 cap=6 → 9u 초과로 카드 효과 자체 OFF ([druid_system.gd:57](godot/core/druid_system.gd:57) `if get_total_units() > unit_cap: return`)

2. **세계수 mult 폭발 위험**:
   - dr_world의 multiply_stats가 매 RS 곱셈 누적 ([druid_system.gd:399](godot/core/druid_system.gd:399))
   - ★ 합성 시 도너 누적분이 모두 곱해짐 → 캐스케이드 ★3에서 mult ×100+ 가능
   - iter 20 정책(stack mult 곱셈 누적)으로는 폭발 막을 수 없음

### Approach

**Step 1 — 임계값 상향 (단순 수치 변경)**:

| 카드 | ★1 | ★2 | ★3 |
|------|----|----|----|
| 생명의 맥동 thresh | 3 → **2** | 4 → **6** | 5 → **18** |
| 오래된 근원 thresh | 3 → **2** | 4 → **6** | 5 → **18** |
| 뿌리깊은 자 thresh | 3 → **2** | 3 → **6** | 3 → **18** |
| 태고의 분노 cap | 5 → **3** | 6 → **9** | 7 → **27** |

★ 합성 후 정원과 정확 매치 (옵션 a). 합성 직후 즉시 보너스 발동, 라운드 손실 시에도 cap 내 유지.

태고의 분노 cap 27은 unit_cap 60의 절반에 가까워 정체성 약화 우려가 있으나 사용자 결정에 따라 단순 상향 채택. 추가 메카닉 변환(`min(units, cap)`으로 부분 적용)은 별도 backlog.

**Step 2 — 세계수 [고유효과] 분리 + max 합성**:

CardInstance에 unique mult layer 신규 도입:
- `stacks[].unique_atk_mult`, `unique_hp_mult` (기본 1.0)
- `unique_as_mult: float = 1.0` (카드 단위)
- `multiply_unique_stats(atk_pct, hp_pct)` 메서드
- `eff_atk_for/eff_hp_for`: layer_unique 곱셈 추가
  ```
  effective ATK = base × (1 + growth) × upgrade_mult × unique_mult × temp_mult
  ```
- `absorb_donor`: unique mult는 `maxf` 정책 (upgrade mult는 곱셈 그대로)

druid_system.gd dr_world: `multiply_stats` → `multiply_unique_stats`, `upgrade_as_mult` → `unique_as_mult`. AS 사용처 4곳 (headless_runner, game_manager, 2 tests)에 `* unique_as_mult` 추가.

다른 입력원(% 업그레이드, 보스 보상, 커맨더 RAIDER)은 여전히 `multiply_stats` → `upgrade_*_mult` 경로 사용 → 합성 시 곱셈 누적 보존.

### Verification

- TDD: Step 2 RED (5 신규 테스트 실패) → GREEN (1005/1005 통과)
- Step 1 회귀: dr_wrath ★3 cap 테스트 28기 검증으로 갱신 (cap 7 → 27)
- 전체 GUT: 1005/1005 통과 (cache 재빌드 후)

### Out-of-scope (잔여)

- DESIGN.md / docs/design 업데이트: 본 iteration에서 처리 (upgrade.md, cards-druid.md)
- 태고의 분노 메카닉 변환 (`min(units, cap)` 부분 적용) — 정체성 강화 옵션, 사용자 결정 후 별도 PR
- 세계수 [고유효과] 활용 신규 카드 — 동일 layer를 사용하는 다른 ★3 후보 카드들 검토 가능
