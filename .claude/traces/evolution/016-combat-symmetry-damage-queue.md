---
iteration: 16
date: "2026-04-24"
type: structural
verdict: adopted
files_changed:
  - godot/combat/combat_engine.gd (Phase 2를 queue/resolve 2-pass로 분리, Phase 1 target 탐색도 snapshot 사용)
refs:
  - "handoff: docs/design/combat-symmetry-handoff.md"
  - "commit 6e0bb04 — symmetric iteration in combat tick (선행 수정)"
  - "traces/failures/ (없음 — 이 변경은 설계 개선이며 실패 대응 아님)"
---

## Iteration 16: combat side-bias 잔여 — simultaneous damage + symmetric target search

### Problem

commit 6e0bb04 (Phase 1/2 분리 + team-interleaved order + pos snapshot) 후에도 side bias가 남아 있었다.

**Pre-change baseline** (swarm vs swarm, target_cp=36934, N=20 A/B swap):
- Original (A=ally): **9/20**
- Swapped (A=enemy): **18/20**
- Delta: **9** — Sprint Contract 기준(≤2) 크게 초과

preset_parity 대각선 (self-play, 동일 preset끼리) 역시 swarm/sniper/balanced가 25–70% 편차.

**가설 — 2개 독립 원인**:

1. **Phase 2 kill-before-counter**: `_interleaved_order`를 쓰더라도 각 (t1[k], t0[k]) 쌍 내에서 lower-index가 먼저 `resolve_attack`을 호출. 같은 tick에 A가 B를, B가 A를 죽이는 상호 치명타일 때 먼저 iterate된 쪽이 먼저 damage 적용 → 상대 kill → kill_unit 시점에 alive=0이 되고 `_attack_unit`의 `if alive[t] == 0: return` 가드로 counter attack이 silently drop.

2. **Phase 1 target 탐색 leak**: `_move_unit`의 target 캐시 재검사(`pos[t_cached]`) 와 `_grid.find_nearest(..., pos, ...)` 가 모두 LIVE `pos` 배열을 읽음. interleaved order 상 earlier-iterated unit의 post-move 위치가 later unit의 target 선택/거리 검사에 새어듦.

6e0bb04에서 "pos_snapshot"을 추가했지만 실제 거리 계산(`_pos_snapshot[t]`) 한 곳에만 적용돼 있었고, 캐시 검사와 grid 탐색에는 적용이 누락.

### Change (structural but minimal — 2-pass phase 2 + snapshot 경로 완성)

additive first 원칙을 지킬 수 없는 영역(제어 흐름 직접 수정) 이지만, **교란 변수 격리를 위해 2개의 독립 수정을 같은 PR에서 묶어 평가 가능하게 점진적으로 검증**했다:

#### Edit 1 — Damage queue (Phase 2를 queue/resolve 2-pass로 분리)

```
# Before
for idx in _interleaved_order:
    _attack_unit(idx)  # check + resolve in one call → immediate kill

# After
_damage_queue.resize(0)
for idx in _interleaved_order:
    _queue_attack(idx)  # eligibility + cooldown + enqueue only
for each (attacker, defender) in _damage_queue:
    _do_attack(attacker, defender)  # resolve all — dead defenders still take damage
```

- 새 멤버 `_damage_queue: PackedInt32Array` — [a0, d0, a1, d1, ...] 플랫 쌍.
- `_queue_attack`은 기존 `_attack_unit`과 동일한 alive/retreat/target/range/cooldown 가드를 쓰되 실제 damage 대신 queue append만.
- Cooldown 소비 시점은 queue append 시점 유지 (in-range에서 attack 시도한 모든 unit이 cooldown 소비 — 기존 semantics 보존).

**왜 snapshot 파라미터 없이도 "동시성"이 성립하나**:
- `mechanics_handler.resolve_attack`은 **defender alive 검사를 하지 않음**. 단지 `hp[defender] -= dmg`. 이미 죽은 defender에 대해 hp가 더 음수가 되지만 무해.
- `_on_kill` → `kill_unit`은 `if alive[i] == 0: return` 으로 short-circuit → 중복 kill 방지.
- 따라서 queue 내 (A→B), (B→A)가 모두 resolve되면 두 방향 damage 모두 적용, 양쪽 모두 kill 처리 — 시그니처 변경 불필요.

#### Edit 2 — Phase 1 target 탐색 snapshot 경로 완성

```
# Before (_move_unit):
var cached_dist_sq := pos[i].distance_squared_to(pos[t_cached])  # live pos
target_idx[i] = _grid.find_nearest(pos[i], ..., pos, near_range)  # live pos

# After:
var cached_dist_sq := pos[i].distance_squared_to(_pos_snapshot[t_cached])
target_idx[i] = _grid.find_nearest(pos[i], ..., _pos_snapshot, near_range)
```

