---
date: "2026-04-27"
classification: "제약 미비"
escalated_to: "data/keywords.yaml + scripts/tests/test_keywords_glossary.py + codegen integration"
search_set_id: "SS-011"
resolved: true
---

# Failure: 신규 13장 카드 desc 핸들러 — codegen 패턴 일괄 위반

## Observation

사용자 피드백 (2026-04-27): 동맹군 desc가 "신병 추가"로 표시 — yaml로부터 generate되므로 이런 종류의 드리프트가 있어선 안 됨. 또한 독양식장 등 골드 표기 "유닛 수 × 0.2골드"도 동일 진단.

전수 점검 결과: **commit 0fd2d5e (2026-04-25) 신규 13장 yaml 등록 시 추가된 desc 핸들러 5개가 codegen 키워드 사전(line 1199 `event_name`, desc_conscript line 504 등)을 우회하고 자유 문자열을 하드코딩**.

## 신규 13장 카드 (commit 0fd2d5e + 후속 ne_clone_seed→ne_pawnbroker 교체)

```
dr_resonance, ml_alliance, ne_envoy, ne_hoarder, ne_legion,
ne_masquerade, ne_void_force, ne_fusion_end, ne_council, ne_nexus,
ne_pawnbroker (ne_clone_seed 대체), pr_parasitic_swarm, sp_global_workshop
```

## 패턴 위반 항목

### A. 이벤트 키워드 하드코딩 (5건)

신규 desc 핸들러가 enum/glossary lookup 없이 자유 한글 문자열을 직접 작성.

| 핸들러 (line) | 카드 | 출력 텍스트 | 기대 |
|--------------|------|------------|------|
| `desc_theme_count_conscript` (754) | ml_alliance | "신병 추가" | "징집" (CO 키워드) |
| `desc_mirror_l2` (714) | pr_parasitic_swarm | "테마 효과 발동 시" (vague) | 키워드 명시 (징집/훈련/제조/번식/부화/변태/개량/나무 성장) |
| `desc_mirror_l1` (797) | ne_nexus | "비-중립 대상" 하드코딩 | 의도는 inter-theme(타테마 간) 였음 — 사용자 확인 |
| `desc_mirror_spawn_to_tree` (777) | dr_resonance | "비-드루이드 대상" 하드코딩 | 동일 패턴 (필터 의미 확인 필요) |
| `desc_gear_diversity_enhance` (736) | sp_global_workshop | "비-스팀펑크" 하드코딩 | 동일 패턴 |

기존 `desc_conscript` (line 504)은 정상적으로 "징집" 키워드를 사용. 신규 핸들러 작성자가 이 패턴을 참조하지 않음.

### B. [반응] 출처 명시 누락

OE_PREFIX (line 51-73)는 `require_other: true`만 "다른 카드의 ..."로 prefix 변환. 기본형은 "[반응] 부화 시:" 같이 출처 모호. 사용자 피드백: "이 카드에 부화한 건지 어디든 부화한 건지 불분명".

영향 카드: 신구 모두 — `pr_molt`, `ne_hoarder`, `ne_nexus`, `pr_parasitic_swarm`, `dr_resonance`, `pr_apex_hunt`, `pr_transcend` 등 OE 카드 다수.

### C. 골드 포맷 정규화 부재

`desc_economy` (line 954-970): `f"{unit_text} × {per}골드"` — 분수 비율을 그대로 출력.

| 카드 | 현재 | 사용자 선호 |
|------|------|-------------|
| pr_farm | "유닛 수 × 0.2골드" | "5기당 1골드" |
| ml_supply | "군대 카드 수 × 0.5골드" | "2기당 1골드" |
| ml_supply ★2/★3 | "군대 카드 수 × 1.0골드" | "1기당 1골드" |

영향: 신규가 아닌 기존 카드에도 적용되는 핸들러 — 신규 13장은 이 핸들러를 쓰지 않지만 같은 codegen 정규화 누락 범주.

### D. 키메라 울부짖음 — 별도 패턴 (참고)

`ne_chimera_cry` (구 카드, 신규 13장 외): "ATK+HP +8% 영구 강화" — 두 스탯을 `+` 기호로 합쳐 표기. 사용자: "ATK/HP" 분리 표기 선호. 별도 핸들러(`desc_enhance`) 포맷 결정.

## Root Cause

1. **자유 문자열 핸들러**: 각 desc 핸들러는 임의 Python 함수가 한글 문자열을 반환 — 키워드 사전(line 1199 `event_name`)이 일부 핸들러에만 사용되고 신규 핸들러는 미참조.
2. **사전 참조 강제 부재**: 액션 카테고리(이벤트 방출 키워드: CO/TR/MF/HA/MT/UP/BR/TG)와 desc 텍스트 일관성을 검증하는 lint/codegen guard 없음.
3. **포맷 정규화 함수 부재**: `gold_per: 0.2` 같은 분수 입력을 정수 비율 텍스트로 변환하는 단계가 없음 — 핸들러가 raw 값을 직접 표기.
4. **[반응] 기본형 ambiguity 미인지**: 설계 의도("require_other 기본 false = 어디서든")가 desc 텍스트에 명시되지 않음.
5. **신규 핸들러 작성 시 패턴 가이드 부재**: 카드 설계 스킬·RULES.md는 YAML 작성 규칙만 명시, desc 핸들러 작성 컨벤션 없음.

## Fix (planned, 본 작업)

### 즉시 수정 (이번 PR)
- [ ] desc_theme_count_conscript: "신병 추가" → "징집" (CO 키워드 lookup)
- [ ] desc_mirror_l2: "테마 효과 발동 시" → 모든 키워드 명시
- [ ] desc_mirror_l1: 필터 텍스트 inter-theme(b 의미)로 정정 + 코드 로직 cross_theme 변경
- [ ] desc_economy: 분수 → 정수 비율 정규화 ("5기당 1골드")
- [ ] OE_PREFIX 기본형: "[반응] 어디서든 ... 시" prefix 추가
- [ ] desc_enhance ATK/HP 분리 표기

### 구조적 개선 (P5 사다리 3단계 제안 — 별도 작업)
- [ ] `data/keywords.yaml` 단일 진실 소스 (이벤트 키워드 enum → 한글 텍스트)
- [ ] desc 핸들러는 사전 lookup 강제 (하드코딩 시 codegen hard-fail)
- [ ] 골드/비율 정규화 helper (`normalize_per_unit_ratio`)

## Prevention

P5 구조적 해결을 채택하면 동일 범주 재발 차단 가능. 구조 강제가 없으면 신규 핸들러 작성 시 동일 드리프트 반복 위험.
