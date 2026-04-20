# 계획 — effect-level trigger_timing 구조 개편 + sp_warmachine RS 스폰

**작성일**: 2026-04-20
**선행**: Session A (CP rebalance) + B (★ merge bonus 제거) 완료
**상위 컨텍스트**: `.claude/plans/balance-c-t4t5-effect-buff.md` — T4/T5 효과 상향 과정에서 sp_warmachine의 RS+PERSISTENT 혼합 타이밍 요구가 발생하여 구조 개편 선행

## 배경

현재 YAML 스키마는 카드 상단 `timing` 1개만 허용. `sp_warmachine`처럼 **RS(spawn)+PERSISTENT(range_bonus)** 두 타이밍을 동시에 갖는 카드를 체계적으로 지원할 수 없음. 임시 해결(apply_persistent hook 재활용)이 가능하지만 evidence가 누적되면 결국 구조화 필요. 지금 한 번에 구조로 흡수한다.

## 최종 YAML 스펙 (확정)

```yaml
sp_warmachine:
  name: 전쟁 기계
  tier: 4
  theme: steampunk
  comp:
    - {unit: sp_turret, n: 2}
    - {unit: sp_cannon, n: 2}
    - {unit: sp_drone, n: 2}
  tags: [steampunk, combat]
  impl: theme_system
  stars:
    1:
      effects:
        - trigger_timing: RS
          max_act: -1
          spawn_firearm: {count: 1, random: true}
        - trigger_timing: PERSISTENT
          max_act: -1
          range_bonus: {tag: firearm, unit_thresh: 8}
    2:
      effects:
        - trigger_timing: RS
          max_act: -1
          spawn_firearm: {count: 2, random: true}
        - trigger_timing: PERSISTENT
          max_act: -1
          range_bonus: {tag: firearm, unit_thresh: 6, atk_buff_pct: 0.30}
    3:
      effects:
        - trigger_timing: RS
          max_act: -1
          spawn_firearm: {count: 4, random: true}
        - trigger_timing: PERSISTENT
          max_act: -1
          range_bonus: {tag: firearm, unit_thresh: 4, atk_buff_pct: 0.30, attack_stack_pct: 0.12}
```

### 핵심 원칙
1. 카드 상단 `timing` 필드 **완전 제거**. default 없음.
2. `effects` = timing 블록의 **리스트**
3. 각 블록:
   - `trigger_timing`: RS/BS/PC/PCD/PCV/PERSISTENT/SELL/MERGE/REROLL/OE/DEATH
   - `max_act`: 발동 횟수 제한 (블록별)
   - `listen`: `{l1, l2}` — OE일 때만
   - `conditional` / `r_conditional`: 블록의 timing 상속 (내부 effect에 `trigger_timing` 중복 명시 X)
   - 나머지 key들 = actions (spawn, enhance, range_bonus, ...)
4. 동일 action 중복 시 params를 리스트로:
   ```yaml
   spawn:
     - {target: self, count: 1}
     - {target: both_adj, count: 2}
   ```
   단일은 dict 유지 가능. codegen이 `isinstance(p, list) ? p : [p]`로 정규화.

## 마이그레이션 전략 — 병렬 codegen + diff 검증

**Godot 런타임은 건드리지 않는다** (Phase 1). 기존 `card_db.gd`/`card_descs.gd` 포맷 유지. 새 codegen이 기존 포맷과 **바이트 동일** 출력 생성 → 테스트 902건 자동 회귀 검증.

복수-timing 필요 기능(sp_warmachine 확장)은 Phase 2에서 런타임 확장.

### 파일 배치

| 역할 | 기존 | 신규 (병렬) | 전환 후 |
|---|---|---|---|
| YAML | `data/cards/*.yaml` | `data/cards_v2/*.yaml` | v2 → cards/ 로 이름 회수 |
| codegen | `scripts/codegen_card_db.py` + `card_desc_gen.py` | `scripts/codegen_v2.py` + `card_desc_gen_v2.py` | v2가 공식 |
| 출력 | `godot/core/data/card_db.gd` + `card_descs.gd` | `/tmp/card_db_v2.gd` + `/tmp/card_descs_v2.gd` | 기존 경로 덮어쓰기 |

### 보호 훅과의 상호작용
- `card_db.gd` chmod 444 + blocking hook — 신/구 codegen 둘 다 이 파일을 직접 쓰지 않음. 기존 codegen만 공식 경로로 출력. v2는 `/tmp`에 출력해서 diff만.
- 최종 전환: 기존 codegen 삭제 + v2를 공식 경로로 승격 + hook 대상 경로 업데이트

## Phase 1 — 동등 이관 (런타임 영향 0)

