# 2026-04-28 — SELL UI flow ESC cancel 비대칭 의도화

## 배경

`feat(ne_awakening)` 커밋 e60703a + `fix(sell-ui)` 커밋 a3bb0ca에서 ne_masquerade / ne_awakening 판매 시 사용자 카드 선택 UI flow를 활성화. 이 과정에서 ESC cancel 처리에 대한 design 결정이 필요했음.

## 문제

`game_state.sell_card()`는 atomic 단위로 다음 3가지를 동시 처리:
1. 환불 골드 지급
2. 카드 보드/벤치에서 제거
3. SELL trigger 효과 발동

ne_masquerade / ne_awakening은 효과가 "보드 카드 1장 선택"이므로 UI popup 후 사용자 입력 대기. 이 시점에 ESC 키를 누르면 어떻게 처리할 것인가?

## 검토된 옵션

| 옵션 | 동작 | 장단 |
|-----|------|------|
| **A) 효과 무시, 환불/제거 유지** | 부분 취소 (효과만 ✗, 환불/카드 제거 ✓) | 단순. 사용자 손해 없음 (환불 받음). 시스템 비대칭이지만 사용자 친화적 |
| B) 환불 회수, 카드 제거 유지 | 효과+환불 ✗, 카드 제거 ✓ | 사용자 손해 발생 (환불 회수). 카드 복원 안 하면 비합리적 UX |
| C) 카드+환불 모두 복원 | 완전 sell 취소 | 구현 복잡 (sell signal side effect 회복, 보드/벤치 슬롯 재할당, card_pool 차감 회수) |

## 결정: 옵션 A 채택

**근거**:
1. **사용자 손해 없음**: ESC = 의도적 효과 포기. 환불은 그대로 받음 → 손해 X
2. **시스템 비대칭이지만 의도적**: sell trigger 묶음을 부분 취소하는 것은 GUI 게임에서 흔한 UX 패턴 (예: 다른 카드 게임도 "효과 발동 취소"를 환불 회수와 분리)
3. **단순성**: 별도 rollback 메커니즘 불필요. signal disconnect + state 정리만으로 충분

## 비대칭 명시화

`game_manager._on_sell_target_cancelled` 핸들러에 design intent 주석 추가:
- 옵션 A/B/C 검토 결과 명시
- 향후 "환불 회수 미구현 = 버그" 리포트 발생 시 이 episode 참조 가능

## 영향 범위

- ne_masquerade SELL: 환불 + 카드 제거 ✓, theme transform ✗ (ESC 시)
- ne_awakening SELL: 환불 + 카드 제거 ✓, units/upgrade transfer ✗ (ESC 시)

## 미래 변경 시 주의

옵션 A를 변경하려면 (B 또는 C로 이동):
1. sold_card 인스턴스 보존 메커니즘 추가 (현재 _pending_sell_select에 sell_result 저장하나, sold_card 자체는 state에서 제거됨)
2. card_pool 차감 회수 / 보드/벤치 슬롯 재할당 로직
3. sim 동등 처리 (현재 sim은 ESC 없이 자동 target — 차이 명확히)

이는 단일 책임 위반 가능 (sell이 commit이자 reversible)이라 신중히.

## 참조

- 커밋: a3bb0ca (fix(sell-ui))
- Multi-review 2차 (Convergence Critic): "환불 회수 미적용이 명시적 허용으로 코드화" 우려
- 사용자 결정: A 채택 (2026-04-28)
