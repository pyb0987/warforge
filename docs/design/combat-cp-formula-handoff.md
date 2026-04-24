# CP Formula Rebalance — Handoff (C)

> 작성: 2026-04-23. 다른 세션이 이 문서만 읽고 이어갈 수 있는 self-contained handoff.
> 선행 맥락 없음 가정.
>
> **독립 작업**: 이 작업은 combat-symmetry-handoff.md(D)와 직교. D는 side bias 수정,
> C는 preset 간 실제 전투력 편차 수정. 한쪽만 해도 다른 쪽 진행 가능.

## 1. 문제

**관측**: 같은 `target_cp`로 생성된 군대끼리 맞붙으면 preset 간 결과 편차가 극단적.

`godot/sim/preset_parity_runner.gd` (20 runs × 4×4 preset pair, target_cp=36934):

| A \ B | swarm | heavy | sniper | balanced |
|-------|-------|-------|--------|----------|
| swarm | (self) | **100%** | **100%** | **100%** |
| heavy | 0% | (self) | 0% | 0% |
| sniper | 0% | 100% | (self) | 100% |
| balanced | 0% | 100% | 0% | (self) |

**엄격한 계층**: `swarm > sniper > balanced > heavy`. 세 target_cp tier (R5/R10/R15 대응) 모두 동일 패턴.

**CP 공식 실패 증명**: 같은 target_cp에서 100% / 0% 양극 발생. CP 수치가 실제 전투력을 반영하지 못함.

## 2. 왜 CP가 잘못되었나

현재 CP 공식 (`godot/sim/preset_generator.gd::derive_comp`):
```
cp_per_unit = (atk / as) × hp × stat_mult²
total_cp_of_army = sum(cp_per_unit × count)
```

이 공식이 무시하는 요인:

**① Range (사거리)**
- sniper range 6, swarm/heavy/melee range 0
- 근접 유닛은 붙어야 때릴 수 있고, sniper는 kiting 가능
- CP는 근접/원거리 동일하게 취급

**② Move speed**
- swarm ms=3, melee ms=2, heavy ms=1, sniper ms=1
- 느린 heavy는 빠른 ranged에게 못 붙음 (0% WR)
- CP는 이동 무시

**③ Unit count density**
- Swarm 다수 vs Heavy 소수 — 같은 CP일 때 swarm은 유닛 수 훨씬 많음
- 다수 유닛이 개별 heavy 유닛을 n:1 집중 공격 → heavy HP 이점 무효화
- CP는 "숫자의 밀도 효과" 반영 없음

**④ Formation / spatial bottleneck**
- 느린 heavy는 뒤처짐, 앞줄만 싸우고 나머지 무력화
- 빠른 swarm은 전면 접촉
- CP는 공간적 참여도 무시

## 3. 목표

CP 공식을 보완하여 **같은 target_cp에서 preset 간 WR 편차 축소**.

**구체 목표 (Sprint Contract)**:
- 4×4 preset 매트릭스 off-diagonal 셀 모두 **30-70%** 범위 (현재 0%/100% 극단 소멸)
- 대각선(self-play)은 C 작업 범위 밖 — D handoff에서 별도 해결
- 완벽한 50/50은 요구 안 함 (preset 정체성 유지) — **극단값만 제거**

## 4. 설계 옵션

세 가지 접근. 상/중/하 난이도.

### Option 4-A: Per-preset CP multiplier (저난이도, 응급)

`target_cp`를 preset 별로 scaling. 현재 parity 데이터에서 경험적으로 도출.
```python
PRESET_CP_MULTIPLIER = {
    "swarm": 0.5,     # 너무 강함 → CP 절반만 써서 유닛 수 축소
    "heavy": 2.0,     # 너무 약함 → CP 두 배로 써서 유닛 수 증가
    "sniper": 0.8,
    "balanced": 1.0,
}
```

`derive_comp(preset, target_cp, ...)` 첫 줄에 `target_cp *= PRESET_CP_MULTIPLIER[preset]` 추가.

**장점**: 즉각적. 직접 조정 가능.  
**단점**: 수치 요정 (magic numbers). 유닛 구성이나 스탯 변경 시마다 재튜닝. "CP가 전투력"이라는 단일 진실 해침.

### Option 4-B: CP 공식에 요인 추가 (중난이도, 권장)

per-unit CP에 range/ms bonus, army 전체에 density bonus 추가.

```python
def cp_unit(stats, stat_mult):
    atk = stats["atk"]
    hp = stats["hp"]
    as_ = max(stats["as"], 0.01)
    range_v = stats.get("range", 0)
    ms = stats.get("ms", 2)

    base = (atk / as_) * hp * (stat_mult ** 2)
    range_bonus = 1.0 + range_v / K_RANGE     # K_RANGE ~ 20, range 6 → 1.3x
    ms_factor = sqrt(ms / MS_REF)              # MS_REF=2, ms 3 → 1.22x, ms 1 → 0.71x
    return base * range_bonus * ms_factor

def cp_army_total(counts_per_type, stats_map, stat_mult):
    base_sum = sum(
        counts_per_type[t] * cp_unit(stats_map[t], stat_mult)
        for t in counts_per_type
    )
    N = sum(counts_per_type.values())
    density_bonus = 1.0 + log(max(N / N_REF, 1.0)) * K_DENSITY  # N_REF=20, K_DENSITY~0.15
    return base_sum * density_bonus
```

