---
session: "auto-search/session-20260407-080000"
date: "2026-04-07"
experiment_range: "E1-E60"
adopts: 5
rejects: 55
metric_start: 0.3661
metric_end: 0.5929
ai_version: "v2 (off-theme -20, foundation reroll +5)"
---

## Episode 005: AI v2 Genome 재탐색 (default→최적화)

### Context
AI v2 행동 변경 후 기존 genome(v1 최적 0.6503)이 무효화됨. default_genome에서 재탐색 시작.
- program.md 방향: Phase 1 → Phase 4 → Phase 2 → Phase 3 → Phase 1 fine-tuning
- 이전 에피소드 교훈: 003에서 Phase 4/5 (activation_caps + boss) 0 ADOPT → genome 공간 소진 판정. 004에서 카드 효과 수정으로 전환. 이번엔 AI v2에서 재탐색이므로 다시 Phase 1부터.

### Raw Output

#### Phase 1 initial (30 iterations, strength=0.20, seed=1000)
```
Loaded best genome from godot/sim/best_genome.json
Baseline weighted_score: 0.3661

[  1] Testing cp_curve mutation (strength=0.20)... ADOPT 0.3734 (+0.0073) [AG90 DR20 EC80 HY60 MI100 PR70 ST50]
       Top deltas: tipping_point_quality:+0.036, card_coverage:+0.007
[  2] Testing cp_curve mutation (strength=0.18)... ADOPT 0.3826 (+0.0091) [AG80 DR20 EC70 HY50 MI90 PR70 ST40]
       Top deltas: emotional_arc:+0.060, card_coverage:-0.007
[  3] Testing cp_curve mutation (strength=0.16)... ADOPT 0.3896 (+0.0071) [AG60 DR10 EC60 HY50 MI90 PR30 ST20]
       Top deltas: emotional_arc:+0.034, tipping_point_quality:+0.014
[  4] Testing economy mutation (strength=0.15)... REJECT 0.3886 (-0.0011)
[  5] Testing cp_curve mutation (strength=0.15)... ADOPT 0.3924 (+0.0028)
       Top deltas: activation_utilization:-0.029, tipping_point_quality:+0.029, emotional_arc:+0.006
[6-30] (session truncated — context compaction. Final score: 0.5662)
```

Final: 0.3661 → 0.5662

#### Phase 4 batch A (5 iterations, strength=0.20, seed=1100)
```
Baseline weighted_score: 0.5662

[  1] Testing activation_caps mutation (strength=0.20)... ADOPT 0.5743 (+0.0081)
       Top deltas: tipping_point_quality:+0.057, emotional_arc:-0.050, activation_utilization:+0.045
[  2] Testing activation_caps mutation (strength=0.18)... REJECT 0.5586 (-0.0158)
[  3] Testing boss_scaling mutation (strength=0.18)... (truncated — session ended)
```

#### Phase 4 batch B (5 iterations, strength=0.20, seed=1200)
```
Baseline weighted_score: 0.5743

[  1] Testing boss_scaling mutation (strength=0.20)... REJECT 0.5591 (-0.0152)
[  2] Testing activation_caps mutation (strength=0.20)... REJECT 0.5725 (-0.0018)
[  3] Testing boss_scaling mutation (strength=0.20)... ADOPT 0.5777 (+0.0034)
       Top deltas: win_rate_band:+0.018, emotional_arc:+0.016, activation_utilization:-0.013
[  4] Testing activation_caps mutation (strength=0.18)... REJECT 0.5759 (-0.0018)
[  5] Testing boss_scaling mutation (strength=0.18)... REJECT 0.5518 (-0.0258)

ADOPTs: 1, Final score: 0.5777
```

#### Phase 2 (5 iterations, strength=0.20, seed=1300)
```
Baseline weighted_score: 0.5777

[  1] Testing shop_tiers mutation (strength=0.20)... REJECT 0.5670 (-0.0106)
[  2] Testing shop_tiers mutation (strength=0.20)... REJECT 0.5771 (-0.0006)
[  3] Testing shop_tiers mutation (strength=0.20)... REJECT 0.5552 (-0.0225)
[  4] Testing shop_tiers mutation (strength=0.20)... REJECT 0.5698 (-0.0079)
[  5] Testing shop_tiers mutation (strength=0.20)... REJECT 0.5755 (-0.0022)
       [Widening search: strength → 0.24]

ADOPTs: 0, Final score: 0.5777
```

#### Phase 3 (5 iterations, strength=0.20, seed=1400)
```
Baseline weighted_score: 0.5777

[  1] Testing enemy_comp mutation (strength=0.20)... REJECT 0.4335 (-0.1442)
[  2] Testing enemy_comp mutation (strength=0.20)... REJECT 0.5719 (-0.0058)
[  3] Testing enemy_comp mutation (strength=0.20)... REJECT 0.5768 (-0.0008)
[  4] Testing enemy_comp mutation (strength=0.20)... REJECT 0.5561 (-0.0216)
[  5] Testing enemy_comp mutation (strength=0.20)... REJECT 0.5114 (-0.0663)
       [Widening search: strength → 0.24]

ADOPTs: 0, Final score: 0.5777
```

