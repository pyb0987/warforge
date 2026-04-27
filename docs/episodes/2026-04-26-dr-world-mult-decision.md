# dr_world unique_atk_mult 누적 정책 결정

- **Date**: 2026-04-26
- **Decision**: 현행 정책 유지 (multiplicative within-card, max merge). 플레이테스트로 검증.
- **Context**: iter 22 완료 후속. iter 21에서 도입한 "unique layer + max merge" 정책의 단일 카드 내 multiplicative 누적이 OP인지 4안 비교.

## 분석 데이터 (scripts/analyze_dr_world_mult.py)

| 시나리오 | 현행 (multiply) | (i) overwrite | (ii) cap@3 | (ii) cap@5 |
|---|---|---|---|---|
| best (★3, 10R, +8🌳/R) | **144.75×** | 2.00× | 3.00× | 5.00× |
| median (★3, 8R, +5🌳/R) | **19.08×** | 1.60× | 3.00× | 5.00× |
| worst (★3, 5R, +3🌳/R) | 4.31× | 1.40× | 3.00× | 4.31× |
| ★2 mid | 4.27× | 1.25× | 3.00× | 4.27× |
| ★1 long | 4.85× | 1.20× | 3.00× | 4.85× |

iter 21의 max merge 정책으로 cascade 폭발(★3 합성 시 도너 mult 누적)은 차단됨. 남은 누적은 단일 카드 내 RS 트리거 multiplicative.

## 옵션 (4안)

1. **현행** — multiply within-card + max merge. T5 ★3 dr_world late-game 100×+ 가능.
2. **(i) 매 RS 덮어쓰기** — `set` 대신 `multiply`. round-by-round 결정값 유지. 성장 누적 사라짐.
3. **(ii) per-source cap (3.0~5.0)** — 누적은 유지, 천장만 설정. 성장 fantasy + 균형.
4. **(iii) ★3 evolve 댐핑** — ★3 진입 시 ×0.8. 진행형 누적은 막지 못함 — 폐기 권장.

## 결정 — 옵션 D (현행 유지 + 플레이테스트 검증)

**근거 (사용자 결정)**:
- 144×는 컨텐츠로 의도된 "OP 구간"이며 플레이테스트로 검증할 사안.
- T4/T5 ★3 = "게임 판도를 바꿀 정도로 강력해야 함" 원칙 (project_high_tier_power 메모리)과 정합.
- 코드 변경 없이 실측 데이터로 균형 판단을 우선.

**플레이테스트 관찰 포인트**:
- ★3 dr_world 보유 게임의 R10+ 승률 (도달 빈도 + 도달 시 압도력)
- 트리 누적 속도 (forest_depth growth rate by druid build)
- 다른 T5 카드와의 상대 강도 (T5 ne_council, T5 ml_command 등)

**조정 발동 조건**:
- 플레이테스트에서 dr_world ★3 빌드가 다른 T5 빌드 대비 명백히 우세 (Win rate +20%p 이상) → cap@5.0 또는 atk_per_tree 감소 검토
- 반대로 도달 빈도 너무 낮음 (★3 도달 게임 < 10%) → 임계값 / 트리 cost 완화 검토
- 균형 (도달률 정상 + 빌드 간 균형) → 현행 유지

## Out-of-scope

- 다른 unique_*_mult 사용 카드 (현재는 dr_world만, 추후 추가 시 동일 분석 필요).
- iter 22 spawn_card funnel과 직교 (fresh_ref 정책은 unit count만 영향).

## 참조

- iter 21 trace: `traces/evolution/021-druid-thresholds-and-unique-mult.md`
- iter 22 trace: `traces/evolution/022-merge-fresh-policy-and-spawn-funnel.md`
- 분석 스크립트: `scripts/analyze_dr_world_mult.py` (재현 가능)
- 메모리: `feedback_high_tier_power.md` (T4/T5 ★3 = 게임 판도)
