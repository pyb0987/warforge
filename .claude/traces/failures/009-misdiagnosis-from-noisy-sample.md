---
date: "2026-04-26"
classification: "정보 부족"
escalated_to: null
search_set_id: null
resolved: false
resolved_date: null
escalation_date: null
promoted_to_feedback: null
---

## Failure: ±15%p 노이즈 표본의 단일 셀로 "약체" 단정 → 잘못된 reweight

### Observation

`preset_parity_runner.gd` runs=20 결과를 보고 다음 진단:

> "military preset이 모든 tier에서 약체. T1/T3/T5 모두 약함."

근거로 제시한 셀:
- T1 military row: `predator 0%, druid 0%, steampunk 0%` (60% self는 무관)
- T3 military row: `predator 0%, druid 15%, steampunk 0%`
- T5 military row: `predator 60%, druid 85%, steampunk 30%`

이를 바탕으로 가설 "military reweight (글래스캐넌 비중↓, HP-balanced↑)" 적용. 결과:

| tier | military off-diag mean | 결과 |
|------|------------------------|------|
| T1 | 0% → 23% | 개선 |
| T3 | 5% → 25% | 개선 |
| T5 | **58% → 15%** | **회귀** |

T5 결과가 가설과 정반대 → 롤백.

### Root Cause

세 가지 실패 겹침:

1. **T5 셀 [60/85/30] 오해석**: off-diag mean 58%는 "30-70% 목표" 범위에 들어옴. 그런데 첫 진단에서 "off range [0%, 100%]"의 max/min 만 보고 "전체 약체"로 묶음. 행 단위 평균을 보지 않음.

2. **표본 크기 무시**: runs=20 → 95% CI ≈ ±22%p. 단일 셀 0%/100% 같은 극값도 노이즈일 수 있음. 그럼에도 "결정적 약체" 라벨링.

3. **선택적 evidence 사용**: T5의 60/85/30은 약체 가설과 충돌하는 evidence였으나 "더 분산되지만 여전히 0%/90% cell 존재"로 회피. 가설 부정 신호를 약화시킴 (confirmation bias).

### Effect

- 1 iteration 낭비 (reweight + 재측정 + 롤백)
- 2개 SSoT 파일 (godot/sim + scripts/) 동시 수정 → 동시 롤백
- 다행히 commit 전 롤백이라 하네스 부담 없음

### Lessons

- 노이즈 ±15-20%p 표본에서 단일 셀로 단정 금지. 행/열 평균 + 전체 분포로 판단.
- 가설을 부정하는 evidence를 "약화" 처리하지 말 것. 동등하게 가중.
- runs 늘리기(100+) vs. 가설 약화 — 둘 중 하나 선택 후 진행.

### What Would Have Prevented

- 첫 진단 시 행 평균 계산: `T5 military row mean = (60+85+30)/3 = 58%` → "T5는 정상" 즉시 보였을 것
- 가설을 "**모든** tier에서 약체"가 아닌 "**T1/T3에서** 약체"로 좁혔을 것
- reweight도 그에 맞춰 더 보수적이거나 tier-aware 접근 검토했을 것

### Status

1회째 발생. Memory 승격은 재발 시 (escalation policy per CLAUDE.md). search-set 추가는 패턴이 단순하지 않아 보류 — "노이즈 인지하라"는 자동 검증 어려움.
