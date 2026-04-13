---
date: "2026-04-05"
classification: "도구 부재"
escalated_to: hook
search_set_id: "SS-001"
resolved: true
---

## Failure: sim hook이 삭제된 Python 경로를 참조

### Observation
PostToolUse hook이 `python3 sim/simulate.py -v`를 실행하지만, sim/ 디렉토리가 godot/sim/으로 이전되어 Python 파일이 전량 삭제됨.
hook이 트리거될 때마다 항상 실패(파일 없음) → `❌ SIM VALIDATION FAILED` 출력.
그러나 에이전트는 이 에러를 무시하고 작업을 계속함 — 백프레셔가 소실된 상태로 운용.

### Root Cause
- sim/ (Python) → godot/sim/ (GDScript) 마이그레이션 후 hook 갱신 누락
- hook에 dead reference가 있어도 에이전트 동작에 영향이 없어 발견이 늦음
- settings.local.json의 hook은 수동 관리 — 코드 변경과 동기화 메커니즘 없음

### Fix
- 삭제된 sim/simulate.py hook 제거 (settings.local.json)
- card_pool.py, unit_pool.py 등 삭제된 Python 파일 참조도 commit guard에서 제거

### Prevention
- CLAUDE.md Harness 섹션에 hook 목록과 강제력(차단/경고) 명시
- 향후 코드 마이그레이션 시 hook 경로 동기화를 체크리스트에 포함
