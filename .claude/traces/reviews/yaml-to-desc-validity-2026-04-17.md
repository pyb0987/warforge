---
date: "2026-04-17"
protocol: multi-review
decision: "YAML → card_descs.gd 변환이 설계 문서 대체용 SSOT로서 충분한가?"
verdict: "MIXED / CONCERN"
mean_score: 7.0
critics:
  - name: translation_accuracy
    model: opus
    score: 8
    verdict: concern
  - name: player_ux
    model: opus
    score: 5
    verdict: concern
  - name: rendering_consistency
    model: sonnet
    score: 8
    verdict: concern
refs:
  - .claude/traces/evolution/015-silent-drop-removed-hard-fail.md
  - .claude/traces/reviews/military-ssot-verification-2026-04-17.md
  - "commit 2934d97 — r_conditional description 포함 + buff.as_bonus"
  - "commit cd306c2 — require_other OE prefix 확장"
---

# YAML → Description Validity Review — 2026-04-17

## 1. Scope

3 disjoint critic으로 YAML → `card_descs.gd` 변환 품질을 검증:
- (a) 번역 정확성: YAML 수치/조건/타이밍이 description에 정확히 반영
- (b) 플레이어 UX: description만으로 카드 의도 이해 가능
- (c) 렌더링 일관성: 동일 패턴의 포맷/용어/구두점 통일

설계 문서(`docs/design/cards-military.md` 효과 섹션)가 삭제된 상태 → description이 플레이어의 유일한 카드 이해 경로.

## 2. Result Table

| Critic | Score | Verdict | Key finding (headline) |
|--------|-------|---------|------------------------|
| 1. 번역 정확성 (opus) | 8 | concern | 수치 99%+ 정확, but dr_world target 오역 + ml_outpost partial 모호 |
| 2. **플레이어 UX (opus)** | **5** | **concern** | 군대 카드 base+R4+R10 밀집 → 첫 플레이어 파싱 실패. "비(강화)", "2기 카운트" 불명 |
| 3. 렌더링 일관성 (sonnet) | 8 | concern | `(전투)` vs `(이번 전투)` 혼용, dr_wrath "이 카드" 누락 |

**Mean 7.0, 3명 모두 concern, veto 없음 → MIXED**. Critic 2의 5점이 신호.

## 3. Findings (Merged by Issue)

### HIGH

| ID | 이슈 | Critics | 위치 |
|----|------|---------|------|
| H1 | `dr_world ★1~3` multiply_stats: YAML `target: self`인데 desc "전체 드루이드 ATK×X" | 1 (MED×3), 2 (HIGH) | [card_desc_gen.py](scripts/card_desc_gen.py) desc_multiply_stats, [druid.yaml:367-415](data/cards/druid.yaml:367) |
| H2 | `ml_outpost ★2` `enhanced: partial`: count:1일 때 all과 구별 불가, 괄호 관계 모호 | 1 (HIGH), 2 (HIGH) | [military.yaml:168-188](data/cards/military.yaml:168) |
| H3 | 군대 카드 base+[R4]+[R10] 한 문장 과밀 → 플레이어 스캔 불가 | 2 (HIGH) | card_descs.gd 군대 10장 전반 |
| H4 | `ml_assault` "15기+ → MS +1. (강화) 2기 카운트" — 무엇의 15기인지, 왜 2기 카운트인지 해독 불가 | 2 (HIGH) | desc_swarm_buff handler |
| H5 | `ml_barracks ★1` [R4]/[R10] 의미가 "조건 트리거"인지 "추가 효과"인지 모호 | 2 (HIGH) | R_CONDITIONAL_PREFIX 형태 |

### MED

| ID | 이슈 | Critics | 위치 |
|----|------|---------|------|
| M1 | `ml_supply` R10 desc는 delta만 (테라진 +1, 골드 +1) — YAML 의도 "누적 총 +2 테라진" | 1 (MED) | military.yaml:268-276 |
| M2 | `sp_charger` "카운터 N+" — 카운터 축적 규칙이 어디에도 없음 | 2 (MED) | steampunk.yaml:220-240 |
| M3 | `ml_supply` "패배 전액" 한국어 부자연스러움 (패배 시 전액 잃는 걸로 오해 가능) | 2 (MED) | desc_economy handler |
| M4 | `dr_world` ★1~3 3축 스케일링이 쉼표로만 나열, 괄호 위치로만 구분 | 2 (HIGH) | desc_multiply_stats |
| M5 | `ne_awakening ★3` "1회:" trigger + "이후 매 라운드" 구분이 마침표 하나뿐 | 2 (MED) | desc_post_threshold |
| M6 | `%(전투)` vs `%(이번 전투)` 혼용 (persistent vs combat-buff) | 3 (MED) | desc_buff vs desc_persistent |
| M7 | `ml_academy` 세 개의 라운드 제한 공존 (R4 라운드당 1회, R10 라운드당 1회, 전체 최대 3/R) | 2 (MED) | 복합 제한 파싱 어려움 |

### LOW