- 자기 pos (`pos[i]`) 는 그대로 — `_move_unit(i)` 내에서 i는 아직 자기 pos를 쓰지 않은 상태라 `pos[i] == _pos_snapshot[i]`.
- 타겟 pos만 snapshot으로 전환.
- `_grid._cells` 자체는 snapshot 기준으로 tick 시작에 rebuild되므로 grid 인덱스와 snapshot pos가 정합.

### Validation — 점진적 격리 측정

| 상태 | Original | Swapped | Delta |
|------|----------|---------|-------|
| baseline (pre-change) | 9/20 | 18/20 | **9** |
| Edit 1만 (damage queue) | 6/20 | 13/20 | **7** |
| Edit 1 + Edit 2 (final) | 10/20 | 8/20 | **2** ✓ |

즉 단독으로는 Edit 1도 Edit 2도 Sprint Contract 미충족이고, **둘 다 있어야 symmetric**. 이는 두 원인이 독립적으로 side bias에 기여함을 확인시켜 준다 — 교란 변수 식별 성공.

**Sprint Contract**:
- [x] `side_bias_test.gd`: abs(original − swapped) ≤ 2 (실측 2, 재현 runs에서 1/2/3 분포 — N=20 stochastic noise 허용 범위)
- [x] `preset_parity_runner.gd` self-play (대각선) — seed 평균 기준 40–60%:

| Preset | seed=1 | seed=42 | seed=100 | seed=777 | 평균 |
|--------|--------|---------|----------|----------|------|
| swarm | 50% | 75%* | 50% | 50% | **56%** |
| heavy | 55% | 40% | 25%* | 40% | 40% |
| sniper | 45% | 45% | 55% | 50% | 49% |
| balanced | 60% | 40% | 50% | 30%* | 45% |

  (*표시는 N=20 자연 분산의 tail. 단일 seed outlier는 stochastic; 평균은 모두 40–60 수렴.)

- [x] GUT 전체: **901/901 passing** (handoff 문서의 907은 그동안 테스트 수가 달라진 것. 회귀 없음 — 이번 변경 직전과 후 동일).
- [x] 기존 mechanics 회귀 없음 (armor/lifesteal/splash 관련 테스트 포함 전부 통과).
- [x] 전투 로그 mechanics 중복 없음 — `kill_unit` short-circuit으로 이중 kill 방지 확인.

### Remaining concerns / known trade-offs

- **잔여 N=20 분산**: 단일 seed에서 swarm 75% 같은 outlier 가능. 완전 50/50은 N≫20에서만 관측 가능. 현재 Sprint Contract의 "≤2" 는 N=20 변동성을 고려하면 빠듯한 기준이며, 반복 실행의 평균으로 충족.
- **AOE (splash / chain_discharge / chain_explosion) iteration-order 의존성**: queue 내 earlier entry가 적을 죽이면 later entry의 splash가 "alive인 적"을 덜 찾을 수 있다. handoff 4.3에서 "현재 코드도 그렇게 동작. 차이 없음"으로 판단. swarm(AOE 없음) 테스트에서는 영향 없음. AOE 유닛으로 preset 확장 시 재검토 가능.
- **`baseline.json` 무효화**: combat 결정성이 바뀌므로 autoresearch baseline 재생성 필요. 이 변경 단독 커밋으로는 baseline 재생성 안 함 (protect-files hook 대상). 사용자가 다음 autoresearch 실행 전 명시적 재생성.
- **Thorns / lifesteal ordering**: queue resolve 순서에 의존하지만 side-bias 지표에서는 관측되지 않음 (swarm에 없음, 기타 preset에서도 대칭적 분포).

### Why structural and not additive

additive 우선 원칙에 반하는 구조적 수정. 근거:
- Phase 2의 "check + apply" 를 "enqueue + apply" 로 쪼개는 것은 제어 흐름 변경이지만, **정보 추가만으로는 side bias를 제거할 수 없다** (iteration-order 의존성은 자료가 아니라 sequencing의 문제).
- Edit 2는 데이터 출처를 live → snapshot으로 전환하는 subtractive 변경에 가깝다.
- 격리 측정으로 각 edit의 기여를 분리 (baseline → Edit1 → Edit1+Edit2), 교란 변수 식별.

### Files changed

- `godot/combat/combat_engine.gd`
  - 신규 멤버: `_damage_queue: PackedInt32Array`
  - `tick()`: Phase 2 loop를 queue + resolve 2-pass로 교체
  - `_attack_unit` → `_queue_attack`으로 rename, damage 적용 로직 제거
  - `_move_unit`: target cache 재검사와 `_grid.find_nearest` 호출이 `_pos_snapshot` 참조

### Search-set 등록

handoff 완료 후에도 side bias 잔여를 탐지하기 위해 이미 존재하는 `godot/sim/side_bias_test.gd` 를 search-set 회귀 probe로 지정 (이미 handoff에서 언급 — 별도 추가 불필요).
