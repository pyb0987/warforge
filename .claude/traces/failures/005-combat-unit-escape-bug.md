---
date: "2026-04-09"
classification: "정보 부족 + 제약 미비"
escalated_to: "godot/combat/combat_engine.gd (max_search 확장 + push 누적 cap)"
search_set_id: ""
resolved: false
resolved_date: ""
---

## Failure: 전투 중 유닛이 적 진영을 관통해 맵 반대편으로 이탈

### Observation
사용자 보고: "#6 전투 중 유닛 맵 밖 이탈 버그. 적 유닛이 남았을때도 flow대로 반대편으로 움직임. 특히 대규모 전투에서 근접유닛이 적에게 달라붙어 더 이상 달라붙을 자리가 없을 때."

### Root Cause (두 가지가 결합)

**원인 1 — 좁은 타겟 탐색 반경**:
`_update_unit`의 `max_search := maxf(attack_range[i], RANGE_SCALE * 4.0)` = 최소 128px.
- 근접 유닛은 128px 밖의 적을 보지 못함 → flow field fallback
- flow field는 centroid 기반이라 "지금 인접한 적"이 아니라 "평균 위치"를 쫓음
- 한쪽 측면 전투가 기울면 centroid가 이동하여 유닛이 현재 교전 지점을 지나쳐 행진

**원인 2 — 적 유닛과의 충돌 push (대규모 전투에서 본질적 원인)**:
`_resolve_collisions`가 같은 팀/적 팀 구분 없이 모든 겹치는 쌍에 대해 push 적용.
- 빽빽한 근접전에서 push 누적이 진형을 관통시킴
- 한 유닛이 적 라인 너머로 밀려나면, 다음 tick의 nearest enemy는 본진 방향
- 그 유닛은 본진 쪽으로 다시 행진하며 "맵 이탈" 시각 효과 발생

### Fix (Additive)
1. **Additive (적용됨)**: `max_search`를 `BATTLEFIELD_W + BATTLEFIELD_H` (배틀필드 대각선 이상)로 확장.
   적이 1기라도 살아있으면 항상 발견. flow fallback은 "적 0명"(승리 직전)에만 도달하며 이 경우 제자리 대기.
2. ~~**Subtractive (OBS-027 회귀로 폐기)**: 적-아군 push 스킵 → 겹침 발생~~
3. **Additive (2026-04-11)**: push 누적 cap. push를 즉시 적용 대신 버퍼에 누적 후
   `MAX_PUSH = SEPARATION_DIST(14px)`로 cap. 적-아군 분리 유지(OBS-027) + 다중 누적 관통 차단(OBS-054).

### Verification
- GUT: 754/754 통과 (회귀 없음)
- 사용자 플레이 검증 필요

### Lessons
- "맵 이탈" 같은 시각 버그는 클램프(0~1000)가 걸려있어도 발생 가능 — *논리적 위치*가 적 진영 너머로 이동하면 화면상으론 본진/반대편으로 보임
- 충돌 분리는 *같은 팀 진형 유지*가 목적이지 *적과의 거리 강제*가 아님. RTS 표준 패턴
- 단, 적-아군 push를 완전 제거하면 겹침 발생(OBS-027). push 자체가 아니라 누적량이 문제 → cap으로 해결
- centroid 기반 flow field는 "타겟이 없을 때"만 fallback이어야 함. 평상시 동작에 의존하면 평균치 추격 버그
