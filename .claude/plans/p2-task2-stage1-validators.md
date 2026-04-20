# Task 2 — Stage 1 validators를 v2 codegen에 재적용

**선행**: p2-task1-main-merge.md 완료 (main이 v2 기반)
**상태**: 대기
**난이도**: 중 (validator 3개 + _find_eff 4개 파일 패치)
**작성일**: 2026-04-20

## 배경

Phase 2 C3+C4에서 만든 기술부채 backlog #3, #4, #5, #7을 사용자가 main에 Stage 1 (commit `b12e6f4`)로 한 번 해결했는데, 그 구현은 **v1 schema 기반**. Task 1에서 main이 v2로 전환되면서 Stage 1 커밋은 revert됨. 이 Task가 **같은 아이디어를 v2 코드에 맞게 재구현**한다.

v2에서 d18d1ce가 이미 `validate_impl_theme_system` (≈ Stage 1의 `validate_impl_declared`)를 추가했으므로, 실제 남은 차이만 메운다.

## v2에 이미 있는 것 (d18d1ce — 확인용)

- `validate_impl_theme_system` — 모든 theme (steampunk/druid/military/predator) 카드가 CARD_DB_ACTIONS 외 action 사용 시 `impl: theme_system` 강제. Stage 1의 `validate_impl_declared`보다 범위 넓음(steampunk 포함), 검사 로직 다름(action 기반 vs theme 기반).
- `validate_multiblock_scalar_actions` — Stage 1에 없던 항목. v2-only.

## Stage 1에서 v2에 아직 없는 것 (이 Task가 추가)

### A) `validate_is_threshold_with_theme_system`
- **무엇**: `impl: theme_system` 카드가 `is_threshold: true` 를 쓰면 hard-fail.
- **왜**: `chain_engine.gd`가 `card.threshold_fired` 플립을 theme_system dispatch 전에 수행 → theme_system 핸들러는 threshold 상태 모름. 조합 사용 시 매 RS에서 첫 tick 인 척 재진입.
- **v2 위치**: `scripts/codegen_card_db.py` 의 validator 섹션.

### B) `validate_no_retrigger`
- **무엇**: YAML에 `retrigger` action 등장 시 hard-fail. Effects / conditional / r_conditional 모두 재귀 검사.
- **왜**: v2 `chain_engine._execute_actions`의 retrigger 구현이 `_find_block(target, ROUND_START).get("actions", [])`를 읽는데, theme_system 카드는 actions 비어있음 → silent no-op. 또한 RS 하드코드.
- **현재 사용 카드**: 0건. 예방적 차단.

### C) `_find_eff` push_error 강화 (4개 theme_system 파일)
- **무엇**: `druid_system.gd`, `military_system.gd`, `predator_system.gd`, `steampunk_system.gd`의 `_find_eff(effs, action, target)` 가 중복 매칭 시 `push_error` 로 경고. 첫 번째만 반환하므로 나머지 silent shadow.
- **왜**: 작성자가 의도적으로 여러 매칭을 쓰려면 `for eff in effs` 명시적 루프를 써야 한다는 계약을 **runtime에 강제**. 구조상 #5(_find_block first-match)와 유사 문제.
- **합법적 iteration 예외**: druid_system의 spore_cloud (여러 debuff_store 의도적 순회)는 이미 explicit loop 사용 중.

### D) `_c()` 헬퍼 flat-hoist 주석 보강
- v2에서는 내 d18d1ce가 이미 flat hoist 의미를 주석화했지만, Stage 1이 추가한 "IMPLICIT CONTRACT" 문장 — "**multi-block per star는 현 스키마에서 지원 안 함**" — 은 v2의 실제 구현과 충돌 (sp_warmachine이 multi-block).
- **v2 맥락 재해석**: v2는 multi-block을 허용하되 "첫 block의 flat hoist"를 backward-compat 채널로 명시한다. 주석은 **이 규약을 분명히** 만 하면 됨. Stage 1의 "단일 block per star" 문장은 버리고, v2 현실을 반영한 문장으로.

