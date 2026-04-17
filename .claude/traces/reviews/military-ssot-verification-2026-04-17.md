---
date: "2026-04-17"
protocol: multi-review
decision: "군대 카드 YAML이 SSOT로 기능하는가 → 설계 문서(docs/design/cards-military.md) 효과 섹션 삭제 가능?"
verdict: "PASS with concerns"
mean_score: 8.0
critics:
  - name: balance_engineer
    model: opus
    score: 9
    verdict: pass
  - name: implementation_correctness
    model: opus
    score: 8
    verdict: pass
  - name: system_consistency
    model: sonnet
    score: 7
    verdict: concern
refs:
  - .claude/traces/evolution/012-military-r4-r10-axis-split.md
  - .claude/traces/evolution/013-r-conditional-star-parity-validator.md
  - .claude/traces/evolution/014-command-revive-scope-yaml-parse.md
  - .claude/traces/evolution/015-silent-drop-removed-hard-fail.md
---

# Military Cards SSOT Verification Review — 2026-04-17

## 1. Scope

세 축 병렬 검증:
- (a) 설계 문서 의도 → YAML 완전 반영
- (b) YAML → 생성 코드(card_db.gd + military_system.gd + game_manager.gd) 정확 반영
- (c) YAML이 실질적 SSOT로 기능

## 2. Result Table

| Critic | Score | Verdict | Key finding (headline) |
|--------|-------|---------|------------------------|
| 1. 밸런스 엔지니어 (opus) | 9 | pass | 10장 전 카드의 ★/R 수치·target·fraction·mult·pct·count 모두 설계 문서와 일치 |
| 2. 구현 정확성 (opus) | 8 | pass | 모든 YAML action이 reachable handler로 dispatch. trace 014 revive refactor end-to-end 검증 |
| 3. 시스템 일관성 (sonnet) | 7 | concern | card_db 경로는 clean. description generator + nested None 처리에 edge gap |

Mean 8.0, veto 없음 → formal PASS. 단, Critic 3의 HIGH finding 1건은 **실제 런타임 영향 가능성**이 있어 합의형 concern.

## 3. Findings by Severity

### HIGH (Critic 3)

**H1. `ol1: null` 정보 손실 → ml_academy ★2/★3 enhance event emission drift 위험**
- 위치: [scripts/codegen_card_db.py:329](scripts/codegen_card_db.py:329) `_convert_nested_effects`
- 증상: YAML에 `enhance: {target: event_target, atk_pct: 0.02, ol1: null}`로 쓴 "이벤트 방출 억제" 의도가 None filter(`if v is None: continue`)에 의해 key 자체가 삭제됨. runtime theme_system handler는 `ol1` absent를 수신.
- 영향: 만약 handler의 default가 non-null이면 Layer1.ENHANCED 이벤트가 잘못 방출되어 chain 루프 생성 가능.
- 권고: theme_system handler의 default 동작 검증 + 필요 시 `_convert_nested_effects`에서 `None`은 명시적으로 `null`로 보존.

### MED (Critic 3)

**M1. card_desc_gen.py에 `spawn_unit`/`crit_buff`/`high_rank_mult` handler 부재 → ml_assault / ml_special_ops 툴팁이 `[TODO: spawn_unit]` 배포**
- 위치: [scripts/card_desc_gen.py:591](scripts/card_desc_gen.py:591), [godot/core/data/card_descs.gd:268-275](godot/core/data/card_descs.gd:268)
- 영향: card_db는 정확하나 UI 표시 불완전. 기능 영향 없음, UX 영향만.
- 권고: card_desc_gen에 해당 3 action의 한국어 설명 template 추가.

### LOW (모든 critic)

