---
date: "2026-04-26"
classification: "도구 부재"
escalated_to: "CLAUDE.md Build 섹션 + search-set SS-008"
search_set_id: "SS-008"
resolved: true
resolved_date: "2026-04-26"
escalation_date: "2026-04-26"
---

## Failure: stale `.godot/global_script_class_cache.cfg` 로 인한 149 false-positive 실패

### Observation

worktree에서 GUT 전체 스위트 실행 시 933개 중 149개가 카스케이드로 실패. 첫 에러:

```
SCRIPT ERROR: Parse Error: Identifier "NeutralSystem" not declared in the current scope.
   at: GDScript::reload (res://core/chain_engine.gd:50)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
   at: GDScript::reload (res://tests/test_chain_engine.gd:0)
```

`chain_engine.gd:50`이 `NeutralSystem.new()`를 호출하는데, fresh 환경에서 `class_name NeutralSystem`이 인식 안 됨 → chain_engine.gd 컴파일 실패 → `_engine = ChainEngine.new()` 가 null 반환 → 모든 chain 의존 테스트가 "Nonexistent function 'run_growth_chain' in base 'Nil'" 로 실패.

### Diagnosis

- 도입 시점: commit `8532451` (Phase 3b-2b — neutral_system 마지막 3카드)
- 작업자 보고: "GUT 908/908 통과" — 에디터 cache warm 상태에서 테스트
- 실제 fresh 환경(headless, worktree, CI)에서는 class_name 등록 순서가 달라 NeutralSystem 등록이 chain_engine.gd 컴파일 시점보다 늦음
- 검증: `rm -f godot/.godot/global_script_class_cache.cfg && godot --headless --path godot/ --import` 후 GUT 재실행 → **1000/1000 통과**

### Root cause

GDScript의 `class_name` 등록은 `.godot/global_script_class_cache.cfg`에 의존. 새 `class_name`이 추가된 commit이 머지될 때, 이미 cache가 있는 환경에서는 invalidation이 자동으로 일어나지 않으므로 stale 상태로 잔존. fresh import만이 cache를 재구축.

문제는 다음 두 조건이 결합돼야 표면화됨:
1. 새 worktree 또는 CI 첫 실행 (cache 없음 → import 실행)
2. import 시 class_name 등록과 의존 스크립트 컴파일이 동시 진행 (등록 누락 가능)

기존 환경에서는 cache가 warm 상태이거나, 여러 번의 에디터 reload로 자연 정리됨 → 작업자가 인지 못 함.

### Fix

- **즉시**: `rm -f godot/.godot/global_script_class_cache.cfg && godot --headless --path godot/ --import`
- **재발 방지**:
  1. CLAUDE.md `Build` 섹션에 cache 재빌드 명령 명시
  2. search-set SS-008 등재 — fresh 환경 진입 시 cache rebuild 후 GUT 통과 확인

### Lesson

- "GUT N/N 통과"는 환경 의존적일 수 있음. 작업자 환경(에디터 warm cache)과 검증 환경(fresh)이 다르면 false-positive 통과 가능.
- `class_name` 추가 commit은 fresh 환경 검증을 명시적으로 거쳐야 함.
- 카스케이드 실패가 발견되면 첫 SCRIPT ERROR (compile/parse error)를 우선 확인. 이후 발생하는 "Nil" 호출 에러는 카스케이드 결과일 뿐 원인 아님.
