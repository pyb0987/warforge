# Handoff — Phase 2 B-direct migration (block-format runtime)

## Status: in_progress
세션 경계 체크포인트. uncommitted working tree 있음 (마지막 커밋: `ff2fdb3` Phase 1).

## Last completed
- **C1**: codegen_v2 재작성 → block 포맷 직접 출력 (`godot/core/data/card_db.gd` 공식 경로)
- **C2**: card_db.gd 헬퍼 API (`get_effect_blocks`, `get_block_for_timing`, legacy `get_theme_effects` adapter)
- **C3 대부분**: chain_engine.gd 전면 재작성 (block-aware dispatch, 모든 phase 루프가 `_find_block(tmpl, TIMING)` 기반, `_execute_actions(actions_list)`)
- `card_instance.gd` 에 `can_activate_with(max_act, bonus)` 추가

## Current state
- `data/cards_v2/*.yaml` — 55장 (Phase 1 커밋에 포함됨)
- `scripts/codegen_v2.py` — 공식 경로에 block 포맷 생성. `_c()` 헬퍼가 flat accessor hoist (backward-compat). legacy `get_theme_effects` adapter는 block.actions + r_conditional/conditional 재구성
- `godot/core/chain_engine.gd` — 전면 block-aware
- `godot/core/card_instance.gd` — can_activate_with 추가
- `godot/core/data/card_db.gd` — v2 block 포맷 (chmod 444)
- **GUT: 902 중 886 pass, 16 fail**

## 남은 16 failure 패턴

### 카테고리 A — legacy 가정 테스트 (자연 마이그레이션)
- `test_sp_warmachine_is_persistent` ([test_card_db.gd:309](godot/tests/test_card_db.gd:309)): `t["effects"].size() == 0` 기대. v2에선 1 block 있음 → `t["effects"][0]["actions"].size() == 0` 으로 업데이트

### 카테고리 B — gameplay regression (chain_engine 재작성 부산물)
1. `shield 20%`, `barrier shield 20%` — `_execute_actions`의 `shield_pct` 분기 확인
2. `merchant +3g`, `패배 시 +3g`, `max_act=1 → 1회만 +3g` — PC/PCD phase의 `grant_gold` 실행 또는 max_act 체크 확인
3. `ON_COMBAT_ATTACK → 1 버프`, `ON_COMBAT_DEATH → 1 버프` — `process_combat_event` block.actions 에서 `combat_buff_pct` 찾기 실패
4. `BS buff → ATK 증가`, `predator BS`, `military BS`, `wildforce ATK`, `chimera enhance`, `패배 시 enhance` — 값 `12.0 → >12.0` 기대. BS/PC temp_buff/enhance 실패
5. `druid PC → gold`, `military PC → gold`, `druid BS → shield` — theme_systems `apply_battle_start`/`apply_post_combat` 경로
6. `2/2 → false` — 미확인
7. `Unexpected Errors` — runtime error 확인 필요

## 권고 진단 순서
1. `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=2 -gexit 2>&1 | tail -200` 로 구체 실패 컨텍스트
2. 실패 테스트 `test_*.gd` 파일에서 해당 함수 Read
3. chain_engine 관련 phase 루프에 실행 흐름 확인
4. 가장 의심: `apply_battle_start`, `apply_post_combat` delegation 조건 (actions.is_empty() check — theme_system 카드 모두 해당)

## C4 재평가 (작업량 축소됨)
원래 계획의 C4 (5 theme_systems block-aware 수정) 는 거의 **불필요**. `get_theme_effects` adapter 가 v1 호환 리스트 반환하므로 기존 `_find_eff` 작동.

**sp_warmachine이 multi-block 되는 C5 시점**에만 steampunk_system이 block 직접 읽도록 수정 필요 (adapter는 block[0]만 반환).

## Next entry point
1. **16 failure 해결** (~20분 예상, 대부분 chain_engine 재작성 미세 버그)
   - gplog=2 로 세부 로그 → 실패 지점 특정 → chain_engine 수정
2. **902/902 복원 후** → C3+C4 중간 multi-review
3. **C5 sp_warmachine**:
   - `data/cards_v2/steampunk.yaml`에 RS 블록 추가 (★1:1기 / ★2:2기 / ★3:4기)
   - 신규 action `manufacture` (comp 랜덤 유닛, MF 이벤트 emit)
   - steampunk_system.gd에 RS 핸들러 + block-aware access
4. **C6 승격**:
   - `scripts/codegen_card_db.py` 삭제
   - `data/cards` 삭제, `data/cards_v2` → `data/cards` rename
   - `scripts/codegen_v2.py` → `scripts/codegen_card_db.py` rename
   - `.claude/settings.json` hook 대상 경로 업데이트 (cards_v2 → cards, codegen 파일 이름 업데이트)

## 중요 메모
- **rollback**: `git checkout -- godot/core/chain_engine.gd godot/core/card_instance.gd godot/core/data/card_db.gd godot/core/data/card_descs.gd scripts/codegen_v2.py`
- card_db.gd chmod 444 유지. Python codegen만 write 가능
- codegen_card_db.py (v1) 아직 존재. 실수 실행 주의 — v1 포맷으로 덮어씀
- data/cards (v1) + data/cards_v2 공존. 현재 codegen_v2 만 v2 사용
- YAML→codegen drift hook 경로는 v1 기준. data/cards_v2/*.yaml 수정 시 훅 안 걸림 → C6에서 수정
