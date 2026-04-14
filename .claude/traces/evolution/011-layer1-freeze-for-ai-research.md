---
iteration: 11
date: 2026-04-13
type: structural
verdict: pending
files_changed:
  - godot/sim/best_genome.json
  - godot/sim/ai_research/ai_best_genome.json
  - .claude/settings.local.json
refs:
  - ".claude/traces/evolution/010-tier0-protect-files.md"
  - "harness-methodology.md § P3, Additive Modification"
---

## Problem

Layer 1 (게임 밸런스) ↔ Layer 2 (AI 품질) 순환 의존.
- Layer 1이 "못하는 AI"에 맞춰 밸런스 왜곡 (R12-15 CP 8.0, income 7/8/9)
- Layer 2가 "왜곡된 밸런스"에 맞춰 AI 최적화 → 로컬 옵티마에 갇힘
- AI 승률: druid/steampunk 0%, military 30%, 나머지 ≤10%
- 머지율 1.33 (거의 전부 ★1) — 후반 전투력 부족의 근본 원인

## Decision

순환 의존 해소를 위해 Layer 1을 **수동 고정값(create_default)**으로 핀.

| 파라미터 | 이전 best_genome | 고정값 (default) | 근거 |
|---------|-----------------|-----------------|------|
| CP curve R1-5 | 2.129 flat | 1.0→1.8 | emotional arc R1-3 쉬움 복원 |
| CP curve R12-15 | 8.0 flat | 3.6→4.5 | cliff function 제거, gradient 복원 |
| base_income | 7/8/9 | 5/6/7 | DESIGN.md 원래 의도 |
| levelup Lv3 | 9g | 7g | 레벨업 접근성 정상화 |
| boss_scaling | 1.28/1.46 | 1.3/1.3 | 기본값 |
| activation_caps | sp_interest:7, ml_conscript:2 | {} (CardDB default) | 카드 설계 기본값 사용 |

## Change

1. `best_genome.json` → `Genome.create_default()` 값으로 교체 (ai_params 제외)
2. `ai_best_genome.json` → 동일 Layer 1 기본값 + DEFAULT_AI_PARAMS 전체 (22개, 테마 상태 5개 포함)
3. `best_genome.json`을 protect-files 훅에 추가 (Layer 2 연구 중 실수 방지)
4. `--init`으로 baseline 재측정

## 변경 전략

**Structural** — outer loop 순환 의존을 끊는 구조 변경 (P3 복원).
한쪽을 상수로 만들어 다른 쪽에 학습 신호를 줌.

## 검증 기대치

- 기본 밸런스에서 AI baseline 측정 → 이후 Layer 2 autoresearch의 gradient 확인
- AI가 개선되면 (승률 상승, 머지율 증가) 전략이 유효한 것
- Layer 2 수렴 후 Layer 1 재개 가능

## Open question

- Layer 2 수렴 후 Layer 1을 다시 돌릴 때, 어느 정도 수준에서 재개할 것인가?
- activation_caps를 CardDB 기본값에 맡겨도 되는가? (검증 필요)
