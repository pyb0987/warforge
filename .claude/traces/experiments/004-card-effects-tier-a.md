---
session: "autoresearch/phase6-20260405"
date: "2026-04-05"
experiment_range: "E1-E15"
adopts: 2
rejects: 13
metric_start: 0.6583
metric_end: 0.6610
---

# Episode 004: Card Effects Tier A — Non-Military Theme Scaling

## Context
genome 파라미터 공간 전부 소진 (Phase 1-5, 135 iterations). Multi-review #2로 "카드 효과 수정 금지" 해제 범위를 결정하고, Tier A 5개 additive 파라미터를 genome에 노출.

- program.md 방향: 비군대(DR/PR/ST) 0% 클리어 → 카드 효과 수치 조정으로 CP 격차 해소
- 이전 에피소드 교훈: 003 — activation_caps/boss_scaling은 군대를 약화시킬 뿐 비군대를 강화하지 못함. "비군대가 너무 약해서"가 근본 원인.

### 해제된 파라미터 (Tier A — additive enhance 계열)
| card_id | param | 기본값 | genome 범위 | 선정 근거 |
|---------|-------|--------|-------------|-----------|
| dr_deep | rate | 0.008 | [0.004, 0.020] | 드루이드 핵심 성장률, continuous float, isolated |
| pr_swarm_sense | buff | 0.10 | [0.05, 0.25] | 포식종 유일의 전투 ATK 스케일러 |
| sp_charger | enhance_atk | 0.05 | [0.02, 0.12] | 스팀펑크 유일의 누적 성장, threshold와 독립 |
| pr_carapace | growth | 0.05 | [0.02, 0.15] | 단순 가산, hatch chain과 독립 |
| pr_transcend | death_atk | 0.03 | [0.01, 0.10] | combat engine float 저장, 완전 isolated |

### Implementation
- genome.gd: `card_effects` dict (DEFAULT_CARD_EFFECTS, CARD_EFFECTS_RANGE, validate)
- 전파 경로: genome → headless_runner → chain_engine.propagate_card_effects() → theme_system.card_effects
- ★2/★3는 ★1 기본값 대비 비례 스케일 유지 (예: dr_deep ★2 = rate×1.5)

## Key Experiments

### Raw Output
```
Baseline weighted_score: 0.6583
Phase 6 — 15 iterations, strength=0.20, mutators: [card_effects]

[  1] card_effects (s=0.20) REJECT 0.6475 (-0.0109) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  2] card_effects (s=0.20) REJECT 0.6489 (-0.0094) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  3] card_effects (s=0.20) REJECT 0.6469 (-0.0114) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  4] card_effects (s=0.20) REJECT 0.6515 (-0.0068) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  5] card_effects (s=0.20) ADOPT  0.6594 (+0.0011) [AG10 DR0 EC10 HY10 MI10 PR0 ST0]
      Top deltas: emotional_arc:+0.013, activation_utilization:-0.004, card_coverage:-0.003
[  6] card_effects (s=0.18) REJECT 0.6456 (-0.0138) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  7] card_effects (s=0.18) REJECT 0.6450 (-0.0144) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  8] card_effects (s=0.18) REJECT 0.6490 (-0.0104) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[  9] card_effects (s=0.18) ADOPT  0.6610 (+0.0016) [AG10 DR0 EC10 HY10 MI10 PR0 ST0]
      Top deltas: emotional_arc:+0.008, activation_utilization:+0.003
[ 10] card_effects (s=0.16) REJECT 0.6469 (-0.0142) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[ 11] card_effects (s=0.16) REJECT 0.6601 (-0.0009) [AG10 DR0 EC10 HY10 MI10 PR0 ST0]
[ 12] card_effects (s=0.16) REJECT 0.6453 (-0.0157) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[ 13] card_effects (s=0.16) REJECT 0.6480 (-0.0131) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
[ 14] card_effects (s=0.16) REJECT 0.6470 (-0.0140) [AG0 DR0 EC10 HY10 MI10 PR0 ST0]
      [Widening search: strength → 0.19]
[ 15] card_effects (s=0.19) REJECT 0.6597 (-0.0013) [AG10 DR0 EC10 HY10 MI10 PR0 ST0]
      [Widening search: strength → 0.23]

Final score: 0.6610, ADOPTs: 2/15
```

