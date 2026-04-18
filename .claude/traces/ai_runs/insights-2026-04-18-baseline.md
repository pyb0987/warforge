# AI Trace Insights — baseline 20-run (2026-04-18)

Genome: ai_best_genome.json (post A fix). Commit ref: 6e957b1.

## Strategy WR + top buys

| Strategy | WR | Capstone buys (T4/T5) in top10 |
|----------|-----|-------------------------------|
| soft_steampunk | 40% | sp_warmachine ✓, sp_charger ✓ |
| soft_predator | 50% | pr_apex_hunt ✓ |
| soft_military | 30% | **없음** (top10=T1~T3만) |
| soft_druid | **25%** | **없음** (top10=T1~T3만) |
| aggressive | 60% | — |
| adaptive | 30% | pr_transcend ✓, sp_arsenal ✓ |
| economy | 45% | pr_transcend ✓ |

## 핵심 발견

### 1. soft_druid: T4/T5 capstone 구매 실패
- dr_world, dr_wt_root, dr_wrath, dr_grace 모두 top10 밖 (95×dr_cradle, 93×dr_lifebeat로 T1 집중)
- 34.8 리롤/run — capstone 대기 리롤을 소진하지만 결국 도달 못함
- detected_paths 20/20 감지 정상 → path logic은 OK, 실제 구매 단계에서 실패
- **원인 후보**: scoring이 T4/T5를 충분히 우선하지 못함 or shop pool에 나타날 확률이 낮음

### 2. soft_military: 동일 패턴
- ml_command, ml_special_ops, ml_factory top10 밖
- ml_barracks(99) dominant, T2/T3 중간 tier는 있지만 capstone 없음

### 3. Neutral event cards 강세
- ne_earth_echo, ne_wild_pulse 모든 전략 top10 상위
- 약한 테마(druid/military)일수록 neutral 비중 ↑ → theme pick 잠식 의심
- 강한 테마(steampunk 149×sp_workshop) 에서는 theme 카드 비중 압도적

## 다음 액션 후보
1. **_score_card capstone 가중 확인** — shop_level 4/5에서 T4/T5 카드 점수가 충분히 높은지
2. **shop pool rotation** — T4/T5가 실제로 등장하는 빈도 체크 (pool exhaustion?)
3. **ne_* 스코어 과대 평가 여부** — 이벤트 emitter 점수가 테마 카드를 압도하는지