PresetGen.derive_comp의 로직도 뒤집어서 `target_cp`가 주어지면 이 확장 공식으로 역산.

**장점**: 구조적. 새 유닛 추가해도 공식이 자연스럽게 scaling. 의미 기반.  
**단점**: 상수 4개 (K_RANGE, MS_REF, N_REF, K_DENSITY) 튜닝 필요. calibration loop.

### Option 4-C: Simulation-based effective CP (고난이도)

Preset 별로 실제 전투 시뮬 돌려 "effective CP" 산정.
- Baseline preset (e.g. balanced)을 기준으로, 다른 preset을 같은 WR 내는 CP로 scale.
- Parity test가 곧 calibration 루프.

**장점**: 이론적으로 완벽. 공식의 편향 0.  
**단점**: 구현 복잡. 매 genome mutation마다 돌려야 하면 비용 큼. calibrate_target_cp와 비슷한 loop 필요.

### 권장: **4-B (CP 공식에 요인 추가)**

- 응급(4-A)보다 구조적. 설계 철학 유지.
- 4-C의 비용 없이 4-A의 즉시성 제공.
- 상수 4개만 찾으면 됨 — parity 매트릭스를 feedback loop으로 사용하면 2-3 iteration에 수렴 기대.

## 5. 구현 단계 (4-B 기준)

### Step 1: 현재 baseline 측정
```bash
godot --headless --path godot/ --script res://sim/preset_parity_runner.gd -- \
  --runs=20 --cps=7262,36934,126577 --mults=1.5,3.5,6.0 --seed=42 > /tmp/parity_before.json
```
참고: 현재 수치 (commit 6e0bb04 이후):
- swarm vs heavy: 100%, heavy vs swarm: 0%
- balanced vs sniper: 0%, sniper vs balanced: 100%
- 기타 동일 패턴.

### Step 2: 공식 수정 (python + godot 쌍대 업데이트)

**`scripts/preset_generator.py`** (python — single source of truth):
- `cp_unit(stats, stat_mult)` 헬퍼 추가
- `derive_comp(...)` 내부 `avg_cp_per_unit` 계산을 `cp_unit` 기반으로 전환
- `cp_army_total` 로 density bonus 포함

**`godot/sim/preset_generator.gd`** (godot 미러):
- 동일 로직 GDScript로 재작성. python 문서 주석 상단에 "mirror of scripts/preset_generator.py — keep in sync" 유지.

**초기 상수 값 (감 기반 출발점, 이후 튜닝)**:
```
K_RANGE = 20.0      # range 6 → 1.3x bonus
MS_REF = 2.0        # 기준 (melee)
N_REF = 20.0        # 기준 army size
K_DENSITY = 0.15    # N=100 → 1.24x, N=200 → 1.34x
```

### Step 3: 측정 + 튜닝 iteration

```bash
# 파라미터 수정 후
godot --headless --path godot/ --script res://sim/preset_parity_runner.gd -- \
  --runs=20 --cps=7262,36934,126577 --mults=1.5,3.5,6.0 --seed=42 > /tmp/parity_iter_N.json
```

각 iteration에서 관찰:
- swarm이 여전히 100% 이김 → `K_DENSITY` 감소 (density bonus 줄여서 swarm 유닛 수 추가 감축)
- heavy가 여전히 0% → `MS_REF` 값 조정하여 heavy CP bonus 늘림 (느린 heavy 지금은 penalty 받음 — penalty 축소)
- sniper 과강 → `K_RANGE` 감소

**수렴 기준**: off-diagonal 모든 셀이 30-70% 범위 이내.

예상 iteration 수: 3-5회 (각 iter ≈ 5분).

### Step 4: Calibration / baseline 재생성

CP 공식 바뀌면 기존 target_cp 값이 다른 의미를 가짐. 따라서:
- `calibrate_target_cp.py` 재실행 → target_cp_per_round 재산정
- `godot/sim/best_genome.json` 갱신 (권한: chmod +w 필요, CLAUDE.md `feedback_autoresearch_perms.md` 참조)
- `godot/sim/baseline.json` 재생성 (batch_runner 1회 실행)

### Step 5: GUT 회귀

```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```
907+ 테스트 통과 확인.

특히 `test_preset_generator.gd` (있다면) 의 수치 기대값 업데이트.

### Step 6: 플레이테스트 / autoresearch 영향 확인

CP 공식 변경은 전체 게임 밸런스에 ripple. 최소:
- 1회 수동 플레이테스트 → 각 라운드 느낌 확인
- autoresearch 10-20 iter 돌려서 economy 축 수렴 확인

## 6. 검증 기준 (Sprint Contract)

