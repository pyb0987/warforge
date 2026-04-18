# Autoresearch Program — Warforge Balance Optimization

## 연구 목표

### 1차 목표: 전략 다양성 + 테마 균형 + 카드 커버리지

| 목표 | 측정 | 수용 기준 |
|------|------|-----------|
| 전략 다양성 | 7 AI 전략의 클리어율 분포 | 모든 전략 클리어율 σ < 0.10 |
| 테마 균형 | 4 테마 focused 전략 간 클리어율 | 테마 간 클리어율 최고/최저 비율 < 3.0 |
| 카드 사용성 | 54장 카드 중 유의미 사용률 | 전 테마에서 카드 사용률 10%+ 달성 비율 > 70% |

### 2차 목표: 감정 아크 보존

기획서의 감정 곡선을 유지하면서 위 목표를 달성해야 한다:
- R1-R3: 플레이어 우세 (승률 80%+)
- R4-R7: 균형 (승률 40-70%)
- R8-R12: 플레이어 열세, ★2+업그레이드 필요 (승률 30-60%)
- R13-R15: 완성 빌드로 빡빡하게 돌파 (승률 20-50%)

### weighted_score 목표

현재 베이스라인: 0.4560 (2026-04-18 v3 재촬영, evaluator WIN_RATE_SIGMA 0.05→0.25 교정 후 — failures/002 2회 재발 흡수. win_rate_band 가우시안이 관측 WR span을 커버하도록 σ 확대).
목표: 0.65+.
ADOPT 기준: 이전 best 대비 weighted_score가 상승하면 ADOPT.
게임 클리어율 목표: 5-10% (15R 생존).

**현 전략 목록** (`ai_agent.gd:STRATEGY_NAMES`):
`soft_steampunk`, `soft_druid`, `soft_predator`, `soft_military`, `adaptive`, `economy`, `aggressive`.
구 네이밍(`*_focused`, `hybrid`)은 2026-04 전환으로 폐기됨.

**현 스냅샷 주요 이슈** (baseline.json v2, 2026-04-18):
- mean WR 75% (목표 5-10% 대폭 초과 — v3 evaluator에서 win_rate_band gradient 복원으로 이제 탐색 신호 있음)
- card_coverage 28.1% (목표 70%+ 미달, bench_space 수정으로 15→28% 개선)
- win_rate_band = 0 (라운드별 감정 곡선 붕괴)
- emotional_arc 0.326 (WR 상향으로 0.389 → 0.326 악화)
- 전략 σ 0.139 (목표 < 0.10 미달, max/min ratio 1.9)

> **탐색 이력 / AI 변경 이력 / Phase별 default_genome 스냅샷은 `rejection_history.md`로 분리됨** (이 파일은 Tier 0 immutable로 보호되므로 agent가 직접 갱신할 수 없음).

---

## Genome 변수 정의 + 허용 범위

### 1. 적 CP 곡선 (15값)

라운드별 적 CP 스케일 팩터. EnemyDB의 기본 공식에 곱해지는 계수.

```
기본값: [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.2, 4.5]
허용 범위: 각 값 [0.5, 50.0] (2026-04-18 확대 — SC tavern-style 복리 성장 레퍼런스. v2 iter2에서 8.0 상한 포화로 plateau 발생 관측)
```

**불변 제약**:
- 단조증가: cp_curve[i] <= cp_curve[i+1] (난이도는 항상 증가)
- 보스 라운드(R4, R8, R12, R15) 값은 직전 라운드보다 최소 1.1배

### 2. 경제 파라미터

#### 2a. 기본 수입 (15값)
```
기본값: [5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7]
허용 범위: 각 값 [3, 10] (정수)
```
**불변 제약**: 단조증가 (base_income[i] <= base_income[i+1])

#### 2b. 리롤 비용
```
기본값: 1
허용 범위: [1, 3] (정수)
```

#### 2c. 이자
```
interest_per_5g: 기본 1, 범위 [0, 2] (정수)
max_interest: 기본 2, 범위 [1, 4] (정수)
```
**불변 제약**: max_interest >= interest_per_5g

#### 2d. 테라진 수입
```
terazin_win: 기본 2, 범위 [1, 4] (정수)
terazin_lose: 기본 1, 범위 [0, 3] (정수)
```
**불변 제약**: terazin_win > terazin_lose (승리가 항상 이득)

#### 2e. 레벨업 비용 (5값)
```
기본값: {2: 5, 3: 7, 4: 8, 5: 11, 6: 13}
허용 범위: 각 값 [2, 20] (정수)
```
**불변 제약**: 단조증가 (cost[lv] < cost[lv+1])

### 3. 상점 티어 확률 (6레벨 × 5티어 = 30값)

각 레벨에서 T1~T5 카드의 출현 확률(%).

