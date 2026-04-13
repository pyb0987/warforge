---
name: engine-bonus-bump-rejected
date: 2026-04-07
verdict: regressed
hypothesis: "missing engine card bonus +20→+35 (above merge +30) → AI prioritizes diversification over duplicate merging"
result: -0.006 regression
context: ai_v2 + genome optimized to 0.5956
---

# Engine Bonus Bump (+20→+35) Rejected

## Hypothesis
ai_build_path.gd의 score_card_modifier가 missing engine card에 +20을 더함.
ai_agent.gd의 _score_card는 merge bonus(2장 보유 시) +30을 더함.

문제: 동일 카드 중복 구매가 엔진 빈칸 채우기보다 +10 우세 → AI가 다양화 안 함.

가설: missing card bonus를 +35로 올리면 merge bonus를 압도하여 엔진 완성을 우선할 것.

## Test
1 line edit: `mod += 20.0` → `mod += 35.0`

### GUT 테스트
26/26 pass. (test는 `assert_gt(mod, 15.0)`만 검증, 절대값 미고정)

### Diagnostic games (seed=42)
- **predator_focused**: pr_farm×5 → pr_nest×4 변경. 유닛 78 → **167** (2배+). R10→R11. 행동 변화 명확.
- **druid_focused**: 동일 (해당 seed의 shop에 dr critical 카드 미제공)
- **steampunk_focused**: 동일

### Aggregate (10 runs × 7 strategies × 3 measurements)
| Code | Mean | Range |
|------|------|-------|
| OLD (+20) | **0.5956** | 0.5931-0.5977 |
| NEW (+35) | 0.5896 | 0.5838-0.5954 |

**Δ = -0.006 (REGRESSION)**. 노이즈 범위 거의 비중첩 — 진짜 회귀.

## Root Cause
diagnostic은 행동 변화를 보였지만, 행동이 결과로 이어지지 않음:
- predator: foundation(pr_nest) 4장 모았지만 engine(pr_queen, pr_swarm_sense), payoff(pr_parasite), capstone(pr_transcend) 미달성
- 결국 R12에서 패배 (이전과 동일)
- **foundation 과투자가 mid/late game 카드 구매 자원 잠식**

근본 원인: 빌드 패스 단계가 너무 길고, T1-T2 shop에서 engine/payoff 카드 접근 어려움.
AI가 foundation에 자원을 쏟으면 R5+ 에서 engine 카드를 살 골드/레벨이 부족.

## Lesson
1. **행동 변화 ≠ 점수 개선**: 단순 priority 조정은 자원 배분만 바꿈. 게임 결과는 더 복잡.
2. **score_card_modifier는 zero-sum**: 한 카드의 우선순위 ↑ → 다른 카드 ↓
3. **결과: build path 가이드 자체가 game economy와 misalign**: 단계가 너무 많음 (foundation/engine/payoff/capstone). T1-T6 shop과 매핑 안 됨.

## Next Approaches (untried)
- **A. card_value_modifier 보강**: 엔진/페이오프 카드 보호를 +15 → +25로 강화 (판매 방지)
- **B. 경제 변경**: build path가 활성일 때 reroll budget 증가 (engine 카드 찾기)
- **C. shop 카드 풀 편향**: theme strategy일 때 shop이 해당 테마 카드를 우선 노출 (구조적 변경)
- **D. 페이즈 단순화**: foundation+engine 통합, payoff+capstone 통합 (코드 변경 필요)
- **E. AI v3 대기**: ai_build_path 자체를 더 정교하게 설계
- **F. Tier B card effects**: 비군대 테마의 multiplicative scaling (현재 금지)

## Status
- ai_build_path.gd: REVERTED to +20 (line 210)
- best_genome.json: 변경 없음 (mean ~0.5956)
- 다음: B 또는 C 접근 시도 권장
