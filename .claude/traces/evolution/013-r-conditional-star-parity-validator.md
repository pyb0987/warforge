---
iteration: 13
date: "2026-04-17"
type: additive
verdict: pending
files_changed:
  - scripts/codegen_card_db.py (+validate_r_conditional_star_parity, +_diff_r_conditional, main() early-fail)
  - scripts/tests/test_r_conditional_validator.py (NEW — 12 unit tests)
  - data/cards/military.yaml (ml_assault/ml_outpost/ml_special_ops — star_scalable_actions 선언)
  - CLAUDE.md (Hooks 섹션에 validator 등록)
refs:
  - "commit 77e0a78 — 훈련소 ★2/★3 target drift + 보급부대 ★2/★3 amount drift fix"
  - "commit 18e7cb2 — 군수공장 ★1~★3 upgrade_shop_bonus amount drift fix"
  - "commit d0ffa65 — 훈련소/전진기지 delta 표현 수정 (최초 drift 발견)"
  - handoff.md (옵션 B: YAML delta/cumulative validator, multi-review iter 5 합의)
---

## Iteration 13: r_conditional ★ parity validator (P5 구조적 해결)

### Problem

같은 카드의 `r_conditional` 블록이 ★1/★2/★3에서 drift한 bug가 3회 반복되었다 (evidence threshold 3건 도달, P5 구조 흡수 대상):

1. **훈련소 ★2/★3** (commit 77e0a78): R4/R10 `train.target`이 ★1과 달랐다. ★1은 delta 표현 (`left_adj`, `far_military`)이었는데 ★2/★3이 cumulative-looking (`both_adj`, `all_military`)로 기재되어 `right_adj` 중복 훈련이 발생.
2. **보급부대 ★2/★3** (commit 77e0a78): R10 `grant_terazin.amount`가 ★1(1)과 달리 2로 적혀, R4(1) + R10(2) = 총 3 테라진 지급 (의도는 2).
3. **군수공장 ★1~★3** (commit 18e7cb2): R10 `upgrade_shop_bonus.slot_delta`/`terazin_discount`가 2로 적혀, R4(1) + R10(2) = 총 +3/−3 (의도는 +2/−2).

공통 원인: ★1 슬롯에 먼저 delta 표현으로 채운 뒤 ★2/★3를 복사하면서, R10에서 "total이 얼마여야 하지?" 라는 의문이 들면 cumulative 값을 쓰거나 target을 총괄형으로 바꾸는 실수가 반복. multi-review iter 5에서도 동일 패턴을 지적하며 structural validator 권고가 있었다.

### Change (additive — 검증기를 추가, 기존 codegen 로직은 미변경)

1. **scripts/codegen_card_db.py — `validate_r_conditional_star_parity()`**
   - 입력: `load_all_cards()` 결과 전체.
   - 불변식: 한 카드의 `r_conditional`이 ★1/★2/★3에서 구조적으로 동일해야 한다 (rank_gte, effects 리스트 길이, action 이름, 모든 params까지 deep equal).
   - 예외: 카드 top-level `star_scalable_actions: [action, ...]`로 선언된 action은 params가 ★별로 달라도 허용. combat buff의 의도된 스케일링을 표현.
   - 실패 시 `sys.exit(2)` — `--check` 모드와 generate 모드 양쪽에서 동일 fail-fast.

2. **`_diff_r_conditional()` helper** — 사람이 읽을 수 있는 diff 메시지 생성 (어떤 milestone의 어떤 action에서 어떤 필드가 다른지). 카드 ID + diff를 main()에서 묶어 출력.

3. **scripts/tests/test_r_conditional_validator.py (NEW)**
   - 12 테스트. 3개 과거 bug class를 합성 YAML fixture로 재현 (target drift, amount drift, nested-param drift). 추가로 rank_gte 차이/effects 카운트 차이/action 이름 차이/allowlist 허용/allowlist 비매칭/single-star skip/no r_conditional skip을 커버.
   - 실제 `military.yaml` 로드 후 clean 상태를 확인하는 test_clean_military_yaml_passes를 baseline 회귀 시험으로 포함.

