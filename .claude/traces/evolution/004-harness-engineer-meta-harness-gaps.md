---
iteration: 4
date: "2026-04-06"
type: additive
verdict: pending
files_changed: [".claude/skills/harness-engineer/SKILL.md"]
refs: [3]
---

## Iteration 004: harness-engineer Meta-Harness 원칙 미비 보강

Trigger: multi-review #4 (init-harness + harness-engineer 조합 평가), avg 6.7/10 FAIL

### Diagnosis
3인 Critic 공통 지적:
1. P3 Non-Markovian: 진단 시 이전 failures 참조가 권장이지 강제가 아님
2. P9 Transfer: 크로스 프로젝트 승격 트리거와 절차 미정의
3. 용어 불일치: "JSON frontmatter" vs 실제 YAML 사용
4. search-set Active 0건 시 검증 공백
5. 수동 트리거 의존: 조용한 성능 저하 감지 메커니즘 부재

### Changes (5건, 모두 harness-engineer SKILL.md)
1. **R1 (Additive)**: 진단 소스에 Non-Markovian 필수 절차 추가 — 진단 전 `grep -rl` 실행 강제
2. **R2 (Additive)**: Periodic Review에 Transfer 섹션 신설 — classification 3회+ 시 learned/ 승격
3. **R3 (Subtractive)**: "JSON frontmatter" → "YAML frontmatter" 용어 수정 (2건)
4. **R4 (Additive)**: Evaluation Set에 Active 0건 정책 추가 — resolved=false 검색 또는 Archived verify 재실행
5. **R5 (Additive)**: Periodic Review에 30일+ 무변경 시 entropy-check 자동 트리거 조건 추가

### Result
- Before: P3 권장, P9 미정의, 용어 불일치, search-set 공백, 수동 트리거만
- After: P3 강제 절차, P9 승격 절차, 용어 통일, Active 0 대응 정책, 시간 기반 트리거

### Lesson
- "권장"과 "강제"의 차이가 실제 루프 작동 여부를 결정 — 핵심 절차는 반드시 강제로
- 크로스 프로젝트 패턴은 정량적 트리거(N회 반복)가 있어야 승격이 실행됨