```
Done when:
- preset_parity_runner.gd 4×4 off-diagonal: 모든 셀 30-70%
  (세 target_cp tier 모두에서)
- GUT 전체 907+ 테스트 통과
- test_preset_generator.gd (있다면) 새 공식 기준 갱신
- godot/sim/preset_generator.gd ↔ scripts/preset_generator.py 동기화 확인
  ("mirror" 주석 + 동일 동작 검증 스크립트)
- baseline.json 재생성 (신 공식 기준)

Evaluator: Tier 2 (haiku) + 체크리스트:
- off-diagonal 매트릭스 30-70% 확인
- python/godot mirror 동일 동작 확인 (sample input 1개로)
- GUT 회귀 pass
- baseline 재생성 유무 확인
```

## 7. 리스크 / 주의사항

### 7.1 D(side bias)와 교란

C 작업은 preset 간 편차를 측정. 그런데 side bias가 있으면 off-diagonal 측정에 side 효과가 섞임. D가 완전히 해결 안 됐을 경우:
- parity 매트릭스의 `A vs B` 와 `B vs A` 가 대칭 아닐 수 있음 (side bias 때문)
- 해결책: 각 pair를 양방향 측정하고 평균. preset_parity_runner.gd에 `--symmetric` 옵션 추가 검토.

현재 D 수정 이후 side bias는 ~25% 잔존. off-diagonal 편차(0-100%)에 비하면 무시 가능한 수준이므로 **C 작업은 D 완료 대기 안 해도 진행 가능**.

### 7.2 자의적 상수 vs SSOT

K_RANGE, K_DENSITY 등은 "디자이너 튜닝" 영역. `genome_bounds.json`에 넣을지 constants에 넣을지 결정 필요.
- 추천: `scripts/preset_generator.py` 상단 상수. autoresearch 탐색 대상 아님 (설계 기반 튜닝).

### 7.3 Mirror drift

python/godot 두 구현 유지. 이미 `scripts/preset_generator.py` 주석 "Mirrors godot/sim/preset_generator.gd — keep in sync" 존재. 수정 시 양쪽 함께.

**장기적**: 한 쪽을 SSOT로 두고 codegen 도입 고려 (CLAUDE.md P5 사다리 3단계). 하지만 이는 C 작업 범위 밖.

### 7.4 Stat_mult² 상호작용

현재 공식의 `stat_mult²`는 stat (atk, hp) 둘 다 × stat_mult 되므로 CP = ... × stat_mult². 새 공식에서도 유지. range/ms/density 항은 stat_mult에 독립 (scaling 불변).

### 7.5 Preset 의도 변화 방지

CP 공식 수정의 목표는 **같은 target_cp → 비슷한 전투력**이지 **preset 간 성격 획일화** 아님.
- swarm은 여전히 유닛 많고 개별 약함
- heavy는 여전히 소수 탱크
- sniper는 여전히 원거리 우위
- 각 preset의 **정체성(identity)은 유지**, 단지 total 전투력만 같게.

구현 시 `PRESET_RECIPES`(role weights)는 건드리지 않음. 오직 CP 공식만 수정.

## 8. 관련 파일

**수정 대상**:
- `scripts/preset_generator.py` — CP 공식 중심
- `godot/sim/preset_generator.gd` — mirror
- `godot/sim/calibrate_target_cp.py` — Step 4 재실행
- `godot/sim/best_genome.json` — calibration 결과 반영 (chmod +w 필요)
- `godot/sim/baseline.json` — 재생성

**보존 / 사용**:
- `godot/sim/preset_parity_runner.gd` — feedback loop 진단
- `godot/sim/target_wr_curve.json` — 상위 설계 (변경 없음)

**참고 / 읽기 전용**:
- `godot/core/data/enemy_db.gd` — preset → units 매핑
- `godot/combat/combat_engine.gd` — 전투 시뮬 (C 작업에서 수정 없음)

## 9. 후속 작업 (이 handoff 밖)

- **D (combat symmetry)**: 독립 작업. `docs/design/combat-symmetry-handoff.md` 참조. 완전 50/50 self-play 위해 simultaneous damage resolution 필요.
- **Evolution trace**: 완료 시 `.claude/traces/evolution/NNN-cp-formula-rebalance.md` 기록.
- **Genome_bounds 자동탐색**: 현재 설계는 K_* 상수를 하드코딩. 장기적으로 `K_DENSITY` 같은 값을 autoresearch로 튜닝 가능성 검토 (단, 탐색 공간 폭발 주의).

## 10. Context rot 방지 / Handoff 팁

- 작업 시작: `preset_parity_runner.gd`로 먼저 현 baseline 측정 (before/after 비교용).
- `scripts/preset_generator.py`는 python 한 파일만 먼저 수정 → 동작 확인 → godot mirror 업데이트.
- `godot/sim/preset_generator.gd:derive_comp`와 python 버전 side-by-side read 추천.
- 각 iteration 후 매트릭스 결과 요약 저장: `/tmp/parity_iter_N_summary.txt` (off-diagonal min/max/avg).
- 수렴 판정은 수치뿐 아니라 **직관 점검** — "heavy가 여전히 0%면 ms factor 문제 등".
- 완료 시: commit + evolution trace + (선택) memory 업데이트 (`feedback_cp_formula_design.md`).