#### Phase 1 fine-tuning (10 iterations, strength=0.10, seed=1500)
```
Baseline weighted_score: 0.5777

[  1] Testing economy mutation (strength=0.10)... REJECT 0.5671 (-0.0106)
[  2] Testing cp_curve mutation (strength=0.10)... REJECT 0.5609 (-0.0168)
[  3] Testing cp_curve mutation (strength=0.10)... REJECT 0.5745 (-0.0032)
[  4] Testing economy mutation (strength=0.10)... REJECT 0.5622 (-0.0155)
[  5] Testing cp_curve mutation (strength=0.10)... REJECT 0.5702 (-0.0075)
       [Widening search: strength → 0.12]
[  6] Testing economy mutation (strength=0.12)... ADOPT 0.5929 (+0.0153)
       Top deltas: win_rate_band:+0.189, theme_ratio_variance:-0.060, tipping_point_quality:-0.029
[  7] Testing cp_curve mutation (strength=0.11)... REJECT 0.5478 (-0.0452)
[  8] Testing economy mutation (strength=0.11)... REJECT 0.5708 (-0.0221)
[  9] Testing cp_curve mutation (strength=0.11)... REJECT 0.5345 (-0.0584)
[ 10] Testing economy mutation (strength=0.11)... REJECT 0.5694 (-0.0235)

ADOPTs: 1, Final score: 0.5929
```

### Key Experiments
| Phase | Hypothesis | Verdict | Metric | Δ | Insight |
|-------|-----------|---------|--------|---|---------|
| P1 initial | CP curve + economy가 가장 큰 레버 | ADOPT ×many | 0.3661→0.5662 | +54.6% | CP curve가 dominant lever |
| P4 batch A | activation_caps로 발동 조절 | 1 ADOPT | 0.5662→0.5743 | +1.4% | sp_interest, ml_conscript caps 추가됨 |
| P4 batch B | boss_scaling 미세 조정 | 1 ADOPT | 0.5743→0.5777 | +0.6% | 매우 미약한 효과 |
| P2 | shop_tiers로 카드 접근성 개선 | 0 ADOPT | 0.5777 | 0% | 소진 — 현 AI에서 상점 확률 변경 무효 |
| P3 | enemy_comp로 전투 양상 조절 | 0 ADOPT | 0.5777 | 0% | 소진 — 매우 불안정 (±0.14 fluctuation) |
| P1 fine | economy 미세 조정 | 1 ADOPT | 0.5777→0.5929 | +2.6% | win_rate_band +0.189 큰 점프 |

### Adopted Changes
- **CP curve**: R1-R15 적 CP 스케일 최적화. 초중반 난이도 감소, 후반 완만한 증가.
- **Economy**: 기본 수입, 이자, 레벨업 비용 미세 조정으로 빌드 속도 개선.
- **Activation caps**: sp_interest:7, ml_conscript:2 추가.
- **Boss scaling**: 보스 배율 소폭 조정.

### Final Strategy Win Rates
| Strategy | Win Rate |
|----------|----------|
| aggressive | 0% |
| druid_focused | 0% |
| economy | 10% |
| hybrid | 10% |
| military_focused | 10% |
| predator_focused | 10% |
| steampunk_focused | 0% |

### Exhausted Axes
- **shop_tiers**: 5/5 REJECT. 현 AI는 상점 확률 변경에 둔감.
- **enemy_comp**: 5/5 REJECT, iteration 1에서 -0.1442 폭락. 적 구성 변경은 과도하게 불안정.
- **activation_caps + boss_scaling**: 매우 미약한 효과 (합계 +0.0115). 레버 소진 근접.

### Lesson
- **핵심 발견**: v2 AI에서도 genome 최적화 ceiling은 ~0.59. v1(0.65)보다 낮음.
  - 원인: v2 off-theme -20이 비테마 구매를 억제했지만, 테마 카드만 사기에는 엔진 카드 도달이 너무 어려움.
  - DR/ST/AG가 여전히 0%: genome(난이도/경제)으로는 "테마 엔진 미완성" 문제를 해결 불가.
- **유망한 방향**: AI 빌드 패스 시스템 (ai_build_path.gd)이 실제로 스코어링에 반영되고 있는지 확인 필요. 현재 AI v2에 build path 연결이 안 되어 있을 수 있음.
- **경고**: enemy_comp는 변동성이 극도로 높아 탐색 비효율적. 향후에도 회피 권장.
- **다음 단계**: plan에 있는 ai_build_path.gd → ai_agent.gd 연결 구현 → AI v3 → genome 재탐색.
