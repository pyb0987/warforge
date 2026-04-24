# Combat Side-Bias Fix — Handoff (D)

> 작성: 2026-04-23. 다른 세션이 이 문서만 읽고 이어갈 수 있는 self-contained handoff.
> 선행 맥락 없음 가정.

## 1. 문제

동일한 두 군대가 combat_engine에서 맞붙을 때 결과가 결정적으로 편향됨.

**관측** (side_bias_test.gd, swarm vs swarm, target_cp=36934):
- 원본 코드: team 1 (ally) 승률 **0/20 (0%)**, team 0 (enemy) 승률 **20/20 (100%)**
- 완전 결정적 편향 — stochastic 노이즈 아님

**영향**: 게임 내 player = team 1 = ally. 즉 **플레이어가 구조적으로 불리**. 같은 덱/같은 preset이 운이 아닌 side 배정으로 승패 결정.

파생 이슈: preset parity 진단 (preset_parity_runner.gd)의 대각선(self-play) 편차가 이 side bias에 오염됨. 같은 preset끼리인데도 50/50이 아닌 0-70% 분산.

## 2. 이미 완료된 수정 (commit 6e0bb04)

파일: `godot/combat/combat_engine.gd`.

### 2.1 Single-phase tick → 2-phase (Phase 1 = move, Phase 2 = attack)

**Before**:
```gdscript
for idx in _alive_list:
    _update_unit(idx)  # move + attack in one call
```

**After**:
```gdscript
for idx in _interleaved_order:
    _move_unit(idx)     # Phase 1: movement only
for idx in _interleaved_order:
    _attack_unit(idx)   # Phase 2: attack based on final positions
```

이유: 원본은 team 1 unit이 먼저 움직이고 바로 range check → 업데이트된 team 1 위치를 team 0 unit이 나중에 봐서 first-strike 획득.

### 2.2 Team-interleaved iteration order

`_alive_list`는 team 1 indices가 lower, team 0이 higher라 iteration 시 team 1 블록이 먼저. 
`_rebuild_interleaved_order()` 신설하여 `[t1[0], t0[0], t1[1], t0[1], ...]` 형태로 교대 배치.

**목적**: 같은 tick 내 first-strike tie-breaker가 unit마다 교대로 분산되어 block-wise bias 제거.

### 2.3 Phase 1 pos snapshot

Phase 1 iteration 중 earlier unit의 pos 쓰기가 later unit의 target distance 계산에 leak되는 문제.
`_pos_snapshot: PackedVector2Array` 신설하여 tick 시작 시 pos[] 복사. `_move_unit`에서 target 거리 계산 시 `_pos_snapshot[t]` 사용 (self pos는 현재 pos 그대로).

### 2.4 신규 진단 도구

- `godot/sim/preset_parity_runner.gd`: 4×4 preset 매트릭스 × N tier. `--runs`, `--cps`, `--mults`, `--seed` 인자.
- `godot/sim/side_bias_test.gd`: identical-army A/B swap 회귀 probe.

### 2.5 검증 결과

**swarm vs swarm (target_cp=36934)**:
- Before: 0/20 vs 20/20 (편차 100%)
- After: 5/20 vs 15/20 (편차 50%)

**Preset 대각선 (self-play, 같은 tier)**:
| Preset | Before | After | Ideal |
|--------|--------|-------|-------|
| swarm | 0% | 25% | 50% |
| heavy | 25% | 50% ✓ | 50% |
| sniper | 50% | 70% | 50% |
| balanced | 70% | 60% | 50% |

편차 합 95 → 55 (**42% 개선**). GUT 907/907 유지.

## 3. 남은 문제 (이 handoff 이후 작업 범위)

**Residual bias**: 
- swarm/heavy self-play는 좋아졌지만 sniper/balanced self-play는 team 1 쪽으로 약간 편향(60-70%).
- 완벽한 50/50이 아님 — 약 20-25% bias 잔존.

**근본 원인 가설**: Phase 2(attack) 내부 순서 의존성. Interleaved order에서도 같은 tick에 두 unit이 모두 attack 가능하면 **먼저 iterate된 쪽이 먼저 damage 적용** → target이 죽으면 counter attack 불가.

Interleaved는 block bias를 제거하지만, 각 pair 내의 "누가 먼저 iterate되나"는 여전히 lower-index 우선. Snapshot도 마찬가지로 iteration 순서 자체를 없애지 못함.

## 4. 다음 단계: 동시 damage 해결 (Simultaneous Damage Resolution)

### 4.1 목표
Phase 2에서 같은 tick의 모든 attack이 **동시에** damage 적용되도록 하여 iteration 순서 의존성 완전 제거.

### 4.2 설계

**Damage queue 도입**:
```gdscript
# 신규 멤버
var _damage_queue: Array = []  # [{"attacker": int, "defender": int, ...}]

# Phase 2 변경
for idx in _interleaved_order:
    _attack_unit_queue(idx)  # 계산만, damage 즉시 적용 안 함
for entry in _damage_queue:
    _resolve_queued_attack(entry)
_damage_queue.clear()
```

**`_attack_unit_queue`**: 현재 `_attack_unit`의 "in range + cooldown ready" 조건 확인만 하고 attack event를 queue에 넣음. cooldown 감소는 여기서 처리 (공격 시도한 모든 unit이 cooldown 소비).

**`_resolve_queued_attack`**: 실제 damage 적용 + mechanics. target이 이미 죽었어도 counter-attack은 허용 (시뮬 동시성).

