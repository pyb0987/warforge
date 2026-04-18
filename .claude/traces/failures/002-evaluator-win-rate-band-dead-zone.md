---
date: "2026-04-05"
classification: "제약 미비"
escalated_to: "CLAUDE.md#tier-0-evaluator-설계-규칙"
search_set_id: "SS-002"
resolved: true
resolved_date: "2026-04-18"
escalation_date: "2026-04-07"
recurrence:
  - date: "2026-04-18"
    commit: "TBD (Phase 1 iter 1 fix)"
    context: "failures/002 1회 fix 이후 WIN_RATE_TARGET 0.70→0.075로 이전됐으나 WIN_RATE_SIGMA=0.05 유지. 관측 WR(76%)이 타겟(7.5%)에서 68.9%p 떨어진 상태에서 exp(−94.9) ≈ 1e−41 → 실질 cliff. Phase 1 iter 1 배치에서 cp_curve +40% 상향에도 win_rate_band=0 불변, score는 activation_util/theme_ratio_variance 등 비목표 축에서 +0.0082 상승."
    fix: "WIN_RATE_SIGMA 0.05 → 0.25. dist=0.689에서 exp(−3.80)=0.022 (살아있는 gradient). 타겟 밴드(5-10%) 내 점수는 0.82+ 유지."
promoted_to_feedback: "feedback_evaluator_gaussian_sigma.md"
---

## Failure: autoresearch evaluator의 win_rate_band gradient dead zone

### Observation
autoresearch Phase 1-3 (30 iterations) 동안 win_rate_band 축이 0.00에서 전혀 움직이지 않음.
evaluator 점수는 0.4142 → 0.4945로 개선됐지만, 실제 게임플레이의 WR은 5/7 전략에서 0%로 붕괴.

evaluator v7의 win_rate_band 공식:
```
clamp(1 - |overall_wr - 0.70| / 0.10, 0, 1) × (1 - σ_penalty × 0.5)
```

overall WR이 60% 미만이면 band_score = 0 — gradient가 완전히 소실.
optimizer는 gradient가 있는 다른 축(emotional_arc, tipping_point)을 최대화하는 방향으로 수렴.
그 결과 적을 13-68% 더 어렵게 만들어 "극적인 패배"를 양산 → 높은 arc/tipping 점수.

### Root Cause
- evaluator의 win_rate_band가 cliff function (60% 미만에서 gradient = 0)
- Multi-objective conflict: arc/tipping은 "어려운 게임"을 보상, win_rate는 "적절한 난이도"를 보상
- Tier 0 evaluator가 immutable이므로 optimizer가 evaluator의 맹점을 exploit

### Fix
**해결됨.** evaluator.gd `_score_win_rate_band()`에서 cliff clamp → Gaussian으로 교체:
```gdscript
# Before (cliff): clamp(1 - |overall_wr - 0.70| / 0.10, 0, 1)
# After (gaussian): exp(-dist * dist / (2.0 * WIN_RATE_SIGMA * WIN_RATE_SIGMA))
```
Gaussian은 모든 구간에서 gradient가 존재하여 dead zone 문제를 근본 해결.
Target도 0.70 → WIN_RATE_TARGET(0.075, 5-10% 클리어율 밴드)로 변경.

### Prevention
- Tier 0 evaluator 설계 시 "gradient dead zone" 검토를 체크리스트에 추가
- 축 간 conflict matrix 사전 분석 (축 A 최대화가 축 B를 파괴하지 않는지)

### 2차 재발 교훈 (2026-04-18)
- Gaussian 자체만으로는 불충분 — **σ가 관측 변수 span을 커버**해야 한다.
- 판단 기준: `σ ≥ (관측 최빈값 − 타겟) / 3` 정도면 gradient 0.01+ 보장 (exp(−4.5)).
- 현 사례: 관측 WR 0.70~0.80, 타겟 0.075 → span 0.625+ → σ ≥ 0.21 필요. 0.25로 설정.