4. **data/cards/military.yaml — opt-in 선언 3건**
   - `ml_assault.star_scalable_actions: [swarm_buff]` — ★↑ 시 `unit_thresh` 15→12→10 (임계값 완화).
   - `ml_outpost.star_scalable_actions: [conscript]` — ★↑ 시 `enhanced` none→partial→all (강화 수준 상승).
   - `ml_special_ops.star_scalable_actions: [crit_buff]` — ★↑ 시 `mult` 2.0→3.0→6.0 (크리 배율 상승).
   - 세 경우 모두 action의 핵심 기능이 카드의 ★ 정체성과 결부된 combat buff. 기존 의도이며 주석으로 명시.

5. **CLAUDE.md — Hooks 섹션 등록**
   - "r_conditional ★ parity validator (codegen 내장, 차단형 exit 2)" 항목 추가 + 회귀 테스트 실행 명령 명시.

### 사다리 위치 (P5)

| 단계 | 메커니즘 | 본 이터레이션 |
|------|---------|--------------|
| 0. 규칙 | CLAUDE.md 제약 | 이전: "★별 복사 주의" (자발적 준수) — 누수 → 3회 drift |
| 1. 경고 | PostToolUse hook | 기존 `codegen --check` drift 경고는 구조적 drift를 탐지하지 못함 |
| 2. 차단 | **PostToolUse + codegen exit 2** | **이번 단계** — YAML 저장 시점에 exit 2로 경고 노출 (블로킹 경로는 PreToolUse가 아닌 generate 실패) |
| 3. 구조적 불가능 | Single Source + Codegen + Protect | 이미 card_db.gd에는 적용됨. r_conditional 자체는 human-edited 필요 → 완전 제거는 불가, 2단계까지가 현실적 최대치 |

완전한 "위반이 불가능한 상태"는 아니지만 (allowlist를 통한 opt-in이 자발적), 3건의 과거 bug class 모두가 exit 2로 탐지되는 것을 unit test로 확인.

### Why additive

기존 codegen flow (load → generate → write/check)에 early-fail 단계를 prepend만 했고, 기존 함수/생성 로직은 전혀 수정하지 않음. validator가 통과하면 downstream은 이전과 동일하게 동작. allowlist는 YAML의 신규 optional field이므로 미지정 카드는 영향 없음.

### Validation

- `python3 scripts/codegen_card_db.py --check` → `✅ card_db.gd + card_descs.gd match YAML (55 cards)`.
- `python3 -m unittest scripts.tests.test_r_conditional_validator` → 12/12 ok.
- 합성 regression: 훈련소 / 보급부대 / 군수공장 과거 bug 세 가지를 YAML에 주입하면 모두 exit 2 + 구체적 diff 메시지로 포착.
- GUT 전체 테스트: 881/886 통과 (5 failing은 pre-existing, 이번 변경과 무관 — 유닛 카운트 stale 2건 + ATK buff 3건).
- card_db.gd 재생성 불필요 (star_scalable_actions는 YAML-only metadata).

### 남은 위험

- `star_scalable_actions` 허용 여부가 카드 작성자의 판단에 의존 → 과잉 opt-in 시 drift 탐지가 무력화. 향후 allowlist에 등재된 action에 대해 numeric-only 변화만 허용하고 target/enum 변화는 여전히 차단하는 한층 더 세밀한 룰 고려 가능 (현재는 allowlist로 opt-in하면 모든 param drift 허용).
- non-military 테마에 `r_conditional`이 도입되면 해당 테마도 자동으로 검증 대상에 포함됨. 추가 opt-in이 필요한 경우 위와 같은 패턴으로 선언하면 됨.
