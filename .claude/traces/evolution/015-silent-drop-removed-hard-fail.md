---
iteration: 15
date: "2026-04-17"
type: structural
verdict: pending
files_changed:
  - scripts/codegen_card_db.py (THEME_EFFECTS/is_theme_effect 제거 + CARD_DB_ACTIONS hard-fail)
  - data/cards/steampunk.yaml (sp_interest.battle_buff 제거, sp_line.persistent 제거)
  - godot/core/data/card_db.gd (codegen 재생성)
refs:
  - "commit 0c785b3 — buff을 THEME_EFFECTS에서 제거한 spot fix (2026-04-17)"
  - ".claude/traces/evolution/013-r-conditional-star-parity-validator.md (P5 구조 흡수)"
  - "대화: '#1 후속 과제 — THEME_EFFECTS 필터링 구조 P5 3단계 강화'"
---

## Iteration 15: silent drop 구조 제거 (P5 3단계)

### Problem

iteration 14까지도 codegen의 `gen_effects_array`는 `is_theme_effect` 필터로 알려지지 않은 action을 조용히 누락시키고 있었다:

```python
card_db_effects = [e for e in effects if not is_theme_effect(e)]
```

여기에 포함된 silent drop의 실제 피해:

1. **ne_wildforce ★1~★3**: `buff` action이 `THEME_EFFECTS` 세트에 실수로 포함돼 BS 경로 no-op. commit 0c785b3에서 spot fix(해당 action을 세트에서 제거)했으나 **구조 자체가 다른 action에서 동일 사고를 또 낼 수 있었다**.
2. **sp_interest ★2/★3**: `battle_buff` YAML 선언은 실제 런타임에 도달하지 않고 [game_manager.gd:304](godot/scripts/game/game_manager.gd:304)의 하드코딩 경로가 카드 ID로 직접 처리. YAML은 **drift 위험이 있는 문서용 선언**.
3. **sp_line ★3**: `persistent: {all_spawn_strongest: true}` — 런타임 구현이 **전혀 없는** dead declaration. YAML에만 존재해 설계와 실제 동작이 분리.

P5 사다리 평가:
| 단계 | 메커니즘 | iter 14 상태 |
|------|---------|--------------|
| 0. 규칙 | "YAML과 코드 동기화" | CLAUDE.md 기재, 자발적 준수 |
| 1. 경고 | YAML→codegen drift 훅 | ne_wildforce buff 같은 **silent semantics drift는 탐지 못함** |
| 2. 차단 | r_conditional parity validator (iter 13) | 부분 범위 (r_conditional 내부만) |
| 3. **구조적 불가능** | **이번 이터레이션** |

### Change (structural — 필터를 삭제하고 hard-fail로 대체)

1. **codegen `gen_effect()` else 분기를 `ValueError` raise로 변경**
   - `CARD_DB_ACTIONS = frozenset({"spawn", "enhance", "buff", "gold", "terazin", "shield", "scrap", "diversity_gold", "absorb"})` 화이트리스트.
   - 미지 action 도달 시 에러 메시지에 "theme-system이면 `impl: theme_system` 설정, 아니면 handler 추가" 안내 포함.

2. **`gen_effects_array`의 `is_theme_effect` 필터 삭제**
   - 호출부는 이미 `impl == "theme_system"` 분기로 routing되므로, 여기 도달하는 effect는 전부 card_db 대상이라는 invariant 확보.
   - 이 invariant 위반은 1번의 hard-fail이 즉시 노출.

3. **`THEME_EFFECTS` / `is_theme_effect` 완전 제거**
   - 잔여 call site 없음 (`grep` 확인). 대신 trace 포인터 주석만 남김.

4. **YAML dead/drift 정리 (사용자 scope 확인 후 진행)**
   - `sp_interest ★2/★3`: `battle_buff` 제거 + game_manager 하드코딩 경로를 노출하는 NOTE 주석 추가. 향후 reroll_buff action type 도입 시 YAML 복원 가능.
   - `sp_line ★3`: `persistent: {all_spawn_strongest: true}` 제거 + 구현 복원 조건 주석.

### 효과: P5 3단계 달성 조건

- **Silent drop 불가능**: base effects에 알려지지 않은 action을 넣으면 codegen이 실패 → YAML 저장 후 즉시 PostToolUse 훅(`codegen --check`)이 exit 2로 노출.
- **Drift 자체가 불가능**: YAML에 효과를 썼는데 코드가 그걸 해석할 handler가 없으면 codegen이 실패. "YAML에 썼는데 효과 안 났어요" 같은 조용한 분리 자체가 발생 불가.
- **Escape hatch는 명시적**: theme-system 경로는 `impl: theme_system` + `_theme_effects[card_id]` 별도 저장소. 이 marker가 없으면 chain_engine 직결 dispatch를 요구.

### Validation

- `python3 scripts/codegen_card_db.py` → ✅ 55 cards generated.
- `python3 scripts/codegen_card_db.py --check` → ✅ card_db.gd + card_descs.gd match YAML.
- `python3 -m unittest scripts.tests.test_r_conditional_validator` → 12/12 OK (iter 13 검증기 유지).
- `godot --headless ... -gdir=res://tests ... -gexit` → **897/897 passing, 0 failing**.
- 합성 regression test: codegen 실행 중 sp_interest.battle_buff가 hard-fail을 정확히 일으켰고 (확인 후 YAML 정리), 다시 실행하면 clean pass.

### Remaining risk

- **sp_interest 하드코딩 경로는 유지됨**. YAML이 실제 소스가 아니라 주석으로만 남아있어, "리롤 버프 +5%/reroll" 같은 수치는 여전히 [game_manager.gd:306](godot/scripts/game/game_manager.gd:306)에만 있다. 이를 완전히 SSOT로 올리려면 `reroll_buff` action type + handler + YAML 재선언이 필요. 현재는 "dead YAML 제거"까지만 완료.
- **sp_line "모든 스팀펑크 제조가 가장 강한 유닛" 효과는 ★3 설계 의도였을 수 있음**. 구현 복원이 필요하면 backlog 항목으로 등록 필요.
- 새 handler를 추가할 때 `CARD_DB_ACTIONS` 화이트리스트 갱신이 인간 작업. 누락 시 codegen fail로 노출되지만 "추가가 필요하다"는 판단은 자동화 안 됨.
