---
iteration: 3
date: "2026-04-05"
type: subtractive
verdict: improved
files_changed: [".claude/settings.local.json", "CLAUDE.md", ".claude/traces/failures/", ".claude/traces/search-set.md"]
refs: [1, 2]
---

## Iteration 003: 하네스 건강도 점검 — dead hook 제거 + 피드백 루프 부트스트랩
Trigger: multi-review (3-Critic, 평균 5.7/10)에서 "있지만 작동하지 않는 하네스" 진단

### Diagnosis
multi-review 결과 3인 공통 지적:
1. sim/simulate.py hook = dead reference (Python sim 삭제 후 미갱신)
2. failures/ 0건 + search-set 비어있음 = 피드백 루프가 한 번도 닫히지 않음
3. hook 3개 모두 경고만 출력 (exit 1 없음) = "외부 강제" 원칙과 괴리

### Change
1. **Subtractive**: sim/simulate.py PostToolUse hook 제거
2. **Subtractive**: commit guard에서 card_pool.py, unit_pool.py (삭제된 Python 파일) 참조 제거
3. **Additive**: commit guard에 `exit 1` 추가 (경고 → 차단)
4. **Additive**: CLAUDE.md Harness 섹션에 hook 강제력 정책 명시 (차단형/경고형)
5. **Additive**: failures/ 2건 회고 기록 (001-sim-hook, 002-evaluator-dead-zone)
6. **Additive**: search-set.md 2건 추가 (verify 명령 포함)
7. **Subtractive**: permissions.allow에서 삭제된 sim/ Python 경로 6건 제거

### Result
- Before: dead hook 1개, failures/ 0건, search-set 0건, 모든 hook 경고만
- After: dead hook 0개, failures/ 2건, search-set 2건 (verify 실행 가능), commit guard 차단형
- SS-001 verify: PASS

### Lesson
- hook은 코드 마이그레이션과 동기화되어야 함 — 코드 구조 변경 체크리스트에 "hook 경로 확인" 추가
- 피드백 루프는 첫 엔트리가 가장 어려움 — 회고적 기록으로라도 부트스트랩해야 루프가 돌기 시작
- "있지만 작동하지 않는" 상태가 "없는" 것보다 위험 — 정기 점검(multi-review) 필요
