---
iteration: 22
date: "2026-04-26"
type: structural
verdict: adopted
files_changed:
  - godot/core/game_state.gd (try_merge fresh_ref + _try_merge_once 3-tier survivor + spawn_card/add_clone funnel)
  - godot/core/card_instance.gd (absorb_donor skip_units + add_specific_unit/line506 unique_*_mult 키 보강)
  - godot/scripts/build/shop.gd (spawn_card 사용으로 리팩터)
  - godot/sim/shop_logic.gd (spawn_card 사용으로 리팩터)
  - godot/scripts/game/game_manager.gd (add_clone 사용)
  - godot/sim/headless_runner.gd (add_clone 사용)
  - godot/core/commander.gd (보드 스왑 라인 lint:allow zone-assign)
  - godot/sim/ai_agent.gd (재배치 라인 lint:allow zone-assign)
  - data/cards/druid.yaml (low_unit thresh ★2=4/★3=8, dr_wrath unit_cap 3/8/16)
  - godot/core/data/card_db.gd (codegen)
  - godot/core/data/card_descs.gd (codegen)
  - godot/tests/test_merge_system.gd (+11 tests: fresh_ref policy + spawn_card funnel)
  - godot/tests/test_druid_system.gd (dr_wrath cap 16 회귀 갱신)
  - scripts/lint_card_spawn.py (신규: card spawn 단일 진입점 검증)
  - scripts/tests/test_lint_card_spawn.py (신규: lint 회귀 테스트 10건)
  - .githooks/pre-commit (신규: staged .gd lint 검사)
refs:
  - "user spec: 합성 시 신규 카드의 유닛 흡수 skip — 3장 → 2장분량 (3배→2배). is_fresh 카드 필드 도입 안 함, try_merge 호출 인자로만 전달."
  - "user spec: 캐스케이드 시 fresh 전파 (★1→★2 cascade survivor도 fresh로 추적)"
  - "user spec: survivor 선정 3-tier (업그레이드 max → non-fresh 우선 → leftmost iteration)"
  - "user spec: 신규 카드 생성하는 모든 경로(구매/보스 보상/부적/카드효과)가 fresh_ref 전달, 구조상 강제 (P5 사다리 2.5단계 — pre-commit lint hook + opt-out 주석)"
  - "iter 21 임계값 되돌림: 3배→2배 정책 정합 (★1=2 / ★2=4 / ★3=8 = 2장분량 cascade)"
---

## Iteration 22: 합성 fresh 정책 + spawn_card 단일 진입점 (P5 2.5단계)

### Problem

iter 20/21에서 도너 stat 흡수 정책을 통합한 후, **3장 합성 시 도너 유닛이 모두 흡수**(★1×3 → 6u, ★2×3 → 18u, ★3 캐스케이드 → 54u)되는 점이 두 결과를 만들었다:

1. **드루이드 "소수 정예" 임계값 무력화** → iter 21에서 임계값 자체를 3배(★2=6, ★3=18)로 상향해 회피.
2. **dr_world unique mult 캐스케이드 폭발** → iter 21에서 [고유효과] mult layer 분리 + max 합성 정책 도입.

iter 21 후속 검토에서 사용자가 두 문제의 **근본 원인을 합성 흡수 비율(3배)로 재진단**:
- 3배는 너무 가파른 진척 → 마지막 산 카드의 유닛은 흡수에서 제외 (2장분량 = 2배)
- 임계값 자체가 아니라 흡수 정책을 바꾸면 임계값을 자연스럽게 되돌릴 수 있음 (★2=4, ★3=8)
- ★3 캐스케이드의 unique mult 폭발도 도너 1장이 자동 skip 되어 완화

### Approach

**Step 1 — 호출 컨텍스트 한정 fresh 추적 (카드 필드 도입 안 함)**:

`try_merge(template_id, fresh_ref: CardInstance = null)`. fresh 정보는 함수 호출 인자로만 전달, CardInstance에 `is_fresh` 필드 없음. 캐스케이드는 `_try_merge_once` 내부에서 로컬 `fresh_set: Array`를 통해 전파:

```
fresh_set = [fresh_ref] if fresh_ref else []
while ...
    step = _try_merge_once(template_id, fresh_set)
    # step 내부에서 fresh-include면 survivor를 fresh_set에 append
```

이 설계의 핵심 장점:
- 라운드 종료 / 빌드 페이즈 종료 등 "리셋 타이밍" 정의 불필요 (호출 단위 소멸)
- 보스 보상 / 부적 카드 등 외부 spawn 경로는 자연스럽게 자기 try_merge에 fresh_ref 넣거나 안 넣음을 결정

**Step 2 — survivor 선정 3-tier**:

| 순위 | 기준 | 근거 |
|------|------|------|
| 1 | 업그레이드 수 max | 기존 정책 유지 (R5 OBS-011 회귀 보호) |
| 2 | non-fresh 우선 (동률 시) | fresh가 survivor가 되면 자기 own units 보존 → 2장분량 의도 깨짐. non-fresh 우선으로 회피. |
| 3 | iteration 순서 (보드 leftmost → 벤치 leftmost) | 기존 정책 |

