---
date: "2026-04-08"
classification: "제약 미비"
escalated_to: "tests/test_game_state.gd (회귀 테스트 2개 추가)"
search_set_id: ""
resolved: true
resolved_date: "2026-04-08"
---

## Failure: `GameState.try_merge` star-grouping 버그 — 상위 ★이 보드에 있으면 하위 ★ 그룹이 영원히 merge 불가

### Observation
사용자가 직접 플레이 중 보고: "필드에 생명의 맥동 ★2 1장, 벤치에 ★1 4장이 있는데 합쳐지지 않는다."

`try_merge`는 상점 구매 시점에만 호출됨에도 불구하고, 3장 이상의 ★1을 축적해도 ★2로 merge가 트리거되지 않음.

### Root Cause
`game_state.gd:try_merge` 구버전:
```gdscript
var all_copies: Array[Dictionary] = []
for i in board.size():
    if board[i] != null and board[i].template_id == template_id:
        all_copies.append(...)   # 보드 먼저 순회
for i in bench.size():
    if bench[i] != null and bench[i].template_id == template_id:
        all_copies.append(...)

var target_star: int = all_copies[0]["card"].star_level  # ← 버그
for entry in all_copies:
    if entry["card"].star_level == target_star:
        copies.append(entry)
```

**문제**: `all_copies[0]`의 star를 target으로 고정. 보드 먼저 순회하므로, 보드에 ★2가 한 장이라도 있으면 `target_star = 2`가 되고 벤치의 ★1 3장+은 카운트 밖으로 밀려나 merge 미발동.

전형적인 auto-chess 플로우:
1. R3: ★1 3장 사서 ★2 1장 → 보드 잔류
2. R4~5: 같은 카드 ★1을 계속 구매해 벤치 축적
3. 3번째 ★1 구매 시 try_merge 호출
4. `all_copies[0]`은 보드의 ★2 → `target_star=2` → ★1 그룹 무시 → return {}
5. 4, 5번째 구매 시에도 동일 → **영원히 merge 안 됨**

### Impact — 테스트 갭과 sim 오염
**기존 테스트가 이 버그를 못 잡은 이유**:
- 모든 `test_try_merge_*` 케이스가 "한 존(보드)에 같은 ★으로만" 배치된 깨끗한 초기 상태
- 유일하게 혼합 ★을 다룬 `test_try_merge_mixed_stars_no_merge`는 ★1 2장 + ★2 1장으로, 낮은 ★이 어차피 3장 미만이라 empty 반환이 옳았음 — 버그를 우회
- **플로우 테스트(선행 merge → 후속 축적) 부재**. 실 플레이 시퀀스에서만 발현되는 합성 상태를 구성하는 테스트가 없었음

**Sim 오염 가능성**:
- `GameState`는 play와 sim(`headless_runner`)이 공유. sim도 동일 버그를 겪고 있었음
- ai_agent가 ★2 도달 후 같은 카드를 더 구매해 ★3으로 올리는 전략이 실제로는 실행되지 않았음
- autoresearch best_genome.json의 weighted_score 측정치는 이 버그가 내재된 채 평가됨
- 고정된 버그 조건하에서 상대 비교는 유효했으나, 절대 수치는 재측정 필요

### Fix
`game_state.gd:try_merge` — ★ 그룹별 dict로 분리하고 가장 낮은 ★부터 3장 있는 그룹을 merge. Cascade 지원:
```gdscript
func try_merge(template_id: String) -> Dictionary:
    var last_result: Dictionary = {}
    while true:
        var step := _try_merge_once(template_id)
        if step.is_empty():
            break
        last_result = step
    return last_result

func _try_merge_once(template_id: String) -> Dictionary:
    var by_star: Dictionary = {}   # star -> Array[{zone, idx, card}]
    # ... populate from board + bench ...
    var stars: Array = by_star.keys()
    stars.sort()
    var copies: Array = []
    for s in stars:
        if by_star[s].size() >= 3:
            copies = by_star[s].slice(0, 3)
            break
    if copies.size() < 3:
        return {}
    # ... merge ...
```

회귀 테스트 2개 추가 (`tests/test_game_state.gd`):
- `test_try_merge_star2_on_board_ignores_star1_bench_bug` — 사용자 정확 시나리오
- `test_try_merge_cascade_star1_to_star3` — cascade 체인 검증

전체 GUT: 748/748 통과.

### Prevention
1. **플로우 기반 테스트 추가**: 단일 함수의 대칭적 input-output 테스트를 넘어, "선행 상태를 만들고 그 위에서 함수 호출" 시나리오를 명시적으로 구성. 특히 `try_merge`, `try_purchase`, `try_levelup` 같은 스테이트풀 API는 "앞선 호출의 결과 위에서 동작하는가"를 체크해야 함
2. **Cross-zone × cross-star 매트릭스**: 카드 관련 테스트는 최소한 (보드, 벤치) × (★1, ★2, ★3)의 조합 매트릭스를 돌아야 함. mixed_stars 테스트를 "낮은 ★이 3장인 variant"로 확장했다면 즉시 발견됐을 것
3. **Sim-side sanity check**: autoresearch 루프에 "★ 진화 분포" 같은 행동 메트릭을 추가해, ★3 도달 횟수가 비현실적으로 낮으면 경보. 현재 evaluator는 결과만 보고 중간 행동을 감시하지 않음
4. **Autoresearch 재측정**: best_genome.json의 weighted_score를 수정본으로 다시 돌려 baseline 업데이트 필요

### Lessons
- **"함수가 올바르게 짜였는가"와 "함수가 실제 플로우에서 올바르게 동작하는가"는 다른 질문**. 단위 테스트는 전자를, 통합/플로우 테스트는 후자를 답한다. 양쪽 다 있어야 함
- **공유 코드베이스의 리스크**: play와 sim이 같은 `GameState`를 쓰는 것이 parity를 위해 좋지만, 한쪽(sim)에서 UI가 없어 증상이 보이지 않는 버그는 오래 잠복할 수 있음. 사용자의 실 플레이가 가장 강한 검증 신호였음
- **Search-set 후보**: 이 버그는 SS-XXX로 추가할 가치가 있음 — 향후 try_merge 리팩토링 시 회귀 방지용