| ID | Finding | Critic | 위치 |
|----|---------|--------|------|
| L1 | ml_supply 설계 문서는 "R10 대체", YAML은 cumulative (+1+1=2). R10 도달 시 R4 병행이므로 의미 동일. | 1 | military.yaml:265-276, cards-military.md:165 |
| L2 | ml_tactical R10이 R4 HP/rank buff 누적에 의존. R4 rank_buff_hp가 활성 상태 가정. | 1 | military.yaml:329-363 |
| L3 | `_supply_post`의 `econ_eff.get("terazin", {})` — YAML에 해당 sub-block 없음, dead branch. | 2 | military_system.gd:1032,1040 |
| L4 | `_apply_crit_buff`에 hardcoded `mult: 2.0` fallback. 현재 YAML은 모든 entry에 mult 명시 → drift 없지만 미래 risk. | 2 | military_system.gd:564 |
| L5 | `ml_assault.spawn_unit`이 CONSCRIPT/UNIT_ADDED 이벤트 미방출 (design choice, 주석 명시). | 2 | military_system.gd:844-850 |
| L6 | `desc_counter_produce`가 `global_military_atk_pct`/`global_military_range_bonus` 키 미처리 → ml_factory 툴팁 "소비, "로 끝남. | 3 | card_desc_gen.py:456-465 |

## 4. Convergence check (trace 013 P5 3단계 유효성)

trace 015 이후 실제로 silent drop이 불가능한지 3명이 교차 확인:
- Critic 3: "codegen hard-fail이 non-theme-system base effects에서 unknown action을 즉시 ValueError로 중단. 확인."
- Critic 2: "YAML에 선언된 action 전부가 dispatchable handler를 가짐. dead action 없음."
- Critic 1: "YAML 수치가 설계 의도와 1:1 매핑. 수치 drift 0건."

P5 3단계 달성 검증 완료. 단, **description generator 계층**은 silent-dropping이 남아있음 (M1). 엄밀한 의미에서 "모든" 계층이 hard-fail은 아니다.

## 5. Verdict

**PASS with known gaps.**

- (a), (b), (c) 세 축 모두에서 YAML이 실질적 SSOT로 기능. 10장 모든 카드에 대해 설계 문서와 런타임 동작이 YAML로부터 재구성 가능.
- HIGH 1건 (H1: ol1 drop)은 runtime 영향 가능성이 있으므로 **설계 문서 삭제 전에 handler 동작 검증 또는 codegen 수정 권장**.
- MED 1건 (M1: desc generator placeholder)은 UX만 영향. 삭제 가능 판정에 관계없음.
- LOW 6건은 문서 정리 또는 drift risk 감시 수준.

## 6. Recommendation

### 설계 문서 삭제 가부

**조건부 가능**. 아래 3개 중 최소 H1 조치 후 삭제 권장.

### 조치 순서 (우선순위)

1. **H1 해결** (필수): ml_academy ★2/★3 enhance effect에서 `ol1: null`의 runtime 영향을 확인.
   - 빠른 조사: theme_system의 academy handler가 `ol1` absent 상태에서 이벤트를 방출하는지 GUT 테스트로 검증.
   - 결과가 "default 동작이 이미 null"이면 no-op, 문서화.
   - 결과가 "default가 non-null"이면 `_convert_nested_effects`를 수정하여 명시적 null 보존.
2. **M1 해결** (강력 권장): `card_desc_gen.py`에 `spawn_unit`, `crit_buff`, `high_rank_mult` description handler 추가. ml_assault/ml_special_ops 툴팁 복구.
3. **L1~L6 정리** (선택): YAML 주석 또는 evolution trace에 설계 의도 뉘앙스 고정. dead branch 제거.

### 장기 제안

- `ol1: null` 케이스는 **다른 테마**에서도 재발 가능. `_convert_nested_effects`의 None 필터를 전면 검토해 의도적 null 보존 규칙을 도입.
- description generator도 codegen hard-fail 대상에 포함시켜 "[TODO]" 배포를 구조적으로 차단.

## 7. User decision

critic 합의는 "삭제 가능 조건부 PASS". 최종 결정은 사용자. H1 선결 의사가 있으면 다음 세션 첫 작업으로 제안.
