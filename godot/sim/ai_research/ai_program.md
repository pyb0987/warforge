# AI Autoresearch Program — AI Agent Decision Optimization

## Layer 구분

| Layer | 대상 | 파일 위치 | 보호 |
|-------|------|----------|------|
| Layer 1 | 게임 밸런스 (적 CP, 경제, 상점) | `godot/sim/` | Tier 0 immutable |
| **Layer 2** | **AI 의사결정 (구매/레벨업/판매 기준)** | **`godot/sim/ai_research/`** | 이 파일 |

Layer 2는 Layer 1의 게임 파라미터를 **freeze**한 채로 AI 행동만 최적화한다.

---

## 연구 목표

### 1차 목표: AI가 인간 수준으로 플레이

| 목표 | 측정 | 수용 기준 |
|------|------|-----------|
| 게임 밸런스 유지 | weighted_score (Evaluator 9축) | 현재 baseline 이상 |
| 전략 다양성 | 7 전략 승률 분포 | steampunk/druid 0% 탈출 |
| AI 품질 | ai_quality_score (AIEvaluator 4축) | 0.50+ |

### 2차 목표: Phase 3 준비

Layer 2 최적화 완료 후, 최적 ai_params를 Layer 1 best_genome.json에 합류시킨 뒤
Layer 1에서 게임 밸런스 재최적화 (Phase 3) 진행.

---

## 탐색 변수 — 17개 Tier 1 AI Params

| 파라미터 | 기본값 | 범위 | 역할 |
|---------|--------|------|------|
| theme_match_bonus | 15.0 | [5, 30] | 온테마 구매 보너스 |
| off_theme_penalty | 20.0 | [5, 35] | 오프테마 패널티 |
| merge_imminent_bonus | 30.0 | [15, 50] | ★2 임박 보너스 |
| merge_progress_bonus | 8.0 | [2, 20] | 2카피 보너스 |
| core_card_bonus | 12.0 | [4, 25] | 핵심 카드 보너스 |
| critical_path_bonus | 8.0 | [2, 20] | 필수 경로 보너스 |
| synergy_pair_bonus | 6.0 | [2, 15] | 시너지 쌍 보너스 |
| late_tier_bonus | 6.0 | [2, 15] | 후반 고티어 선호 |
| slow_roll_min_round | 5 | [3, 8] | 슬로우롤 시작 |
| slow_roll_board_cp_ratio | 1.5 | [0.8, 3.0] | 슬로우롤 강도 문턱 |
| interest_all_start | 4 | [2, 8] | 이자 뱅킹 시작 |
| aggro_transition_round | 10 | [7, 14] | 올인 전환 |
| chain_pair_reroll_bonus | 3 | [0, 8] | 체인 미완성 리롤 |
| foundation_urgency_rerolls | 5 | [0, 10] | 기초 부재 리롤 |
| capstone_urgency_rerolls | 3 | [0, 8] | 캡스톤 부재 리롤 |
| bench_sell_threshold | 12.0 | [5, 25] | 벤치 정리 기준 |
| arsenal_fuel_bonus | 15.0 | [5, 30] | 아스널 연료 판매 |

---

## 평가 체계

### Game Balance (Evaluator, 9축, immutable)
기존 evaluator.gd 그대로. AI가 잘 플레이할수록 게임 결과가 개선되므로
weighted_score 상승 = AI 개선.

### AI Quality (AIEvaluator, 4축)
| 축 | 가중치 | 측정 |
|----|--------|------|
| economy_efficiency | 0.25 | 골드 활용 효율 |
| merge_rate | 0.25 | 최종 덱 평균 ★ |
| board_strength_curve | 0.25 | CP 성장 단조성 |
| card_diversity | 0.25 | 카드 사용 다양성 |

### ADOPT/REJECT 기준
- **Primary**: weighted_score(new) > weighted_score(best) → ADOPT
- AI quality는 참고 지표 (진단용, ADOPT 기준 아님)
- 연속 20회 REJECT → 에스컬레이션

---

## 실행 방법

```bash
# 초기화 (Layer 1 best_genome + default ai_params → baseline 생성)
python3 godot/sim/ai_research/ai_autoresearch.py --init --runs=20

# 최적화 실행
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=30 --strength=0.20

# 커스텀 설정
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=50 --strength=0.15 --seed=42 --runs=20
```

---

## 금지 사항

1. Layer 1 파일 수정 금지 (autoresearch.py, evaluator.gd, batch_runner.gd, program.md, baseline.json, best_genome.json)
2. 게임 밸런스 파라미터 변이 금지 (enemy_cp_curve, economy, shop_tier_weights 등)
3. ai_batch_runner.gd 내에서 Evaluator 축 가중치 변경 금지