### 4.3 복잡도 / 리스크

- **Mechanics 영향**: `mechanics_handler.resolve_attack`가 단순 damage 외에 crit, armor, armor_pierce, lifesteal, soul_steal, phase_shift, immortal_core, revive, splash, chain_explosion 등 처리. 모두 attacker/defender 쌍 기반. 대부분 순서 비의존적이라 queue에 그대로 넣고 나중에 처리해도 동일 결과. 
- **Splash / AOE**: splash target은 attack 시점의 alive 상태 기반. queue 처리 시점에 이미 죽은 unit이 splash 영향권에 있으면 skip되는데, 현재 코드도 그렇게 동작. 차이 없음.
- **죽은 target에 attack**: target died by earlier queued damage 후 later queue entry가 동일 target이면 — 현재 `resolve_attack`은 `alive[defender] == 0`이면 skip. 시뮬 semantics 변화: "동시에 때려서 둘 다 죽음" 허용하려면 pre-queue alive snapshot 사용. **설계 결정 필요**.

**권장 설계 결정**: 
- "pre-queue alive snapshot" 방식 채택. 즉 같은 tick에 A가 B를, B가 A를 동시에 죽이면 둘 다 사망 처리.
- 이는 RTS/AoS 전투 시뮬에서 흔한 관례 (StarCraft 2 combat 예).

### 4.4 구현 단계

1. `_damage_queue` 멤버 + `_attack_unit_queue` 도입
2. phase 2 iteration에서 queue만 생성, cooldown 소비는 즉시
3. queue 처리 루프: alive snapshot 기준으로 damage/mechanics 적용
4. `_do_attack` / `resolve_attack` 시그니처에 `alive_snapshot` 파라미터 추가 또는 내부에서 snapshot 참조
5. side_bias_test.gd 재실행 → ~10/20 vs ~10/20 (50/50) 기대
6. preset_parity_runner.gd 재실행 → 대각선 모두 45-55% 수렴 기대
7. GUT 전체 (907/907) 회귀 유지

### 4.5 검증 기준 (Sprint Contract)

```
Done when:
- side_bias_test.gd: abs(original - swapped) <= 2 (10% 이내 자연 노이즈만)
- preset_parity_runner.gd self-play (대각선): 각 preset 40-60% 범위
- GUT 전체 테스트 907+ 유지
- 기존 mechanics(armor, lifesteal, splash 등) 회귀 없음
- 전투 로그에 mechanics 중복 발동 없음 확인
```

Evaluator: Tier 2 (haiku sub-agent) + 체크리스트로 위 5개 항목 검증.

## 5. 위험 / 주의 사항

### 5.1 Combat replay 결정성

Damage queue 도입 시 처리 순서가 queue 적재 순서에 영향받을 수 있음. Replay 결정성 유지를 위해 queue는 interleaved order 그대로 유지, mechanics 호출 시점만 동시화.

### 5.2 기존 side_bias_test 와 preset_parity_runner 결과 비교

수정 전 이 handoff의 "검증 결과" 섹션 숫자(5/15, 대각선 25/50/70/60)를 benchmark로 사용.
수정 후 숫자가 50/50에 가까워지면 성공.

### 5.3 Combat 속도 영향

Phase 2에 queue 오버헤드. queue가 작으면 (<1000 entries/tick) 성능 영향 미미. 벤치마크로 confirm 필요.

### 5.4 기존 플레이테스트 / autoresearch baseline 영향

combat 결정성이 바뀌므로 기존 `sim/baseline.json`은 무효화될 가능성. autoresearch 실행 전 baseline 재생성 필수 (`feedback_autoresearch_perms.md` 참조).

## 6. 관련 파일

**이미 수정됨** (commit 6e0bb04):
- `godot/combat/combat_engine.gd`
- `godot/sim/preset_parity_runner.gd` (신규)
- `godot/sim/side_bias_test.gd` (신규)

**다음 세션에서 수정 예상**:
- `godot/combat/combat_engine.gd` — damage queue 로직
- `godot/combat/mechanics_handler.gd` — alive_snapshot 파라미터 추가 또는 참조 경로 조정

**보존 대상**:
- `godot/sim/side_bias_test.gd` — 회귀 probe로 계속 사용
- `godot/sim/preset_parity_runner.gd` — 회귀 probe + C (CP 공식) 작업에서도 사용 예정

## 7. 후속 작업 (이 handoff 밖)

- **C (CP formula 개선)**: off-diagonal 불균형 (swarm이 다른 preset 전부 이김)은 D로 해결 안 됨. CP 공식에 range/ms/count density 반영 필요. 별도 handoff 예정 (combat-cp-formula-handoff.md).
- **Evolution trace**: 본 D 작업 완료 시점에 `.claude/traces/evolution/NNN-combat-symmetry.md` 기록 권장.

## 8. Context rot 방지 / Handoff 팁

- 작업 시작 시 **먼저 `godot/sim/side_bias_test.gd` 현 상태 측정** (baseline).
- 다음 `godot/combat/combat_engine.gd:308-323` 의 phase 2 루프만 read — 전체 581줄 읽지 말 것.
- `mechanics_handler.resolve_attack` (line 103+, 70여 줄) 도 핵심만.
- 구현 중간에 side_bias_test 자주 돌려 regression early detection.
- 완료 시 commit + evolution trace 기록.
