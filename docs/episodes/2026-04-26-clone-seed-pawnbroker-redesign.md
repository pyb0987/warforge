# 분열체(ne_clone_seed) 폐기 → 전당포(ne_pawnbroker) 신설

## 배경

T1 중립 분열체 카드의 자기 복제 메커니즘이 auto-merge 시스템과
근본적 모순을 일으켜 폐기 결정.

## 문제

분열체는 RS에 자기 ★1 복사본을 벤치에 추가 (`clone_self_to_bench`).
★2/★3에서도 ★1 클론 효과 유지 + 자기 강화 (ATK +2%/+4% 영구).

`game_state.try_merge()` 가 상점 구매 시점에만 호출됨. 클론으로 추가된
★1 카드들은 자동 합성 안 됨. 사용자 관점에서:

> "분열체가 효과로 분열체를 생성할 때 3기 이상이 되면 ★1이 ★2로
> 합쳐지지 않는 문제."

자동 합성을 켜면 더 큰 문제: ★1 1장 구매 → 무한 ★3 생성기 (★2/★3
도 클론 유지하므로). 무한 스노우볼 → 어떤 밸런스로도 못 막음.

> 자기 복제 카드 + auto-merge 시스템은 본질적 모순.
> TFT/Hearthstone BG도 자기 복제 유닛은 거의 안 만들거나 매우 좁은 조건만 허용.

→ **카드 자체의 디자인 미스로 판별** (commit 8ea80de 분열체 도입 시
auto-merge 충돌 미검토).

## 대안 비교

폐기 후 슬롯(T1 중립, comp ne_scrap×2)을 채울 후보 4안:

| 안 | 정체성 | 채택 |
|----|-------|------|
| A. 매턴 골드 (+1g/R) | "초기 골드 책임" | ❌ ne_envoy(T2 +2g/R) 약화판 |
| B. 임계점 (보드 4장+ 시 ATK +N%) | "꽉 찬 보드 보상" | ❌ "초기" 컨셉 미달 |
| C. 방어막 디스펜서 | "초반 생존" | ❌ 시각적 만족감 약함 |
| D. 자가 성장 단일 카드 | "오래 들고 있을수록 강함" | ❌ 드루이드와 정체성 충돌 |

→ 모두 다른 카드와 일부 겹침. 사용자 재검토 후 **다른 빈 칸 영역** 선택:

| 빈 칸 후보 | 정체성 | 채택 |
|-----------|-------|------|
| 리롤 보조 (T1) | "리롤 횟수 공급" | ✓ |
| 보드 임계점 | 후기 한정 | 보류 |
| 자가 성장 | 드루이드 충돌 | 보류 |

리롤 메커니즘은 T1에 비어있음 (ne_scrapyard T2는 폐기 조건부).

## 결정: 전당포 (ne_pawnbroker)

```yaml
ne_pawnbroker:
  name: 전당포
  tier: 1
  comp: [ne_scrap×2]
  tags: [neutral, reroll]
  impl: theme_system
  ★1: REROLL trigger, 50% 확률 levelup_discount -1
  ★2: REROLL trigger, 50% 확률 levelup_discount -2
  ★3: REROLL trigger, 100% levelup_discount -2
       + RS trigger, free_reroll +1 (max 1/R)
```

기존 자연 감가(매 정산 -1g) 위에 추가 인하. 가격 0이 최저
(`apply_levelup_discount` 의 `maxi(_, 0)`).

### ★ 진화 검증

- **★1 → ★2**: amount 1→2 (×2). "더 잘한다" ✓
- **★2 → ★3**: chance 50→100% + RS 자기-트리거 free_reroll 공급.
  "다른 차원" ✓ (RS 자동 발동은 ★2에 없는 새 메커니즘)
- 합성 유인:
  - ★1×3 = 평균 1.5g/리롤 가치
  - ★2×1 = 평균 1g/리롤 + 슬롯 2칸 절약 → 자원 카드 일반 패턴
  - ★2×3 = 평균 3g/리롤
  - ★3×1 = 확정 2g/리롤 + RS reroll(2g 가치) + 결정성 → 비등 + 매력 우위

