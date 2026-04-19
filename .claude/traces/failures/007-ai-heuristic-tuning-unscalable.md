---
date: "2026-04-19"
classification: "제약 미비"
escalated_to: null
resolved: false
search_set_id: null
---

## Failure: AI 휴리스틱 단일 상수 튜닝이 전략별 분기 효과

### Observation
soft_steampunk 60 runs 0/60 (0% WR)에 대한 진단: coverage dump 결과
- T4/T5 카드 접근성 문제 아님 (문제의 일부이지만 본질 아님)
- SP가 `_play_soft_theme`에서 ml_barracks 같은 타 테마 T1을 off_theme_penalty=20 때문에 거의 안 삼 (12 vs aggressive 62)
- SP는 sp_assembly/sp_furnace/sp_workshop만으로 deck 구성 → R8 보스(CP 5.67)에서 사망

**가설 A**: off_theme_penalty 20 → 12로 완화하면 SP가 혼합 빌드로 전환 → 회복 가능

**가설 B**: pressure-aware 동적 완화 (후반 CP 상승 시 penalty 자동 감소)

### 실험 결과

baseline: weighted_score 0.5411, soft_steampunk 0/60, soft_military 1/60

| 실험 | weighted_score | SP | SM | SD | mean WR | 판정 |
|------|:-:|:-:|:-:|:-:|:-:|---|
| A (12) | 0.5389 | 1/60 | 0/60 | 1/60 | 3.57% | 부분 성공 + military regression |
| A+B | 0.5322 | 0/60 | 0/60 | 0/60 | 2.62% | 전면 실패 |

A+B에서 모든 theme-focused 전략이 regression. pressure-aware 완화가 초반에는 
penalty × 1.09 (UP), 후반에 × 0.70 (DOWN)으로 작동했지만, 전략들의 build path 
decision에서 non-monotonic 효과 유발.

### Root Cause
1. **AI 휴리스틱은 전략별 build_path 로직과 얽혀있다**: 단일 상수 변경이 
   전략마다 다른 효과. SP에 도움 = SM에 해로움 (build_path divergence 때문).
2. **off_theme_penalty는 설계 의도 보호 상수**: 완화하면 theme commit 의미 
   상실. SP의 0% 문제는 commit 부족이 아니라 **현 CP curve(4.2x default)에서 
   steampunk 체인 자체가 전력 부족**.
3. **휴리스틱 튜닝의 비대칭성**: autoresearch mutator가 ai_params를 변이 
   대상에서 제외한 이유가 이것. 전역 상수 튜닝은 전략간 편차 증폭.

### Fix
사용자 지시에 따라 A+B 모두 revert. 원래 상태 복원 (penalty=20).

### Prevention / 교훈
- **soft_X 전략별 문제는 해당 전략의 AI 로직 자체 개선으로 접근** (ai_build_path.gd의 
  soft_steampunk branch 강화, steampunk-specific reroll 정책 등)
- **전역 AI 휴리스틱 상수 변경은 모든 전략 회귀 테스트 필수** — 한 전략 
  개선이 다른 전략 악화 패턴
- **Phase 2 (shop tiers) 또는 card balance**가 더 직접적 레버일 가능성 
  — SP steampunk 카드 자체의 설계 재검토 필요

### Related
- feedback_evaluator_gaussian_sigma.md: 평가기 튜닝 유사 교훈
- failures/002: evaluator 3회 재발 — heuristic/평가기 모두 설계의도 직결
