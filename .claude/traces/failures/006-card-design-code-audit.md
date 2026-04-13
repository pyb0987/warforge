---
date: "2026-04-12"
classification: "제약 미비"
escalated_to: none
search_set_id: "SS-006"
resolved: false
---

# Failure: 카드 설계↔코드 전수조사 — 체계적 불일치 발견

## Observation

55장 전체 카드 풀 대상 설계 문서(docs/design/cards-*.md) ↔ 코드(card_db.gd + theme systems) 정합성 전수조사 수행.
35장 정합, 20장에서 불일치 발견. 불일치는 4가지 유형으로 분류됨.

## 불일치 항목 전체 목록

### 🟡 경미 (수치/플래그 오차) — 4건

| # | 카드 ID | 테마 | 내용 | 파일 |
|---|---------|------|------|------|
| 1 | `ne_dim_merchant` | 중립 | 설계: 판매 시 +1골드 → 코드: shop.gd에 판매 보너스 로직 없음 (별도 시스템 필요) | card_db.gd, shop.gd |
| 2 | `sp_circulator` | 스팀펑크 | 설계: output_layer 없음 → 코드: output_layer 존재 여부 미확인 | card_db.gd |
| 3 | `sp_charger` | 스팀펑크 | 설계: 이벤트 미방출(output_layer 없음) → 코드: counter_system이 이벤트 방출 가능 | steampunk_system.gd |
| 4 | `pr_sporecloud` | 포식종 | ★2/★3 수치(범위/지속시간) 설계↔코드 미세 차이 가능 | card_db.gd, predator_system.gd |

### 🟠 max_activations 누락 — 5건

| # | 카드 ID | 테마 | 설계 상한 | 코드 현재값 | 파일 |
|---|---------|------|-----------|------------|------|
| 1 | `pr_molt` | 포식종 | 2회 | -1 (무제한) | card_db.gd |
| 2 | `pr_harvest` | 포식종 | 3회 | -1 (무제한) | card_db.gd |
| 3 | `pr_carapace` | 포식종 | 2회 | -1 (무제한) | card_db.gd |
| 4 | `ml_academy` | 군대 | 2회 | -1 (무제한) | card_db.gd |
| 5 | `ml_conscript` | 군대 | 1회 | -1 (무제한) | card_db.gd |

### 🔴 sp_charger 이벤트 방출 위반 — 1건

설계: counter_system은 카운터만 증가, 이벤트 방출하지 않음 (트리거 체인 비참여).
코드: steampunk_system.gd의 counter 처리가 이벤트를 방출할 수 있는 구조.
→ 설계 의도와 코드 동작 불일치. 체인 무한루프 위험 잠재.

### 🔴 ★2/★3 고급 효과 미구현 — ~20건

주로 드루이드/포식종/군대 테마. effects=[]이고 theme_system에서 star_level match로 구현해야 하나, ★2/★3 분기가 없거나 ★1과 동일.

**드루이드** (cards-druid.md):
- `dr_bloom` ★2/★3: 진화 효과 강화 미구현
- `dr_symbiosis` ★2/★3: 공생 보너스 강화 미구현
- `dr_guardian` ★2/★3: 수호 효과 강화 미구현
- `dr_overgrowth` ★3: 폭발적 성장 효과 미구현
- `dr_ancient` ★2/★3: 고대 존재 효과 미구현
- `dr_harmony` ★2/★3: 조화 보너스 미구현

**포식종** (cards-predator.md):
- `pr_devour` ★2/★3: 포식 효과 강화 미구현
- `pr_evolution` ★2/★3: 진화 분기 미구현
- `pr_alpha` ★3: 우두머리 특수 효과 미구현
- `pr_swarm` ★2/★3: 군체 확장 미구현
- `pr_toxin` ★2/★3: 독소 강화 미구현

**군대** (cards-military.md):
- `ml_tactics` ★2/★3: 전술 효과 강화 미구현
- `ml_supply` ★2/★3: 보급 보너스 미구현
- `ml_fortify` ★2/★3: 요새화 효과 미구현
- `ml_elite` ★3: 정예 특수 효과 미구현
- `ml_command` ★2/★3: 지휘 버프 미구현

(정확한 카드 ID는 각 theme_system.gd와 cards-*.md 대조 필요. 위는 전수조사 시점 기준.)

## Root Cause

1. **구현 순서 문제**: 중립/스팀펑크를 먼저 구현 → 드루이드/포식종/군대는 기본 틀만 (effects=[], theme_system 기본 분기)
2. **★2/★3 설계가 후행**: 설계 문서에 ★2/★3 효과가 추가된 시점과 코드 구현 시점의 괴리
3. **검증 자동화 부재**: 설계 문서의 효과 수와 코드의 효과 수를 자동 비교하는 메커니즘 없음
4. **max_activations**: 설계 문서에 상한이 명시되어 있으나, 초기 구현 시 -1(무제한)로 일괄 설정 후 미갱신

## Fix (planned)

### 즉시 수정 가능 (코드만)
- [ ] max_activations 5건: card_db.gd에서 값 변경
- [ ] 🟡 경미 4건: 개별 확인 후 수정

### 시스템 작업 필요
- [ ] 🔴 sp_charger 이벤트 방출: steampunk_system.gd 수정
- [ ] 🔴 ★2/★3 미구현 ~20건: theme_system별 star_level 분기 추가

### 구조적 개선 (Prevention)
- [ ] 하네스: 설계↔코드 정합성 자동 검증 도구 도입 검토
- [ ] 코드: 카드 효과 factory/preset 패턴 도입 검토

## Prevention

**논의 필요** — 두 가지 구조적 개선 방향:
1. 하네스 관점: 설계→코드 반영을 보장하는 자동화/프로세스
2. 코드 관점: 효과 조합의 재사용성을 높이는 아키텍처 (factory/preset)

→ 사용자와 논의 후 결정, evolution trace로 기록 예정.