| ID | 이슈 | Critics | 위치 |
|----|------|---------|------|
| L1 | `sp_charger` rare_counter "3택1" 수식어가 YAML에 없음 (UX 해석 첨가) | 1 (LOW) | desc_rare_counter |
| L2 | `dr_wrath` unit_cap 조건문에 "이 카드" prefix 없음 ("≤5기 ATK..." only) | 3 (LOW) | desc_tree_temp_buff vs CONDITION_TEXT |
| L3 | spawn_unit(named) "N기 추가" vs spawn(generic) "N기 유닛/제조" 동사 차이 | 3 (LOW) | 의미 구분 OK, 문서화 권장 |
| L4 | `dr_origin` "-4%p" (퍼센트 포인트) 단위가 UI에서 드뭄 | 2 (MED) | desc_tree_add handler |
| L5 | `dr_grace` "🌳÷3" ÷ 기호 + 소수 처리 불명 | 2 (LOW) | desc_economy 드루이드 경로 |

## 4. Synthesis — 근본 원인 (3 계층)

### 계층 1: Handler 정책 drift (기술 부채)
- 각 handler가 독립적으로 포맷 결정 → suffix, 조건문 prefix, target 해석이 대형 코드 베이스에 흩어져 있음
- 증거: `(전투)`/`(이번 전투)`, `desc_tree_temp_buff`가 `CONDITION_TEXT`를 우회, `desc_multiply_stats`가 `target: self`를 "전체 드루이드"로 하드코딩
- 수정 난이도: **낮음** (handler별 작은 fix)

### 계층 2: 정보 밀도 & tooltip layout (UX)
- 군대 카드는 base + [R4] + [R10] = 3 섹션을 한 줄 prose에 압축
- "(강화)", "비(강화)", "카운터", "%p" 같은 도메인 용어가 처음 본 플레이어에게 낯섦
- 축약된 문장("15기+ → MS +1") 이 전제/단위/주어를 생략
- 수정 난이도: **중** (일부는 handler, 일부는 tooltip 렌더링 레이아웃 = Godot UI 변경)

### 계층 3: YAML schema 불충분 (근본 구조)
- `enhanced: partial` 의 수량 규칙이 schema에 없음 → handler 해석이 임의적
- `ml_supply` cumulative 의도가 YAML 주석에만 있고 machine-readable 선언이 없음
- 수정 난이도: **높음** (YAML schema + codegen + 마이그레이션)

## 5. Verdict

**MIXED → 설계 문서 대체 SSOT로서는 부족.**

- 기술적 번역은 8/10 (거의 정확)
- 렌더링 일관성도 8/10
- **플레이어가 읽을 수 있는가는 5/10** → 설계 문서 삭제 전제였던 "YAML만으로 플레이어가 카드를 이해할 수 있다"를 충족하지 못함

다만 **게임 플레이가 망가지는 정도가 아니고, 수정 경로가 명확**하므로 veto 아님.

## 6. Recommendations (우선순위)

### P0 — Handler drift 수정 (즉시, 1 commit)
1. `desc_multiply_stats`: `target: self` 경로 추가, "전체 드루이드" 하드코딩 제거 → dr_world ★1/★2/★3 3건 동시 수정
2. `desc_tree_temp_buff`: cap 조건문을 `CONDITION_TEXT["unit_count_lte"]` 경로로 라우팅 → "이 카드" prefix 추가
3. `(전투)` vs `(이번 전투)` suffix 통일 (권장: 모두 "이번 전투" 또는 명시적 구분 문서화)
4. `desc_economy` "패배 전액" → "승패 무관 전액"
5. `ml_outpost` YAML의 `enhanced: partial` + `count: 1` 케이스 명시: "(전원 강화)"로 렌더, 또는 partial/all 의미 재정의

### P1 — YAML schema 명확화 (별도 스프린트)
6. `enhanced` 필드 spec 문서화: `none`/`partial`/`all` 각각의 정량 규칙을 `data/cards/RULES.md`에 추가
7. counter 전제 (제조 1회 = 카운터 +1)를 steampunk theme 카드의 description 앞부분에 자동 삽입
8. cumulative vs delta 표시 정책을 r_conditional 에 flag로 추가 (예: `display: cumulative`)

### P2 — UX layout (별도 설계)
9. `[R4]` `[R10]` 블록을 card_descs.gd 포맷에서 줄바꿈(`\n`)으로 물리 분리 — 현재는 공백이라 한 줄 렌더
10. 용어집 tooltip: "(강화)", "비(강화)", "카운터" 등 호버 시 정의 표시 (이미 keyword_glossary.gd 존재)
11. `ml_assault` 축약 절 재작성: "이 카드 15기 이상 시 해당 카드 유닛 MS +1. (강화) 유닛은 2기로 집계"

### P3 — 재검증
수정 후 다시 **Critic 2 (플레이어 UX)** 만 단독 실행해 7+ 점 도달 여부 확인. Critic 1/3는 pass 상태이므로 재실행 불필요.

## 7. User decision

최종 결정은 사용자:
- (A) P0만 해결하고 "설계 문서 삭제 유지" — 기술적 정확성과 일관성은 확보
- (B) P0+P1 해결 후 Critic 2 재검증 — "플레이어 UX" 통과 목표
- (C) P0+P1+P2 — UI 변경까지 포함한 완전 SSOT
- (D) 설계 문서 삭제 되돌림 (git revert 111150d) — 실질적 보류
