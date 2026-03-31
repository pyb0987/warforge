# Backlog — 미구현/후속 작업

## 완료 항목
- [x] ★2/★3 전용 카드 템플릿 등록 (T4/T5 14장 × ★2/★3 = 28 엔트리, card_db.gd)
- [x] 업그레이드 아이템 26종 설계 (upgrades-items.md)
- [x] 보스 보상 27개 설계 (boss-rewards.md)
- [x] 커맨더 7종 상세 설계 + 밸런스 조정 (commanders.md)
- [x] Sprint 11: 테마 시스템 4종 구현 (steampunk/druid/predator/military _system.gd)

---

## Sprint 11: 테마 시스템 구현 ✅

> 목표: T3+ 카드의 복잡한 효과를 처리하는 테마별 시스템 구현. 이것 없으면 card_db.gd의 effects=[] 카드들이 동작하지 않음.

| # | 항목 | 파일 | 설명 |
|---|------|------|------|
| 1 | steampunk_system.gd | godot/core/ | sp_warmachine(#화기 사거리 스케일링 ★1/★2/★3), sp_charger(제조카운터→테라진+개량 ★1/★2/★3), sp_arsenal(ON_SELL 흡수 ★1/★2/★3) |
| 2 | druid_system.gd 확장 | godot/core/ | ★2/★3 분기: dr_wrath(태고의분노 곱연산), dr_wt_root(세계수뿌리 🌳임계), dr_world(세계수 배율) |
| 3 | predator_system.gd | godot/core/ | 부화/변태 기본 + ★2/★3: pr_parasite(기생진화), pr_apex_hunt(포식자사냥), pr_transcend(군체초월) |
| 4 | military_system.gd | godot/core/ | 계급/훈련/징집 + ★2/★3: ml_special_ops(리더생성), ml_factory(카운터→테라진), ml_command(부활) |

Done 조건: 각 시스템의 ★1 효과가 체인 엔진에서 발동 확인. ★2/★3 분기 로직 존재.

---

## Sprint 12: 업그레이드 + 경제 시스템

> 목표: 테라진 사용처 구현. 업그레이드 부착/조회/효과 적용.

| # | 항목 | 파일 | 설명 |
|---|------|------|------|
| 1 | 업그레이드 슬롯 시스템 | godot/core/ | 카드당 5슬롯, 테라진 비용, 부착/제거 로직 |
| 2 | 업그레이드 아이템 26종 데이터 | godot/core/data/ | upgrade_db.gd — 커먼11/레어9/에픽6 등록 |
| 3 | 업그레이드 상점 UI | godot/scenes/build/ | 테라진으로 구매, 카드에 부착하는 UI |
| 4 | ★2 합성 시 레어 3택1 UI | godot/scenes/ui/ | 합성 완료 → 레어 업그레이드 3장 표시 → 1장 선택 → 부착 |
| 5 | ★3 합성 시 에픽 3택1 UI | godot/scenes/ui/ | 동일 흐름, 에픽 풀에서 |
| 6 | 업그레이드 전투 적용 | godot/combat/ | combat_unit 생성 시 업그레이드 효과 반영 (DEF, 관통, 스플래시 등) |

Done 조건: 커먼 업그레이드 구매→부착→전투 반영 확인. ★2 합성→레어 선택 확인.

---

## Sprint 13: 보스 보상 + 커맨더 시스템

> 목표: 런의 핵심 선택지(커맨더, 보스 보상) 구현.

| # | 항목 | 파일 | 설명 |
|---|------|------|------|
| 1 | 보스 보상 27개 구현 | godot/core/data/ | boss_reward_db.gd — R4/R8/R12 각 9개 |
| 2 | 보스 보상 선택 UI | godot/scenes/ui/ | 보스 격파 → 4장 표시 → 1장 선택 |
| 3 | 보스 보상 효과 적용 | godot/core/ | ★승급, 골드/테라진 즉시, 영구 패시브, 필드확장 등 |
| 4 | 커맨더 7종 구현 | godot/core/data/ | commander_db.gd — 시작보너스 + 패시브 |
| 5 | 커맨더 선택 UI | godot/scenes/ | 런 시작 시 커맨더 2~7종 표시 → 선택 |
| 6 | 커맨더 패시브 적용 | godot/core/ | game_state에 커맨더 효과 연결 |

Done 조건: 커맨더 선택 → 패시브 적용 확인. 보스 R4 격파 → 보상 선택 → 효과 적용 확인.

---

## 후순위 (Phase B/C)

- [ ] 적 파워 곡선 수치 확정 (플레이테스트 기반)
- [ ] 경제 수치 미세조정
- [ ] 부적 12종 설계 + 구현
- [ ] 난이도 8단계 상세
- [ ] 튜토리얼/온보딩
- [ ] 성장 체인 시각 연출
- [ ] 합성 시각 연출 (파티클, 카드 합체 애니메이션)
- [ ] T1~T3 ★2/★3 카드 템플릿 등록 (card_db.gd, 40장 잔여)
