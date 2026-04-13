---
name: autoresearch-v1
verdict: adopted
weighted_score_start: 0.414
weighted_score_end: 0.595
clear_rate: 5.7%
iterations_total: 55
adopts_total: 13
date: 2026-04-04
---

# Autoresearch v1 — First Genome Optimization Run

## Scope
AI agent v5 + 8-axis evaluator + 3-phase genome optimization.

## Evaluator Change (mid-experiment)
- win_rate_band: per-round WR 60-80% → **per-game clear rate 5-10%** (gaussian gradient)
- 이유: cliff function (WR < 60% → score=0)이 gradient dead zone 생성.
  optimizer가 WR 밴드 밖에서 방향을 찾지 못해 적을 더 강하게 만드는 방향으로 진화.
- 효과: 변경 후 즉시 win_rate_band > 0, optimizer가 클리어율 5-10%를 향해 수렴.

## Phase Results

### Phase 1: CP curve + Economy (30 iterations)
- Round 1 (10 iter): 6 ADOPTs, 0.414→0.467
- Round 2 (10 iter): 1 ADOPT, 0.467→0.480
- Round 3 (post-evaluator, 15 iter): 2 ADOPTs, 0.516→0.555
- 핵심 변화: CP curve R12-R15 대폭 상승, base_income +1g

### Phase 2: Shop Tier Weights (10 iterations)
- 1 ADOPT, 0.555→0.557
- 약한 효과: shop tiers는 현재 genome에서 low-leverage

### Phase 3: Enemy Composition + Stats (10 iterations)
- 2 ADOPTs, 0.557→0.594
- 핵심 변화: tipping_point_quality +0.21 (적 구성 변경으로 턴어라운드 패턴 생성)

## Remaining Issues
- druid/predator/steampunk 클리어율 0% — 전략간 σ가 크므로 win_rate_band 점수 제한
- card_coverage 0.18 — 여전히 낮음 (54장 중 활용 부족)
- 목표 0.65+ 미달성 (0.595)

## Next Steps
- 더 많은 iteration (연속 20회 REJECT까지 각 phase 반복)
- 전략간 σ 축소를 위해 AI agent v6 고려 (druid/steampunk 전략 개선)
- activation_caps 탐색 추가 (특정 카드 cap 조정)