### 다른 카드와의 차별

- ne_envoy (T2 +2/3/4 g/R): 매턴 골드 — 무조건 보상
- ne_pawnbroker (T1 -X g 가격 인하): 리롤할 때 발동 — 능동적 사용 보상
- 트리거 시점이 RS vs REROLL로 명확히 다름

## 구현 변경

### 신규
- `data/cards/neutral.yaml`: `ne_pawnbroker` 블록 추가 (분열체 자리)
- `scripts/card_desc_gen.py`: `desc_levelup_discount`
- `godot/core/chain_engine.gd::_execute_actions`: `levelup_discount` action case (RNG chance 처리)
- `godot/core/chain_engine.gd::process_reroll_triggers`: result dict 에 `levelup_discount` 누적
- `godot/core/chain_engine.gd::run_growth_chain`: theme_system result 의 `free_rerolls` 신호 처리
- `godot/core/neutral_system.gd`: `_pawnbroker_rs` (★3 RS free_reroll 신호 발신)
- `godot/scripts/game/game_manager.gd::_apply_reroll_levelup_discount` 헬퍼
- `godot/core/game_state.gd::apply_levelup_discount(amount: int = 1)` — 매개변수 추가 (default 1로 후방 호환)
- `godot/tests/test_pawnbroker_reroll.gd` (신규 8 테스트)

### 제거
- `godot/core/neutral_system.gd`: `_clone_seed_rs`, `_clone_seed_sell`
- `godot/core/chain_engine.gd::run_growth_chain`: `clones_to_bench` 누적 코드
- `godot/scripts/game/game_manager.gd`: clone 처리 블록
- `godot/sim/headless_runner.gd`: clones_to_bench + transfer_upgrade 처리
- `data/cards/neutral.yaml`: `ne_clone_seed`
- `godot/tests/test_neutral_system.gd`: 5 ne_clone_seed 테스트 → 3 ne_pawnbroker 테스트로 교체

### 미손상 (의도된 dead code, 다른 카드 미사용 시 future cleanup)
- `card_desc_gen.py::desc_clone_self_to_bench`, `desc_transfer_upgrade` — 매핑에서만 제거. 함수 본체 삭제는 별 작업.

## Evaluator 결과

haiku Evaluator: **MIXED** — 2개 CAUTION:

1. **E6 지속 범위 텍스트**: levelup_discount 텍스트가 "리롤 시 누적"인지 "영구 인하"인지 모호하다는 우려. **수용 불가**: 실제 동작은 `levelup_current_cost` 직접 차감 → 다음 levelup까지 누적 (자연 감가와 동일). ne_envoy "라운드 시작: 골드 +2"도 같은 표기 패턴. over-strict 판정.

2. **E9/E11 도박꾼 커맨더 중첩**: 도박꾼(50% 무료 리롤) + ★3 중첩 시 T6 13g levelup이 2R 내 0g 도달 가능. **수용**: 사용자 인지된 다양성 시너지 ("강제 시너지 아님"). sim 검증은 future 작업.

★2 합성 유인 / ★3 차원 전환 / 임계점 호환성 / E14 단조성: 모두 PASS.

## 알려진 결함 (이번 작업 범위 외)

**sim 의 ON_REROLL trigger 미처리**:
- `sim/headless_runner.gd` 가 `chain_engine.process_reroll_triggers` 를 호출하지 않음
- 게임 본체(`game_manager.gd`)는 호출함
- sp_interest 의 ON_REROLL 효과(spawn + enhance) 도 sim 에서 미발동
- ne_pawnbroker 의 levelup_discount + free_reroll 도 sim 에서 미발동
- **결과**: sim 기반 밸런싱이 ON_REROLL 카드의 효과를 과소평가
- → backlog: `sim/shop_logic.gd::reroll()` 에 chain_engine hook 추가 (별도 작업)

## 검증

- GUT 테스트: 985/985 pass (8 ne_pawnbroker 테스트 신규, 5 ne_clone_seed 제거)
- codegen `--check`: PASS (yaml ↔ card_db.gd 동기)
- 게임 본체 godot 시작: 정상 (CardDB Registered 68 cards)
