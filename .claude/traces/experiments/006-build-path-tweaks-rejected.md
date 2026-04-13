---
session: "auto-search/session-20260407-090000"
date: "2026-04-07"
experiment_range: "E1-E2"
adopts: 0
rejects: 2
metric_start: 0.5956
metric_end: 0.5956
ai_version: "v2 (unchanged)"
---

## Episode 006: Build Path AI 행동 조정 시도 (2회 모두 REJECT)

### Context
Episode 005 결론: genome 공간 ceiling ~0.59. DR/ST/AG 0% 문제는 AI 행동(build path)에서 해결 필요.
Plan(piped-jumping-unicorn.md) 검증 결과: ai_build_path.gd가 이미 ai_agent.gd에 연결되어 있음 (line 81-82, 569, 686).
- 이전 에피소드 교훈: Episode 005에서 단순 genome tuning은 비군대 테마 0% 해결 불가.
- 본 세션 목표: build path 가이드를 더 강하게 적용하여 비군대 테마 win rate 개선.

### Diagnostic 진단 (수정 전)
seed=42 게임 분석:
- **druid**: dr_lifebeat ×4, dr_cradle ×1 — foundation만 모이고 engine/payoff 미달성. R12 패배.
- **steampunk**: sp_assembly ×4, sp_workshop ×5, sp_warmachine ×2 — payoff까지 도달했으나 R12 HP=-10 패배.
- **predator**: pr_farm ×5 — foundation만, units=78. R10 패배.
- **military**: ml_outpost ×3, ml_barracks ×4, ml_command — diverse build, units=134. R15 도달.

핵심 관찰: 비군대는 동일 카드 중복 구매, 군대는 다양화. 원인 분석:

| 시나리오 | 점수 |
|----------|------|
| 중복 카드 (merge) | theme +15 + merge +30 + tier +2 = **+47** |
| 누락된 engine 카드 | theme +15 + engine gap +20 + tier +2 = **+37** |

merge가 engine completion보다 +10 우세 → AI가 다양화 안 함.

### Raw Output

#### E1: missing engine card bonus +20→+35
**가설**: bonus를 +35로 올리면 merge bonus(+30) 압도 → 다양화 우선.

```
Edit ai_build_path.gd line 210: mod += 20.0 → mod += 35.0
GUT 테스트: 26/26 pass

Diagnostic seed=42:
  predator: pr_farm×5 → pr_nest×4 (foundation 다양화)
            units 78 → 167 (2배+)
            R10 → R11 (1라운드 더 생존)
  druid/steampunk: 동일 (해당 seed shop에 critical 카드 미제공)

Aggregate (3 measurements × 10 runs × 7 strategies):
  OLD (+20): mean 0.5956, range 0.5931-0.5977
  NEW (+35): mean 0.5896, range 0.5838-0.5954
  Δ = -0.006 REJECT
```

#### E2: build path reroll urgency 모든 페이즈 확장
**가설**: 자원 배분 변경 없이 exploration depth만 늘리면 zero-sum 회피.

```
Edit ai_agent.gd: foundation urgency (R1-R4) → 모든 페이즈 (engine/payoff/capstone에서 +3 reroll)
GUT test_ai_agent: 9/9 pass

Aggregate:
  OLD: mean 0.5956
  NEW: mean 0.5947, range 0.5933-0.5956
  Δ = -0.001 REJECT (within noise)

특이사항: predator_focused 3/3 runs 일관되게 10% 승리 (이전엔 가변적)
        하지만 다른 strategies가 미세하게 손해
```

### Key Experiments
| # | Hypothesis | Verdict | Δ | Insight |
|---|-----------|---------|---|---------|
| E1 | Engine bonus +20→+35 | REJECT | -0.006 | 행동 변화는 명확 (predator 167 units), but 결과 미개선. Foundation 과투자가 mid-game 카드 잠식 |
| E2 | Reroll urgency 모든 페이즈 | REJECT | -0.001 | predator 안정화되지만 aggregate flat. Zero-sum 압박 여전 |

### Adopted Changes
없음. 모두 revert. 코드는 v2 baseline 그대로.

### Exhausted Approaches
- **score_card_modifier 수치 조정**: 상한 도달. +35는 너무 강함, +20은 merge에 밀림.
- **reroll budget 확장**: 카드 풀이 작아서 reroll로 다른 카드가 안 나옴.

### Lesson
- **유망한 방향**:
  - **D. 페이즈 단순화**: foundation+engine 통합 (T1-T2 shop 매핑), payoff+capstone 통합 (T4-T5)
  - **C. shop 카드 풀 편향**: 테마 strategy일 때 shop이 해당 테마 카드를 우선 노출 (구조적 변경, 불변 제약 검토 필요)
  - **F. Tier B card effects**: 비군대 테마의 multiplicative scaling (현재 "카드 효과 수정 금지" 해제 필요)
- **경고**:
  - 단일 수치 조정은 zero-sum. 다른 카드/전략이 손해를 봄.
  - "행동 변화 ≠ 점수 개선": diagnostic만으로 판단 금지. aggregate 측정 필수.
  - REJECT 누적 → 더 큰 구조적 변경이 필요한 신호.
- **다음 단계**: 사용자 에스컬레이션. D/C/F 중 선택 또는 전혀 다른 접근.

### Status
- best_genome.json: 변경 없음 (mean ~0.5956)
- ai_agent.gd: v2 그대로 (foundation reroll +5만)
- ai_build_path.gd: 원본 (+20)
- failure trace: .claude/traces/failures/003-engine-bonus-bump-rejected.md