**목표**: 새 YAML + 새 codegen이 기존 card_db.gd/card_descs.gd와 **바이트 동일** 출력 생성

### 단계

1. **`data/cards_v2/` 생성 + 스키마 변환 스크립트**
   - `scripts/migrate_v1_to_v2.py` — 기존 55장 YAML을 기계적으로 새 구조로 변환
   - 원칙: 카드 상단 `timing` + (`listen`, `require_tenure` 등) → 각 effect 블록으로 이관. ★별 `max_act`, `conditional`, `r_conditional`, `post_threshold`도 블록 안으로.
   - 단일 timing 카드는 1-block 리스트로 둘러싸기만 하면 됨
   - 여러 effect 중 같은 action 중복 → params 리스트로 합침

2. **새 codegen 작성** — `scripts/codegen_v2.py` + `card_desc_gen_v2.py`
   - 입력: `data/cards_v2/*.yaml`
   - 출력: 기존 포맷의 card_db.gd + card_descs.gd (Phase 1에서는 런타임 포맷 유지)
   - 내부에서 timing 블록들을 flat effects + card-level timing으로 "역변환"하는 셈 (Phase 1 한정, Phase 2에서 제거)

3. **Diff 검증**
   - `diff <(python3 scripts/codegen_card_db.py --dry-run) <(python3 scripts/codegen_v2.py --dry-run)` → 0 bytes
   - card_db.gd + card_descs.gd 모두 바이트 동일
   - 실패 시 migrate 또는 codegen_v2 수정

4. **GUT 테스트 902/902 유지**
   - codegen_v2로 card_db.gd 덮어쓴 상태에서 전체 테스트 통과

## Phase 2 — 런타임 확장 + sp_warmachine 신규 효과

**목표**: `trigger_timing` 블록별 실행 경로 + sp_warmachine RS spawn 효과 추가

### 단계

1. **card_db.gd 포맷 확장** — codegen_v2가 timing 블록 구조를 그대로 내보내도록 수정
   - 기존: flat `effects` + card-level `trigger_timing`
   - 확장: `effects = [{trigger_timing, actions, max_act, ...}, ...]`
   - 단일-timing 카드는 1-block 형태

2. **chain_engine.gd 수정**
   - RS 루프: 카드의 effect 블록 순회 → `trigger_timing == ROUND_START`인 블록만 `_execute_effects`
   - 블록 내부 actions를 순회하며 기존 action 핸들러 호출
   - 블록 단위 `max_act` 체크

3. **theme_systems 순회 로직 업데이트**
   - `apply_persistent`: 카드의 PERSISTENT 블록 찾아서 action 실행
   - `process_rs_card`, `process_event_card`, `apply_post_combat` 동일 패턴

4. **sp_warmachine RS 신규 효과 구현**
   - YAML에 RS 블록 추가 (스펙 위)
   - 신규 action: `spawn_firearm`
   - steampunk_system.gd에 handler 추가 — 카드의 firearm 태그 유닛 중 랜덤 1종 선택 후 N기 추가
   - 카드 설명 자동 분리: "라운드 시작: #화기 1기 랜덤 추가" + "[지속] #화기 8기당 사거리 +1"

5. **테스트 추가**
   - sp_warmachine RS spawn ★1/★2/★3 개수 검증
   - 랜덤성 검증 (seed 고정)
   - 기존 range_bonus 동작 유지 검증

## 검증 체크포인트

| Phase | 검증 |
|---|---|
| Phase 1 완료 | codegen 출력 diff 0 + GUT 902/902 pass |
| Phase 2 중간 | 각 theme_system 수정 후 해당 테마 테스트 통과 |
| Phase 2 완료 | GUT 902+α pass (sp_warmachine 테스트 추가) + sim baseline 유지 |
| 전환 | `data/cards_v2/` → `data/cards/`로 회수. 기존 삭제. codegen_v2 → codegen_card_db.py 로 승격 |

## 롤백 조건

- Phase 1에서 diff가 0이 아닐 경우 — migrate 스크립트 또는 codegen_v2 수정. 구조 자체는 유지
- Phase 2에서 회귀 발생 — 해당 theme_system 수정만 revert
- 신/구 병렬 유지 기간 동안 언제든 기존 경로로 전환 가능 (런타임은 Phase 1에서 건드리지 않으므로)

## Next entry point

1. 이 계획 사용자 승인
2. `scripts/migrate_v1_to_v2.py` 작성 → 55장 변환
3. `data/cards_v2/*.yaml` 생성 + 눈으로 몇 장 샘플 검토
4. `scripts/codegen_v2.py` + `card_desc_gen_v2.py` 작성
5. Diff 검증 루프
6. Phase 2 착수
