# AI Trace Deep Dive — Merge Failure (2026-04-18)

Follow-up to `insights-2026-04-18-baseline.md`. Added sell events + score breakdown.

## 핵심 발견 (진단 뒤집힘)

### 1. Capstone 구매는 실제로 발생 — 초기 집계 오독
dr_world, dr_wt_root, dr_wrath, dr_grace 모두 10-run 트레이스에서 다음 빈도로 구매됨:
- dr_world: 10/10run (shop_lv 5 도달 시)
- dr_wrath: 20/10run
- dr_wt_root: 16/10run
- dr_grace: 20/10run

초기 top10 집계에서 누락된 것일 뿐 0건은 아님.

### 2. 진짜 문제: Merge 실패
| Card | Buys | Actual ★2 merges | 기대 |
|------|------|------|------|
| dr_cradle (soft_druid) | 39 | **0** | ~3 |
| dr_lifebeat (soft_druid) | 44 | 2 | ~3 |
| pr_nest (soft_predator) | 57 | 4 | ~4 |
| pr_farm (soft_predator) | 36 | 5 | ~3 |

**전 전략 ★3 merge = 0건** (15-round 전체).

### 3. Merge Imminent → 실제 Merge 전환율
- dr_cradle: 9 imminent buys → 1 merge (**11%**)
- pr_nest: 19 imminent buys → 4 merges (**21%**)

AI가 "2 ★1 보유 상태에서 3번째 구매" 판단을 자주 하는데, 실제 auto-merge는 절반 이하만 성공.

### 4. Sell은 주요 원인이 아님
- soft_druid: 10-run 동안 테마 카드 4건만 sell (transition_board only)
- soft_predator: 7건 sell
- cleanup_bench / weakest_for_upgrade sell로 인한 ★1 drop은 유의미하지 않음

### 5. Score Breakdown 비교 (dr_cradle vs pr_nest 구매 시)

```
soft_druid dr_cradle (n=38, avg score 38.16):
  theme:       +21.87 (n=38/38, 거의 매번 critical +8 포함)
  tier:         +2.00 (n=38)
  timing:       +4.41 (n=38)
  merge:       +16.49 (n=20/38, 53%)
  synergy:      +4.75 (n=16, 동-theme partner)
  theme_state:  +4.00 (n=5, 13% 발동)
  dup_penalty: -10.00 (n=5, 13%)

soft_predator pr_nest (n=57, avg score 43.08):
  theme:       +19.16 (critical 없음, 순수 theme match)
  tier:         +2.00 (n=57)
  timing:       +4.69 (n=57)
  merge:       +20.07 (n=33/57, 58%)
  synergy:      +5.78 (n=27)
  theme_state:  +4.00 (n=26, 46% 발동!)
  build_path:  +20.00 (n=3)
  dup_penalty: 0건
```

## 차이의 근원

1. **theme_state 발동률**: druid 13% vs predator 46%. Druid "payoff→producer" 보너스 조건이 까다로움(DRUID_PAYOFF 중 하나 보유해야). Predator는 pr_farm 조건 단순.
2. **dup_penalty 13%**: dr_cradle이 이미 3+ copies 상태에서도 구매 — 합성 실패 후 계속 사는 패턴.
3. **pr_nest는 dup_penalty 0건** — 합성이 제때 되어 ★1 copies가 쌓이지 않음.

## 다음 가설 (검증 대상)

**A. 합성 순간 side-effect**: _sell_weakest_for_upgrade가 `no_space` 시 다른 ★1 드루이드 카드를 팔아 공간 확보하면서, 합성 직전 상태를 깨뜨릴 가능성.

**B. Bench full 타이밍**: `has_space` 체크 후 `try_purchase`로 bench 추가 → `try_merge`. 만약 bench가 이미 full인 상태에서 _sell로 1칸 확보 → add_to_bench 성공 → try_merge. 순서는 정상.
→ 그러면 왜 merge 성공률이 11%인가?

**C. CHAIN_PAIRS 효과**: predator엔 ne_* RS emitter가 pr_* OE listener로 연결. druid는 CHAIN_PAIRS 정의가 없음 → chain_bonus 0. 이게 전체 merge와는 직접 연관 없음.

**D. card_pool exhaustion**: dr_cradle 39번 샀으면 return_cards로 풀에 복귀될 때 pool 카운트가 뒤엉킬 가능성. 추가 조사 필요.

## 다음 액션 후보

- **D 검증**: trace에 `card_pool.count(card_id)` 샷 찍기 (round_start에 포함)
- **A/B 재현**: `_sell_weakest_for_upgrade` 호출 직전/직후 bench 상태 dump
- **간단 실험**: merge_imminent_bonus를 +50으로 올려 강제 우선. 전환율 상승하면 scoring 문제, 아니면 로직 문제.
