# 핸드오프 — C: T4/T5 특수 효과 수치 상향

**작성일**: 2026-04-20
**선행 세션**: Phase 1 autoresearch + 플레이테스트 피드백 1회차
**선행 의존**: Session A (base CP 재조정) + Session B (업그레이드 너프) 이후 가장 정확

## 배경

플레이테스트 결과 **T4/T5 카드가 T1 ★3 + 업그레이드 빌드를 못 이김**:
- "유틸성은 좋을 수 있어도 결국 쌓인 유닛 물량을 이길 수 없음"
- "카드 교체가 잘 일어나지 않음"

원인:
1. T4 base CP 평균 < T1 평균 (575 < 658) — Session A에서 해결 예정
2. **T4/T5 특수 효과 수치가 복리 T1 generator 이득을 상쇄하지 못함**

## 현 T4/T5 카드 목록 + 효과 (간략)

### T4 (8장)
| ID | 이름 | 주 효과 (★1) | 문제점 (추정) |
|---|---|---|---|
| sp_warmachine | 전쟁 기계 | persistent range scaling | 기기수 8+ 조건 빡빡 |
| sp_charger | 태엽 과급기 | manufacture 이벤트 → 테라진 + enhance | 이벤트 기반, 드물게 발동 |
| ne_dim_merchant | 차원 행상인 | 특수 상인 | 자원 교환 효과 제한 |
| ne_awakening | 고대의 각성 | tenure 기반 각성 | 장기 전용 |
| dr_wrath | 태고의 분노 | 🌳 비례 자기 ATK 대폭 | 🌳 확보 전제 |
| dr_wt_root | 세계수의 뿌리 | 🌳 분배 + 전체 성장 | 드루이드 전용 |
| pr_parasite | 기생 진화 | 유닛 진화 | 포식종 전용 |
| pr_apex_hunt | 포식자의 사냥 | 사냥 효과 | base CP 360 (매우 낮음) |
| ml_special_ops | 특수 작전대 | 치명타 | 효과적이나 기본 약함 |
| ml_factory | 군수 공장 | 카운터 → 전역 ATK 버프 | 느린 빌드업 |

### T5 (4장)
| ID | 이름 | 주 효과 | 문제점 |
|---|---|---|---|
| sp_arsenal | 제국 병기창 | 판매 시 흡수 | **판매 행위 자체 드물어 무효** |
| dr_world | 세계수 | 전체 드루이드 곱연산 성장 | 유닛 cap 제약 |
| pr_transcend | 군체 초월 | 초월 효과 | base CP 473 낮음 |
| ml_command | 통합 사령부 | 전체 군대 훈련 + 부활 | 효과 풍부함 |

## 목표

T4/T5 카드가 **T1 ★3 + 업그레이드 + ★합성 보너스**를 이길 수 있도록:

1. **특수 효과 수치 상향** (spawn 수, enhance %, 버프 % 등)
2. **트리거 확대** — 너무 제한적 조건 완화
3. **T5는 "게임 체인저" 수준**으로 강화 (사용자 feedback: `feedback_high_tier_power.md`)
4. **sp_arsenal 전면 재설계** (판매 트리거는 현 게임 흐름과 부조화)

## 예상 작업 범위

### 1. T5 전면 재검토 (4장)
- **sp_arsenal 트리거 대체**: 판매 → PERSISTENT or 다른 자연 트리거
  - 예: "라운드 종료: 이 카드 사망한 유닛 수 × 5% 영구 ATK" 같은 자연 누적
- **pr_transcend 기본 전력 상향**: base CP 473 → 1500+
- **dr_world 곱연산 강화** 검토
- **ml_command 기본 유지 + 버프 수치 ★별 상향**

### 2. T4 효과 수치 상향 (10장)
각 카드의 효과를 **기본 전력의 1.5-2배 추가 기여** 수준으로:
- spawn 카드: spawn count 2배 (예: 1 → 2, 2 → 3)
- enhance 카드: % 1.5배 (예: +5% → +8%)
- 트리거 기반: 조건 완화 or 효과 배율 상향

### 3. 수치 산정 방법
- Session B의 framework로 T1 ★3 + 업그레이드 최종 CP 추정
- T4/T5의 "기대 CP" = base + 효과 누적
- 비교 후 gap 메우기

### 4. 유닛 구성 재조정 (comp 수정도 가능)
- Session A에서 base CP 변경 시 함께 검토
- T4/T5에 강한 유닛 추가 or 약한 유닛 제거

## 참조 문서

- `docs/design/themes.md` — 테마별 정체성
- `docs/design/cards-{steampunk,druid,predator,military,neutral}.md` — 카드별 설계 의도
- **feedback memory**: [feedback_high_tier_power.md](~/.claude/projects/-Users-fainders-personal-chain-army/memory/feedback_high_tier_power.md)
  > "T4/T5 ★3은 게임 판도를 바꿀 정도로 강력해야 함. 과잉 우려보다 '사기' 쾌감 우선."

## 검증 기준

- T4/T5 카드가 plausible 빌드에서 **교체 유인 있음** (플레이테스트)
- sim: card_coverage 0.136 → **0.50+** (T4/T5 등장 빈도 상승)
- sim: mean WR target 5-10% 유지 (너무 쉽게 만들지 말 것)
- soft_steampunk 전략 회복 (현재 0/60) — sp_arsenal 재설계 효과

## 주의사항

### Session A + B 완료 후가 효율적
- A: base CP rebalance로 T4/T5 기본값 상향
- B: 업그레이드 너프로 상대적 경쟁력 확보
- C: A+B 기반으로 **미세 조정** (효과 수치 상향)

A/B 없이 C 단독 진행 시 T4/T5만 과도 buff → 사기 카드 양산 위험.

### 기존 카드 설계 (YAML) 수정 규칙
- DESIGN.md 변경 영향 맵 확인
- docs/design/cards-*.md 동기화
- 각 카드 재설계 시 episodes/YYYY-MM-DD-{card}.md 기록

## Next entry point

1. Session A + B 완료 확인 (또는 병행)
2. Session B framework로 현 T4/T5 카드 정량 평가
3. gap 큰 카드부터 재설계 착수
4. sp_arsenal 최우선 (판매 트리거 전면 교체 필요)
5. YAML 수정 → codegen → 테스트 → sim 검증