### Per-Iteration Table
| # | Verdict | Score | Δ | Strength | Strategy WRs | Insight |
|---|---------|-------|---|----------|--------------|---------|
| 1 | REJECT | 0.6475 | -0.0109 | 0.20 | AG0 DR0 EC10 HY10 MI10 PR0 ST0 | 변이 방향 불리 |
| 2 | REJECT | 0.6489 | -0.0094 | 0.20 | 동일 | |
| 3 | REJECT | 0.6469 | -0.0114 | 0.20 | 동일 | |
| 4 | REJECT | 0.6515 | -0.0068 | 0.20 | 동일 | 가장 작은 REJECT — 근접 |
| **5** | **ADOPT** | **0.6594** | **+0.0011** | 0.20 | **AG10** DR0 EC10 HY10 MI10 PR0 ST0 | emotional_arc +0.013 주도. AG 0→10% |
| 6 | REJECT | 0.6456 | -0.0138 | 0.18 | AG0 | ADOPT 후 strength 감소, 연속 REJECT 시작 |
| 7 | REJECT | 0.6450 | -0.0144 | 0.18 | AG0 | |
| 8 | REJECT | 0.6490 | -0.0104 | 0.18 | AG0 | |
| **9** | **ADOPT** | **0.6610** | **+0.0016** | 0.18 | **AG10** DR0 EC10 HY10 MI10 PR0 ST0 | emotional_arc +0.008, activation_util +0.003 |
| 10 | REJECT | 0.6469 | -0.0142 | 0.16 | AG0 | |
| 11 | REJECT | 0.6601 | -0.0009 | 0.16 | AG10 | 근소 REJECT — 거의 채택 수준 |
| 12 | REJECT | 0.6453 | -0.0157 | 0.16 | AG0 | |
| 13 | REJECT | 0.6480 | -0.0131 | 0.16 | AG0 | |
| 14 | REJECT | 0.6470 | -0.0140 | 0.16 | AG0 | 연속 5 REJECT → strength 확대 |
| 15 | REJECT | 0.6597 | -0.0013 | 0.19 | AG10 | 근소 REJECT |

## Adopted Changes

### ADOPT #5 (E5): pr_transcend_death_atk 미세 하향
- `pr_transcend_death_atk`: 0.03 → 0.0297 (-1%)
- 채택 후 best_genome.json 반영 확인
- emotional_arc +0.013이 주 기여 축

### ADOPT #9 (E9): pr_swarm_sense_buff 하향
- `pr_swarm_sense_buff`: 0.10 → 0.0944 (-5.6%)
- 예상 외 방향 — buff 하향이 채택됨
- 가설: 포식종 전투력 소폭 하락 → aggressive 전략 간접 수혜 → emotional_arc 개선

### 최종 card_effects 상태
```json
{
  "dr_deep_rate": 0.008,        // 변동 없음
  "pr_swarm_sense_buff": 0.0944, // -5.6%
  "sp_charger_enhance_atk": 0.05, // 변동 없음
  "pr_carapace_growth": 0.05,     // 변동 없음
  "pr_transcend_death_atk": 0.0297 // -1.0%
}
```

## Exhausted Axes

### Tier A additive 파라미터 (부분 소진)
- `dr_deep_rate`: 15회 중 변이 채택 0건. 드루이드 전략 자체가 0% 클리어 → rate 변이가 evaluator 8축에 신호 없음
- `sp_charger_enhance_atk`: 15회 중 채택 0건. 동일 이유 (스팀펑크 0% 클리어)
- `pr_carapace_growth`: 15회 중 채택 0건. carapace 발동 빈도가 낮아 enhance 수치 변이 효과 미미
- `pr_swarm_sense_buff`, `pr_transcend_death_atk`: 소폭 하향만 채택. 상향 변이는 전부 REJECT

**근본 원인**: Tier A 파라미터는 전부 additive enhance 계열. experiment 002에서 이미 확인된 "additive 성장으로는 군대의 multiplicative CP 격차를 못 좁힌다"와 동일한 한계. 비군대 전략이 0% 클리어인 상태에서 additive 수치를 올려봤자 evaluator 승률 축에 변화가 없음.

## Lesson
- **Additive 파라미터 단독으로는 0% → >0% 전환 불가**. 승률 축 변화가 없으면 evaluator가 채택할 이유가 없음.
- **Tier B multiplicative 레버(dr_world.base_atk)가 필요** — 지수 성장의 밑수를 바꿔야 CP 곡선 자체가 변함.
- 유망한 방향: dr_world.base_atk (1.10 → [1.05, 1.25]), dr_deep.mult (1.3 → [1.15, 1.8])
- 경고: dr_world.base_atk와 dr_deep.rate/mult 동시 변이 시 곱셈 폭발 — 반드시 교란 변수 격리 (한 번에 하나만)
- 초기 골드를 genome에 포함하는 것도 검토 중 (사용자 요청)
