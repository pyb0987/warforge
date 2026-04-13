---
iteration: 6
date: "2026-04-06"
type: additive
verdict: pending
files_changed: [".claude/skills/harness-engineer/SKILL.md", ".claude/commands/init-harness.md"]
refs: [5]
---

## Iteration 006: 최종 잔류 약점 해소 (F1-F3)

Trigger: multi-review #6 (재검증), avg 8.7/10 MIXED — 잔류 3건

### Diagnosis
3인 Critic 공통 잔류:
1. F1: P9 역방향 — init-harness가 ~/.claude/skills/learned/ 기존 패턴을 신규 프로젝트에 적용하지 않음
2. F2: P7 — Step 8 체크리스트에 스킬 Anti-patterns 섹션 확인 항목 없음
3. F3: diagnosis→proposal 전환 조건 미정의 (진단 과잉 억제 없음)

### Changes (3건)
1. **F1 (Additive, init-harness)**: Step 2에 `ls ~/.claude/skills/learned/` 스캔 추가 + Step 8 체크리스트에 learned/ 참조 확인 항목 추가
2. **F2 (Additive, init-harness)**: Step 8 체크리스트의 스킬 항목에 "Anti-patterns 섹션 포함" 게이트 추가
3. **F3 (Additive, harness-engineer)**: Output Format 진단 섹션에 전환 판단 분기 가이드 추가 — (a) Prevention 불충분→강화, (b) 다른 원인→재진단, (c) 재발→에스컬레이션

### Result
- Before: P9 단방향, Anti-patterns 게이트 없음, 전환 조건 암묵적
- After: P9 양방향(승격+역적용), Anti-patterns 체크리스트 게이트, 전환 3분기 명시
