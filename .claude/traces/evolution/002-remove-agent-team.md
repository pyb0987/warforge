---
iteration: 2
date: "2026-03-31"
type: subtractive
verdict: neutral
files_changed: ["CLAUDE.md", ".claude/agents/", ".claude/skills/warforge-orchestrator/"]
refs: [1]
---

## Iteration 002: 에이전트 팀 제거 — Meta-Harness 충실 구현
Trigger: Meta-Harness 논문이 단일 에이전트 환경 최적화에 집중하며, 에이전트 팀/오케스트레이션을 다루지 않음. 논문: "skill document 품질 > iteration 수 > population size"

### Diagnosis
Iteration 001에서 에이전트 팀을 "기존 자산 보존"으로 유지했으나, Meta-Harness 원칙과 충돌:
- P3 (Minimal outer loop): 오케스트레이션 = 복잡한 outer loop
- 변경 격리: 여러 에이전트 동시 변경 시 교란 변수 발생
- Context efficiency: 에이전트 간 통신 오버헤드

### Change
1. **삭제**: `.claude/agents/` 전체 (designer, balancer, engineer, qa, delegation-protocol)
2. **삭제**: `.claude/skills/warforge-orchestrator/` (팀 오케스트레이션 전용)
3. **보존**: card-designer (도메인 스킬 — 논문의 "skill document = highest leverage")
4. **보존**: btw (유틸리티)
5. **CLAUDE.md**: Agent Team 섹션 제거, Harness 섹션을 Meta-Harness 4요소로 재구성

### Result
- Before: 4 agents + delegation-protocol + orchestrator + 3 skills
- After: 0 agents + 2 skills (card-designer, btw)
- Verdict: neutral (subtractive 변경, 효과는 향후 작업에서 검증)

### Lesson
- "작동하는 것을 보존한다"는 Additive first 원칙이지만, 논문의 핵심 철학과 충돌하면 제거가 맞음
- 에이전트 팀의 지식(카드 설계 방법론)은 도메인 스킬(card-designer)에 이미 포함 — 에이전트 정의 없이도 동일한 품질 가능