```
기본값:
  Lv1: [100, 0, 0, 0, 0]
  Lv2: [70, 28, 2, 0, 0]
  Lv3: [35, 45, 18, 2, 0]
  Lv4: [10, 25, 42, 20, 3]
  Lv5: [0, 10, 25, 45, 20]
  Lv6: [0, 0, 10, 40, 50]

허용 범위: 각 값 [0, 100] (정수)
```

**불변 제약**:
- 각 레벨의 5값 합 = 100
- Lv1은 T1=100% 고정 (R1은 학습 구간)
- 레벨이 높을수록 고티어 비중 증가: 각 레벨의 가중평균 티어 단조증가
  - weighted_tier(lv) = sum(Ti * weight_i) / 100, weighted_tier(lv) <= weighted_tier(lv+1)

### 4. 적 유닛 구성 (4프리셋 × 계수)

적 프리셋별 유닛 수 공식: `n = base + round * per_r`

```
기본값:
  swarm:    {swarm_base: 8, swarm_per_r: 2.5, ranged_base: 2, ranged_per_r: 0.5}
  heavy:    {heavy_base: 3, heavy_per_r: 0.8, melee_base: 4, melee_per_r: 1.0, ranged_base: 2, ranged_per_r: 0.5}
  sniper:   {sniper_base: 3, sniper_per_r: 0.6, melee_base: 5, melee_per_r: 1.2}
  balanced: {melee_base: 4, melee_per_r: 1.0, ranged_base: 3, ranged_per_r: 0.7, swarm_base: 3, swarm_per_r: 0.5}

허용 범위:
  base: [1, 15] (정수)
  per_r: [0.1, 5.0] (float, step 0.1)
```

**불변 제약**:
- 모든 프리셋에서 R1 총 유닛 수 >= 5 (최소 교전)
- R15 총 유닛 수 <= 80 (시뮬 성능)

### 5. 적 기본 스탯 (5타입 × 3스탯 = 15값)

유닛 타입별 ATK/HP/AS 기본값. CP 곡선이 전체 스케일을 조절하므로, 여기서는 타입 간 비율이 핵심.

```
기본값:
  swarm:  {atk: 2.0, hp: 12.0, as: 0.8}
  melee:  {atk: 4.0, hp: 30.0, as: 1.2}
  ranged: {atk: 3.0, hp: 15.0, as: 1.5}
  heavy:  {atk: 5.0, hp: 60.0, as: 2.0}
  sniper: {atk: 6.0, hp: 10.0, as: 2.0}

허용 범위:
  atk: [1.0, 12.0]
  hp:  [5.0, 120.0]
  as:  [0.3, 3.0]
```

**불변 제약**:
- heavy는 최고 HP 타입: heavy.hp >= max(swarm.hp, melee.hp, ranged.hp, sniper.hp)
- 모든 타입 ATK >= 1.0 (최소 피해)
- 모든 타입 AS >= 0.3 (최소 공속)

### 6. 보스 스케일링
```
boss_atk_mult: 기본 1.3, 범위 [1.0, 2.0]
boss_hp_mult:  기본 1.3, 범위 [1.0, 2.0]
```

### 7. 활성화 캡 오버라이드
```
기본값: {} (빈 딕셔너리 = 카드 기본값 사용)
허용 범위: card_id → [1, 10] (정수)
```
특정 카드의 라운드당 최대 발동 횟수를 오버라이드.

---

## 불변 제약 (요약)

모든 genome 변이는 아래 제약을 위반하면 REJECT:

1. **단조증가**: CP 곡선, 기본 수입, 레벨업 비용
2. **합산 제약**: 상점 티어 확률 각 레벨 합 = 100
3. **순서 제약**: 상점 가중평균 티어 단조증가, terazin_win > terazin_lose
4. **범위 제약**: 모든 변수의 min/max
5. **역할 제약**: heavy 최고HP
6. **성능 제약**: R15 적 유닛 <= 80
7. **Lv1 고정**: 상점 Lv1은 T1=100%
8. **card_id 유효성**: activation_caps의 모든 key는 CardDB에 존재하는 card_id여야 함

이 제약들은 genome 로딩 시 검증하고, 위반 시 해당 genome을 무효 처리한다.

---

## 탐색 전략 힌트

### 우선순위 (Phase 순서)

**Phase 1: CP 곡선 + 경제 (가장 큰 레버)**
- win_rate_band: 게임 클리어율 5-10% 목표 (gaussian gradient, 어디서든 gradient 존재)
- CP 곡선 조정으로 클리어율을 목표 대에 맞춤
- 경제 파라미터(수입, 이자, 레벨업 비용)는 빌드 속도를 조절

