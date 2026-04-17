---
date: "2026-04-17"
protocol: multi-review (iteration 2, Critic 2 단독 재검)
decision: "P0/P1/P2 개선 후 YAML → description이 플레이어 UX 기준을 충족하는가?"
verdict: "PASS with known gaps"
mean_score_update: 7.67
prev_iteration:
  ref: .claude/traces/reviews/yaml-to-desc-validity-2026-04-17.md
  mean_score: 7.0
  verdict: MIXED/CONCERN
refs:
  - "commit 8d46fae — ml_academy R10 replaces R4"
  - "commit 94ae9e4 — P1-1 enhanced_count migration"
  - "commit 68d61f1 — P1-2 counter prefix"
  - "commit 7621549 — P1-3 [랭크 N 이상] + glossary"
  - "commit 2ee12a6 — P2-1 line break"
  - "commit e7ef2c0 — P2-3 swarm_buff rewrite"
---

# YAML → Description Validity — Iteration 2 (Critic 2 재검)

## 1. 개선 요약 및 점수 변화

| Critic | 이전 (2026-04-17 iter 1) | 현재 (iter 2) | 변화 |
|--------|-------------------------|---------------|------|
| 1. 번역 정확성 (opus) | 8 (concern) | 8 (유지, P0로 커버) | — |
| 2. **플레이어 UX** (opus) | **5 (concern)** | **7 (concern)** | **+2** |
| 3. 렌더링 일관성 (sonnet) | 8 (concern) | 8 (유지, P0로 커버) | — |

**Mean 7.0 → 7.67**. 모든 critic ≥ 7 → **PASS** (residual gaps 있음).

## 2. 이전 findings 해결 상태

| ID | 이슈 | 결과 | 커밋 |
|----|------|------|------|
| H1 | dr_world multiply_stats target 오역 | ~~handler 정정~~ (이전 P0) | 670a221 |
| H2 | ml_outpost enhanced:partial 모호 | **enhanced_count 수량 필드화** | 94ae9e4 |
| H3 | 군대 base+R4+R10 밀집 | **\n 물리 분리** | 2ee12a6 |
| H4 | ml_assault swarm_buff 축약 해독 불가 | **주어/단위 명시** | e7ef2c0 |
| H5 | [R4]/[R10] 의미 불명 | **`[랭크 N 이상]` + glossary 누적 설명** | 7621549 |
| M1 | ml_supply cumulative vs delta | delta 유지 (설계 명확) | — |
| M2 | sp_charger 카운터 축적 규칙 부재 | **counter_prefix 자동 삽입** | 68d61f1 |
| M3 | ml_supply "패배 전액" 오독 위험 | **"승패 무관 전액"** | 670a221 |
| M6 | (전투) vs (이번 전투) 혼용 | **통일** | 670a221 |
| M7 | ml_academy 복합 쿨다운 | **R10 → R4 대체 bug fix + 순회 순서 변경 + max 기반 theme_state** | 8d46fae |

## 3. 잔존 concerns (iter 2 신규/미해결)

| ID | 카드 | severity | 이슈 | 권고 |
|----|------|---------|------|------|
| R1 | dr_world ★1~3 | HIGH | 3축 (ATK/HP/AS) × 서로 다른 `깊이 N당` 기준이 한 줄에 혼재 | multiply_stats desc에 `\n` 3줄 분리 + "숲의 깊이" glossary |
| R2 | 군대 10장 공통 | MED | `이 카드의 비(강화) 유닛 50% → (강화)` 가 30 entries에 반복 | 공통 규칙 키워드화 또는 축약 규칙 도입 검토 |
| R3 | ml_academy ★2 | MED | 각 `(라운드당 1회)` + 전체 `(최대 2/R)` 상호작용 불명확 (resolved의 "partial") | 통합 쿨다운 규칙 문서화 또는 UI 카운터 표시 |
| R4 | dr_deep ★1 | MED | `≤3기 → 🌳×1.2%`가 "0.8% 대체"인지 "0.8%+1.2% 중첩"인지 모호 | 대체 관계 명시 |
| R5 | ne_awakening ★1 | LOW | `필드 위 모든 카드`가 3회 반복되어 리듬 무거움 | 효과 병합 또는 줄바꿈 |

## 4. Verdict

**PASS with known gaps**: Mean 7.67, 모든 critic ≥ 7, veto 없음.

- **설계 문서(`docs/design/cards-military.md` 효과 섹션) 삭제 전제 충족됨.**
- 잔존 HIGH 1건 (`dr_world`)은 드루이드 테마이고 군대 SSOT와 무관. 별도 후속 작업 가능.
- MED/LOW 4건은 추가 P2 iteration으로 개선 여지 있음 (필수 아님).

## 5. 후속 제안

다음 세션 작업 후보:
1. **dr_world multiply_stats desc 3축 분리** (HIGH, 1 commit)
2. **공통 R4/R10 prefix 축약 규칙 도입** (MED) — 군대 전반 가독성
3. **ml_academy 쿨다운 통합 서술** (MED)
4. **dr_deep 조건 대체 명시** (MED)

필수는 아니지만 UX 완성도 차원에서 가능한 개선.
