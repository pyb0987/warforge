---
name: warforge-orchestrator
description: "Warforge 에이전트 팀 오케스트레이터. 카드 추가, 시스템 변경, 크로스 도메인 작업 등 여러 도메인에 걸치는 작업을 에이전트 팀으로 분해·조율·검증한다."
when-to-use: "작업이 설계+시뮬+엔진+QA 중 2개 이상 도메인에 걸칠 때. 단일 도메인 작업(문서만 수정, 코드만 수정)에는 사용하지 않는다."
---

# Warforge Orchestrator

여러 도메인에 걸치는 작업을 에이전트 팀으로 조율한다.

## 팀 구성

| 에이전트 | 파일 | 도메인 |
|---------|------|--------|
| designer | .claude/agents/designer.md | DESIGN.md + docs/design/ |
| balancer | .claude/agents/balancer.md | sim/ 밸런스 검증 |
| engineer | .claude/agents/engineer.md | godot/ 구현 |
| qa | .claude/agents/qa.md | Sprint Contract 검증 |

## 아키텍처: Fan-out/Fan-in + Producer-Reviewer

### Fan-out/Fan-in (크로스 도메인 작업)

```
사용자 요청
  → [Phase 1] designer: 설계 문서 작성/수정
  → [Phase 2] Fan-out (병렬):
      balancer: sim/ 수치 반영 + 밸런스 검증
      engineer: godot/ 구현 (설계 문서 Read 필수)
  → [Phase 3] Fan-in:
      qa: Sprint Contract 전항 검증
  → [Phase 4] 결과 통합 + 사용자 보고
```

### Producer-Reviewer (카드 설계)

```
designer: 카드 설계 (card-designer 스킬 활용)
  → qa: Evaluator 서브에이전트 검증 (Tier 2)
  → 미통과 시 designer 수정 → qa 재검증 (최대 3회)
  → 3회 초과 미해결 → Tier 3 (/multi-review) 에스컬레이션
```

## 작업 유형별 실행 경로

### A. 신규 카드 추가

1. designer → 카드 스펙 설계 + docs/design/cards-{theme}.md 업데이트
2. balancer → sim/data/card_pool.py에 카드 추가 + `sim -n 50 --seed 42`
3. engineer → godot/core/data/card_db.gd에 카드 추가 (설계 문서 대조)
4. qa → Sprint Contract "신규 카드 설계" + "카드/수치 변경" + "Godot 카드 데이터" 검증

### B. 시스템/수치 변경

1. designer → DESIGN.md 확정 테이블 수정 (사용자 확인) + 영향 맵 동기화
2. balancer → sim 수치 반영 + 4프리셋 검증
3. engineer → godot 반영 (DESIGN.md 상수 대조)
4. qa → Sprint Contract "문서 변경" + "시뮬레이터 코드" 검증

### C. 밸런스 조정 (수치만)

1. balancer → 승률 분석 + 수치 조정 제안
2. designer → 설계 문서 반영
3. qa → Sprint Contract "카드/수치 변경" 검증

## 에러 핸들링

- 에이전트 간 불일치 발견 → 작업 중단 + 불일치 보고 + designer에게 판정 요청
- qa Sprint Contract fail → 실패 항목의 담당 에이전트에게 수정 요청 (최대 2회)
- 2회 수정 후에도 fail → 사용자 에스컬레이션

## 모델 배정 원칙

에이전트 spawn 시 작업 특성에 따라 모델을 선택한다.
각 에이전트는 내부적으로 delegation-protocol.md에 따라 haiku/sonnet 서브에이전트를 추가 위임할 수 있다.

| 에이전트 | 기본 모델 | 근거 |
|---------|----------|------|
| designer | opus | 창의적 설계 판단 |
| balancer | opus | 밸런스 분석·원인 추론 |
| engineer | sonnet | 설계 스펙 → 코드 변환 (스펙 명확 시) |
| qa | sonnet | 체크리스트 기반 검증 위주 |

**오버라이드 조건:**
- engineer가 설계 모호성 해결이 필요한 경우 → opus
- qa가 Tier 3 에스컬레이션 판단이 필요한 경우 → opus
- 단순 코드 생성(템플릿 기반) → sonnet으로 충분

## 중간 산출물 보존

작업 중간 결과는 삭제하지 않는다. 감사 추적을 위해 보존.
- 시뮬레이션 로그: 터미널 출력으로 보존
- 설계 변경: git diff로 추적
- Evaluator 결과: qa 에이전트 출력에 포함