**Phase 2: 상점 티어 확률 (다양성 레버)**
- card_coverage가 0.11로 매우 낮음
- 고티어 카드 접근 시점이 빌드 다양성에 직접 영향
- 레벨업 비용과 연동하여 탐색

**Phase 3: 적 구성 + 스탯 (전투 양상 조절)**
- 적 유닛 구성은 "어떤 빌드가 유리한가"를 결정
- 단일 프리셋이 특정 테마에 과도하게 유리/불리하면 테마 균형 깨짐
- CP 곡선과 이중 조절 주의: 적 스탯 변경 시 CP 곡선은 고정하고 테스트

### 변이 폭 가이드

- 초기: 큰 변이 (±30%) → 탐색 공간 빠르게 탐험
- 수렴 시작 후: 작은 변이 (±10%) → 미세 조정
- 연속 20회 REJECT 시: 변이 폭 확대 또는 다른 축으로 전환

### 교란 변수 방지

- 한 번에 1개 축만 변이 (CP 곡선만, 또는 경제만, 또는 상점만)
- 2개 이상 동시 변이는 개선/악화 원인 분리 불가
- 예외: 강한 상관이 있는 변수 쌍 (CP 곡선 + 보스 스케일링)은 동시 변이 허용

---

## 금지 사항

1. **카드 효과 수정 금지**: spawn 수, enhance %, shield 값 등은 고정 (콘텐츠 정체성)
2. **커맨더/탈리스만 수치 수정 금지**: 리플레이 시스템의 정체성
3. **업그레이드 수치 수정 금지**: 성장 경로의 정체성
4. **보스 보상 수치 수정 금지**: 보상 설계의 정체성
5. **게임 구조 변경 금지**: MAX_ROUNDS=15, STARTING_FIELD_SLOTS=6, MAX_FIELD_SLOTS=8, MAX_BENCH_SLOTS=8, 플레이어 HP=30
6. **평가기(evaluator.gd) 수정 금지**: Fixed Evaluator 원칙
7. **default_genome.json은 Phase 도중 수정 금지**: mutation seed이자 phase 간 reproducibility anchor. Phase 종료 시에만 갱신하고, 갱신 시 `rejection_history.md` § Phase 별 default_genome.json 스냅샷에 sha256 + 변경 사유 기록.

---

## 평가 시스템 (확정, v7)

8축 고정 평가기. 상세는 evaluator.gd 참조.

| 축 | 가중치 | 측정 대상 |
|----|--------|-----------|
| board_utilization | 0.12 | CP 분배 균등도 (Gini) |
| activation_utilization | 0.08 | 활성화 캡 사용률 |
| win_rate_band | 0.13 | 게임 클리어율 5-10% + 전략 간 편차 |
| tipping_point_quality | 0.17 | 턴어라운드 모멘트 (패배→급성장→승리) |
| dominance_moment | 0.12 | 승리 시 압도감 |
| theme_ratio_variance | 0.13 | AI별 테마 구성 다양성 |
| card_coverage | 0.10 | 카드 사용 범위 |
| emotional_arc | 0.15 | 구간별 승률이 감정 곡선에 부합하는 정도 |

### emotional_arc 축 상세

기획서의 감정 곡선을 4구간으로 측정:

| 구간 | 라운드 | 목표 승률 | 의미 |
|------|--------|-----------|------|
| 여유 | R1-R3 | 70-95% | 학습 구간, 플레이어 우세 |
| 균형 | R4-R7 | 40-70% | 빌드가 맞물려야 이김 |
| 열세 | R8-R12 | 25-55% | ★2+업그레이드 필요 |
| 돌파 | R13-R15 | 15-45% | 완성 빌드로 빡빡하게 |

각 구간의 실제 승률이 목표 범위 안에 있으면 1.0, 벗어나면 거리에 비례하여 감점.
4구간 점수의 평균이 최종 emotional_arc 점수.

### 테마 균형 측정 (결정사항)

`win_rate_band`가 7전략(4테마 focused 포함) 간 편차를 이미 측정하므로,
테마 간 승률 균형은 별도 축 없이 `win_rate_band` 내에서 커버한다.

---

### ADOPT/REJECT 기준

ADOPT 조건: weighted_score(new) > weighted_score(best)
REJECT 조건: weighted_score(new) <= weighted_score(best) 또는 불변 제약 위반
연속 20회 REJECT 시: 사용자 에스컬레이션 (Tier 3)

### 축별 Delta 출력 (결정사항)

batch_runner의 JSON 출력에 각 축의 delta(현재 - baseline) 포함:
```json
{
  "axis_delta": {
    "board_utilization": +0.05,
    "win_rate_band": -0.02,
    ...
  }
}
```
ADOPT/REJECT 기준 자체는 weighted_score 단순 비교로 유지.
에이전트는 delta 정보를 활용해 다음 변이 방향을 선택.
