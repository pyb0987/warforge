---
name: activation-caps-boss
verdict: exhausted
weighted_score_start: 0.6583
weighted_score_end: 0.6583
clear_rate: 5.7%
iterations_total: 25
adopts_total: 0
date: 2026-04-05
---

# Activation Caps + Boss Scaling Experiment

## Scope
Phase 4: activation_caps + boss_scaling 개별 변이 (15 iterations)
Phase 5: 결합 변이 (10 iterations)

## Results
- Phase 4: 0 ADOPTs / 15 iterations. 모든 변이가 REJECT.
- Phase 5: 0 ADOPTs / 10 iterations. 모든 변이가 REJECT.

## Analysis

### activation_caps가 작동하지 않는 이유
- 군대 카드 발동 제한 → 군대 WR 하락 → 전체 클리어율 하락 → weighted_score 하락
- 군대를 약화시켜도 비군대가 강해지지 않음 (independent paths)
- 오히려 군대가 가끔 이기던 게임마저 잃어서 win_rate_band 악화

### boss_scaling이 작동하지 않는 이유
- 보스 라운드(R4,R8,R12,R15)만 영향. 전체 15라운드 중 4라운드만.
- 보스 약화 → 보스 라운드 승률 소폭 상승 → 비보스 라운드에서 이미 지는 전략엔 무의미
- 보스 강화 → 보스 라운드 승률 하락 → emotional_arc 악화

### 핵심 교훈
**드루이드/스팀펑크/포식종의 0% 클리어는 "군대가 너무 강해서"가 아니라 "비군대가 너무 약해서".**
genome 파라미터 공간 전체(Phase 1-5)를 소진. 남은 레버는 카드 효과 수치 자체뿐.

## Decision Trigger
→ "카드 효과 수정 금지" 해제 논의로 에스컬레이션.