**Step 3 — `absorb_donor(donor, skip_units: bool = false)`**:

skip_units=true일 때 유닛 count 합산만 건너뜀. stack mult / growth / theme_state / upgrade 등은 정상 흡수. fresh donor가 약간의 stat 보너스(체인강화, 업그레이드)를 받아왔다면 그건 보존해야 자연스러움.

**Step 4 — spawn_card 단일 진입점 (P5 2.5단계 구조적 강제)**:

```
GameState.spawn_card(template_id) -> Dictionary
    create + Commander.apply_card_bonuses + add_to_bench + try_merge(fresh_ref=card)
GameState.add_clone(template_id) -> CardInstance
    create + add_to_bench (auto-merge 미트리거 — 시스템 카드 경로)
```

호출처 리팩터:
- shop.gd / shop_logic.gd → spawn_card
- game_manager.gd / headless_runner.gd (ne_clone_seed) → add_clone

**Step 5 — Lint + pre-commit (drift 차단)**:

`scripts/lint_card_spawn.py`:
- `CardInstance.create(` 직접 호출 검출 (whitelist: game_state.gd, tests/)
- `(bench|board)\[..\] =` 직접 대입 검출 (동일 whitelist)
- 라인 단위 opt-out: `# lint:allow card-create` / `# lint:allow zone-assign`

`.githooks/pre-commit`:
- staged `.gd` 파일을 lint script에 전달
- `core.hooksPath = .githooks` 활성화 (worktree config 갱신)
- `SKIP_LINT=1 git commit` 우회 가능 (긴급 hotfix용, 권장 안 함)

10개 단위 테스트 (`scripts/tests/test_lint_card_spawn.py`)로 lint 자체 회귀 보호.

**Step 6 — 임계값 yaml 되돌림 (iter 21 작업 무효화)**:

| 카드 | 항목 | iter 21 (3배) | iter 22 (2배) |
|------|------|---------------|---------------|
| dr_lifebeat | low_unit thresh | 2 / 6 / 18 | 2 / **4** / **8** |
| dr_origin | low_unit thresh | 2 / 6 / 18 | 2 / **4** / **8** |
| dr_deep | low_unit thresh | 2 / 6 / 18 | 2 / **4** / **8** |
| dr_wrath | unit_cap | 3 / 9 / 27 | 3 / **8** / **16** |

dr_wrath cap은 thresh × 2 (50% 버퍼) — 사용자 결정 (옵션 나).

### Side Fix (out of scope but adopted)

`add_specific_unit` (line 432) 및 line 506의 stack 추가 사이트가 `unique_atk_mult / unique_hp_mult` 키 없이 stack 생성 → iter 21 이후 `multiply_unique_stats`가 missing key 접근으로 런타임 에러. iter 21 GUT는 통과했으나 spawn_card 도입으로 game_state 흐름이 미세히 바뀌면서 노출됨 (test_evaluator). _init_stacks와 동일한 키 셋으로 보강하여 정합화.

### Verification

- TDD: 11 신규 테스트 (`test_merge_system.gd`):
  - `test_fresh_donor_units_skipped_two_thirds`
  - `test_fresh_ref_null_keeps_3x_legacy_absorption` (legacy 회귀 보호)
  - `test_fresh_survivor_prefers_non_fresh_when_upgrades_tied`
  - `test_fresh_survivor_kept_when_uniquely_most_upgrades`
  - `test_fresh_propagates_through_cascade_to_star3`
  - `test_fresh_no_propagation_means_full_3x_at_step2` (대조)
  - `test_fresh_only_applies_when_in_picked_three`
  - `test_spawn_card_creates_and_benches`
  - `test_spawn_card_with_two_existing_triggers_fresh_merge`
  - `test_spawn_card_no_merge_returns_empty_steps`
  - `test_spawn_card_bench_full_signals_via_bench_idx`
  - `test_add_clone_creates_without_merge`
- 회귀 갱신: dr_wrath cap 27→16 (test_druid_system.gd)
- 전체 GUT: **1017/1017 통과** (cache 재빌드 후, 11 신규 + iter 21 1006개)
- Lint 단위 테스트: 10/10 통과
- Lint 운영 검증: 정당 사용 5건 opt-out 주석 처리, smoke test로 hook 위반 차단 확인

### Search-set 등재

SS-009: card spawn 단일 진입점 위반 검출 (별도 항목으로 search-set.md 추가).

### Out-of-scope (잔여)

- 작업 2 (메커니즘 4안 비교) — 작업 1의 효과 측정 후 결정. 2배 흡수로 mult 폭발이 충분히 완화되면 현행 unique layer + max 유지 권장.
- DESIGN.md / docs/design 동기화 — iter 22 변경사항 반영 필요 (별도 작업).
- 다른 worktree/clone에서 `core.hooksPath = .githooks` 활성화는 수동 (`git config core.hooksPath .githooks`). README/setup 문서화 별도.
