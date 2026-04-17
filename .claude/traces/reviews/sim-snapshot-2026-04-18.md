---
date: "2026-04-18"
type: sim-snapshot
scope: baseline delta 측정 (군대 재설계 + bug fix 3건 + description SSOT 전환 이후)
genome: best_genome.json
runs: 140 (20 × 7 strategies)
seed: 42
weighted_score: 0.4642
refs:
  - godot/sim/program.md (연구 목표, 수용 기준)
  - godot/sim/baseline.json (stale — 전략 naming 불일치)
  - .claude/traces/evolution/012 (군대 R4/R10 재설계)
  - .claude/traces/evolution/013~015 (YAML SSOT 전환)
---

# 시뮬 밸런스 스냅샷 — 2026-04-18

## 1. 맥락

군대 R4/R10 재설계(trace 012, 2026-04-16) 이후 YAML SSOT 전환 세션(trace 013~015, 2026-04-17)에서 다음 bug fix가 런타임에 실제 반영됨:

1. **ml_outpost enhanced_count** (P1-1 migration): `enhanced: partial/all` dead field → `enhanced_count: N` 수량 필드. `_conscript`가 앞 N기를 CONSCRIPT_POOL_ENHANCED에서 pick.
2. **ml_assault swarm_buff enhanced_count** (iter3): `total_units` 계산에 (강화) 가중치 반영. atk_per_unit 버프 + ms_thresh 판정 양쪽에 적용.
3. **ml_tactical enhanced_shield_bonus** (iter3): (강화) 유닛 보유 카드에 `shield_hp_pct += bonus` 가산.
4. **dr_deep tree_bonus.mult** (R4): `bonus_growth_pct` dead field → `mult`. ★3 mult=1.5 실제 적용 (이전 default 1.3).
5. **ml_academy R10 대체** (iter3): rank_gte 내림차순 순회 + tenure slot 공유. R10 spawn이 R4 convert 대체.

이 중 1~3은 **군대 전력에 직접 영향**, 4는 드루이드, 5는 메커니즘 정리(수치 영향 낮음).

## 2. 베이스라인 무효화

`godot/sim/baseline.json`의 `metadata.strategies` 목록이 현재 `ai_agent.gd.STRATEGY_NAMES`와 불일치:

| 구분 | strategies |
|------|-----------|
| baseline (stale) | steampunk/druid/predator/military_focused, hybrid, economy, aggressive |
| 현재 | adaptive, aggressive, economy, soft_{druid,military,predator,steampunk} |

→ batch_runner의 `axis_delta` 계산은 **전략 miss로 인한 zero-fallback** 결과로 의미 없음. 이번 스냅샷은 **절대값**만 유효.

## 3. 현재 스냅샷

### 3.1 전략별 승률

| Strategy | Win Rate | avg_hp | 분류 |
|----------|:--------:|:------:|------|
| economy | 70.0% | +14.35 | 과강 |
| soft_predator | 70.0% | +14.70 | 과강 |
| aggressive | 65.0% | +14.25 | 강 |
| soft_steampunk | 55.0% | +9.95 | 중 |
| **soft_military** | **50.0%** | **+3.80** | **중** |
| adaptive | 35.0% | +0.95 | 약 |
| soft_druid | 35.0% | +3.00 | 약 |

- Mean WR **54.3%**
- σ **0.1512** (program.md 목표 `< 0.10` 미달)
- Max/min ratio **2.00** (목표 `< 3.0` 달성)

### 3.2 거시 지표

| 지표 | 현재 | program.md 목표 | 평가 |
|------|------|-----------------|------|
| weighted_score | 0.4642 | 0.65+ | **미달** |
| 클리어율 평균 | 54.3% | 5-10% | **매우 초과** (게임 쉬움) |
| theme_ratio_variance | 0.5299 | — | — |
| activation_utilization | 0.9587 | — | 양호 |
| board_utilization | 0.6236 | — | 보통 |
| card_coverage | 0.1543 | 70%+ 카드 10%+ 사용 | **대폭 미달** |
| dominance_moment | 0.9388 | — | 양호 |
| emotional_arc | 0.3941 | — | 중간 |
| loss_resilience | 0.6452 | — | 양호 |
| tipping_point_quality | 0.1849 | — | 낮음 |
| win_rate_band | 0.0000 | — | **완전 붕괴** |

## 4. 군대 재설계 + bug fix 영향 해석

직접 baseline delta는 없으나 **타 테마와의 상대 비교**로 추정:

- `soft_military` 50% WR: **균형 범위 내**. soft_steampunk(55%)와 근접, soft_druid(35%)보다 높음.
- avg_hp +3.80 → 다른 focused(+10~+14)보다 낮음 → "이기되 빡빡하게" 설계 의도에 가장 근접.
- bug fix가 (강화) 파워를 실제로 해금한 이후에도 과강/과약 없음.

**결론**: 군대 재설계는 *전력 차원에서* 안정적 수준. 밸런스 이슈는 군대 국지가 아닌 **게임 전체 난이도**(economy/predator 과강, druid 과약, card_coverage/win_rate_band).

## 5. program.md 수용 기준 평가

| 기준 | 현재 | 결과 |
|------|------|------|
| 모든 전략 σ < 0.10 | 0.15 | ✗ |
| 테마 간 WR max/min < 3.0 | 2.00 | ✓ |
| 70%+ 카드가 10%+ 사용 | ~15% | ✗ |
| 클리어율 5-10% | 54.3% | ✗ (대폭 초과) |

3 of 4 미달. autoresearch Phase 재개 또는 genome 재탐색 필요 신호.

## 6. 후속 제안

### 즉시 가능 (현 세션 밖)
- **baseline.json 갱신**: 현 strategy naming으로 재촬영 → 향후 delta 비교 가능
- **program.md update**: 감정 아크 목표 재정의 or strategy 목록 동기화

### 별도 세션 (autoresearch Phase)
- **genome 재탐색**: mean WR을 목표 수준(5-10%)에 가깝게 끌어내기 위해 적 CP 곡선 + enemy 기본 스탯 튜닝
- **card_coverage 개선**: 전략별 카드 편중 완화를 위한 ai 전략 조정
- **emotional arc 재설계**: 현 win_rate_band 0.00 → 라운드별 감정 곡선 회복

### 군대 범위
- 현 재설계 + bug fix는 안정적 → 추가 작업 불필요
- 단, 다른 테마(특히 드루이드) 약화가 상대 편중을 만들 수 있으므로 주기적 스냅샷 권장