## 작업 범위 (파일)

### scripts/codegen_card_db.py
1. `validate_is_threshold_with_theme_system` 함수 추가 (~30줄)
2. `validate_no_retrigger` 함수 추가 (재귀 walk ~40줄)
3. `run_validators` 에서 2개 새 validator 호출 추가
4. `_c()` 헬퍼 주석(HELPER_FUNCTIONS 상수) 보강 — multi-block 규약 명시

### godot/core/{druid,military,predator,steampunk}_system.gd
각 파일의 `_find_eff` 를 다음 시그니처로 교체:
```gdscript
func _find_eff(effs: Array, action: String, target: String = "") -> Dictionary:
    var first := {}
    var matches := 0
    for e in effs:
        if e.get("action") == action:
            if target == "" or e.get("target", "") == target:
                matches += 1
                if matches == 1:
                    first = e
    if matches > 1:
        push_error("_find_eff shadowed duplicates: action=%s target=%s matches=%d — use explicit loop" % [action, target, matches])
    return first
```

(Stage 1의 b12e6f4 commit에서 정확히 이 코드가 4 파일에 복사됨. 재사용 가능.)

## 작업 단계

1. `b12e6f4` 의 diff 검토 — `git show b12e6f4 -- scripts/codegen_card_db.py godot/core/*.gd`
2. `validate_is_threshold_with_theme_system` — v1 코드를 v2 `load_cards()` 결과 dict에 맞게 재작성
3. `validate_no_retrigger` — 재귀 walk를 v2 block 구조 (effects가 block 리스트)에 맞게 재작성. 각 block의 actions + conditional/r_conditional/post_threshold 재귀.
4. `run_validators` 호출 추가
5. 4개 theme_system의 `_find_eff` 교체 (Bash `sed` 로 동일 교체 가능)
6. codegen 실행 → validator 통과 확인
7. GUT 실행 → 907/907 유지

## 검증 기준 (Sprint Contract Done)

- [ ] `validate_is_threshold_with_theme_system` 호출 후 현 55장 YAML 에 violation 0
- [ ] `validate_no_retrigger` 호출 후 violation 0 (retrigger 사용 카드 없음)
- [ ] `_find_eff` push_error 가 4개 theme_system 파일 모두 동일 형태
- [ ] `python3 scripts/codegen_card_db.py --check` exit 0
- [ ] GUT 907/907 pass
- [ ] `docs/design/backlog.md` 에서 항목 #3, #5, #7 상태 업데이트 ("해결" 표기)

## 참고 자료

- `b12e6f4` commit diff 전체
- 원문 docstring (이 handoff의 "A/B/C/D" 섹션)
- v2 구조: `data/cards/steampunk.yaml` sp_warmachine (multi-block), `scripts/codegen_card_db.py` 의 `BLOCK_META_KEYS` / `_project_to_desc_gen_input`

## 변환 주의: v1 → v2 adapter

Stage 1의 `validate_no_retrigger` 는 v1 schema (`sd.get("effects", [])` 가 flat action list) 기준으로 walk. v2에서는 `sd.get("effects", [])` 가 block 리스트:

```python
# v2 walk 수정 예시
for star, sd in (card.get("stars") or {}).items():
    for block in sd.get("effects", []):
        for key, val in block.items():
            if key in BLOCK_META_KEYS:
                continue
            # key = action name. retrigger 인지 확인
            if key == "retrigger":
                errors.append(...)
            # dict/list of dict 내부 effects 재귀 (on_combat_result 등)
            ...
        # block 내부 conditional/r_conditional도 각각 재귀
        for cond in block.get("conditional", []) or []:
            walk_flat_effects(cid, star, ..., cond.get("effects", []))
        ...
```

`validate_is_threshold_with_theme_system` 는 간단 — v2에서도 `is_threshold` 는 block-level 필드이지만 현재 1장 (ne_awakening) 이 사용, `impl: theme_system` 아님 → violation 없어야.
