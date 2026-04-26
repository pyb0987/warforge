# Handoff — ★ 합성 정책 통합 후속 (2026-04-26)

## Status: paused

본 세션(2026-04-26)은 ★ 합성 도너 stat 흡수 정책 통합 + 드루이드 임계값 + 세계수 [고유효과] 분리 + AS semantic fix 완료 후 main 머지(`f742c38`). 다음 세션은 두 가지 후속 작업 처리.

## 최종 상태

- main `f742c38` (Merge of `claude/quirky-leakey-843bab` ← 6 commits)
- GUT 1012/1012 통과 (cache 재빌드 후)
- search-set 5건 (SS-001/002/006/007/008)
- 신규 trace: failures/010, evolution/020, evolution/021

## 본 세션 commit 요약

| Commit | 내용 |
|--------|------|
| `c153280` | ★ 합성 도너 stat 흡수 정책 통합 — `CardInstance.absorb_donor()` |
| `0f0f377` | stale class_cache 카스케이드 진단 + cache rebuild 가이드 (SS-008) |
| `d1c8bea` | 드루이드 low_unit/unit_cap 임계값 → 합성 후 정원 매치 (2/6/18, 3/9/27) |
| `4c59dae` | 세계수 [고유효과] 분리 (`unique_*_mult` layer) + max 합성 |
| `818760b` | docs/design + traces 동기화 |
| `8120f6f` | `unique_as_mult` max → min (multi-review 후속, AS semantic) |

---

## 다음 세션 작업 1: ★2 합성 시 "마지막 구매 카드 미흡수" 정책

### 배경

현행 정책 (commit `c153280`): 3장 모두 흡수 → ★2가 시작 unit의 **3배** 보유.

사용자 결정 (2026-04-26 세션 종료 후): **마지막 구매되는 카드(합성 트리거)의 내용을 빼고 나머지 2장만 합치는** 정책으로 변경. 결과: 시작 unit의 **2배**.

### 의도

- 합성 보상 강도 조정 (3배 → 2배)
- "신규 카드는 fresh 상태로 합성에 진입" — 합성 직전 라운드 동안 누적된 stat 보존이 보상의 핵심
- 마지막 카드는 어차피 막 구매되어 누적분이 없는 fresh 상태 → 빼도 손실 작음

### 결정 필요 사항

1. **"마지막 구매되는 카드" 식별 방법**
   - (a) `GameState`에 `last_purchased_id`/`last_purchased_instance` 추적 필드 추가. 구매 시 갱신, try_merge에서 참조
   - (b) `CardInstance`에 `tenure == 0` (방금 진입) 조건으로 식별 — 시뮬상 부정확할 수 있음
   - (c) 명시적 메타 필드: 구매 시 `is_freshly_purchased=true`, 첫 라운드 끝나면 false
   - **권장**: (a) 명시적 추적이 가장 견고. 캐스케이드 합성/벤치 보관 시나리오에 안전

2. **캐스케이드 합성 처리** (★1×9 → ★3 = ★1×3→★2 → ★2×3→★3)
   - ★1→★2 단계: 마지막 구매 카드 제외 → 2장 흡수 (즉 2배 unit)
   - ★2→★3 단계: ★2 카드 3장 중 "마지막"은 누구? — 가장 최근 합성된 ★2? 또는 마지막 구매한 ★1이 만든 ★2? — **사용자 결정 필요**
   - **default 권장**: ★1→★2에만 정책 적용, ★2→★3은 기존 3장 흡수. 이유: ★2 카드는 모두 이미 "합성 결과"로 fresh 아님

3. **벤치 보관 후 합성 시나리오**
   - R3에 카드 A 구매 → R5에 A 한 장 더 → R7에 A 한 장 더 → 합성
   - "마지막 구매"는 R7 카드. R3/R5 카드는 라운드 누적 stat 보유.
   - 정책 그대로 적용 — R7 카드 미흡수, R3+R5 흡수 (2배 unit + 누적 stat)

4. **3장 중 "마지막"이 survivor 후보가 되는 경우**
   - 현행 survivor 선정: "업그레이드 수 최대 → 동점 시 leftmost"
   - 마지막 구매 카드가 업그레이드를 부착할 수 있는가? (벤치 카드는 부착 불가 — bench upgrade rule)
   - 고로 마지막 구매 카드는 일반적으로 upgrade=0 → survivor 후보 아님 (다른 2장 중 1장 survivor)
   - 단, 3장 모두 upgrade 0이고 마지막 구매가 leftmost인 경우 → survivor 됨
   - **이 경우 마지막 구매 카드가 survivor가 되면 미흡수 정책 어떻게 적용?** — survivor의 내용은 baseline이고 donor 1장만 흡수 (미흡수 카드는 폐기)

### 영향 범위 (구현 시 변경 파일)

- `godot/core/game_state.gd`: 
  - `last_purchased_*` 추적 필드 + 구매 흐름에서 갱신
  - `_try_merge_once`: copies 중 `last_purchased`인 것 식별 후 absorb 대상에서 제외 (또는 폐기)
- `godot/core/card_instance.gd`: 정책 docstring 업데이트
- `godot/tests/test_merge_system.gd`: 신규 테스트
  - "마지막 구매 카드 미흡수 → 2배 unit"
  - "벤치 보관 카드는 흡수됨 (last_purchased 아님)"
  - "마지막 구매가 survivor가 되는 엣지케이스"
- `docs/design/upgrade.md`: ★합성 도너 stat 흡수 정책 섹션 갱신

### 영향받는 기존 정책

본 세션 (iter 20) 정책 표에서 합산/곱셈/max/OR 모두 도너 2장이 아닌 **1장만** 흡수로 변경:
- 유닛 합산: 2배 (이전 3배)
- 업그레이드 어레이: 마지막 카드의 업그레이드 안 흡수 (어차피 fresh라 0)
- growth_*_pct, tag_growth_*: 합산이지만 fresh 카드 0이라 영향 없음
- stack mult: 곱셈이지만 fresh 1.0이라 영향 없음
- max 항목 (rank, tenure): 마지막 구매 카드의 rank=0, tenure=0 → max 영향 없음
- 따라서 **fresh 카드의 contribution이 0이 아닌 unit count만 실질적 영향**

→ 결과적으로 unit count만 3배에서 2배로 감소, 다른 stat은 동일.

---

## 다음 세션 작업 2: 세계수 mult 폭발 방지 메커니즘 대안 검토

### 배경

본 세션 multi-review의 Convergence Meta-Critic (Critic 4)이 제기한 우려:
- commit `c153280`은 stack mult를 통합 곱셈 누적으로 결정 ("분리 필드 over-engineering 회피" 명시)
- commit `4c59dae`는 dr_world에 한해 별도 `unique_*_mult` layer 도입 + max 합성 — **사용자가 이전에 거부한 "parallel mult layer" 패턴 재도입**
- 사용자는 **정책(max)** 은 결정했으나 **메커니즘(unique layer 신설)** 은 어시스턴트 단독 결정
- 대안 미제시

### 현행 메커니즘 (이미 main에 머지됨)

- `stacks[].unique_atk_mult`, `unique_hp_mult` (per-stack, 기본 1.0)
- `unique_as_mult` (per-card, 기본 1.0)
- `multiply_unique_stats(atk_pct, hp_pct)` 메서드
- `eff_atk_for/eff_hp_for`에 `layer_unique` 곱셈 추가
- `absorb_donor`: unique mult max (AS는 min)
- dr_world만 `multiply_unique_stats` 사용. 다른 입력원(보스/커맨더/% 업그레이드)은 기존 `multiply_stats` 유지

### 대안 옵션

#### 옵션 (i): 매 RS 덮어쓰기 (overwrite, not accumulate)

**핵심**: dr_world의 `multiply_stats` 호출을 매 RS 곱셈 누적이 아닌 **기준값 갱신**으로 변경.

```gdscript
# 현행 (누적):
target.multiply_unique_stats(atk_mult - 1.0, hp_mult - 1.0)

# 대안 (덮어쓰기):
for s in target.stacks:
    s["world_atk_mult"] = atk_mult  # 매 RS 절대값 설정 (이전 값 무시)
    s["world_hp_mult"] = hp_mult
```

- 매 RS 새로 forest_depth 기반 mult 결정. 이전 라운드 mult는 사라짐 (누적 아님)
- 합성 시점: stack mult가 이미 단일 라운드 효과만 반영 → 도너의 누적분 자체가 없어 폭발 위험 0
- 합성 시 max/min 정책 불필요 (단순 덮어쓰기 또는 max)

**장점**:
- 메카닉이 "지속 효과 (매 라운드 갱신)"로 더 직관적
- unique_*_mult 분리 layer 불필요 — 코드 단순화
- 합성 정책 단순 (덮어쓰기는 max랑 동일 효과)

**단점**:
- dr_world 효과 강도 **약화**. 현행은 라운드 진행에 따라 mult 무한 누적 (10라운드 후 ×2.6+) — fantasy의 일부.
- 사용자가 "★3 사기 쾌감" 의도한 부분 손상 가능 ([feedback_high_tier_power.md](memory))

#### 옵션 (ii): per-source cap

**핵심**: `multiply_stats` 호출 시 source 식별 + source별 누적 cap.

```gdscript
func multiply_stats(atk_pct: float, hp_pct: float, source: String = "generic") -> void:
    var cap := SOURCE_CAPS.get(source, INF)
    for s in stacks:
        var new_mult: float = s["upgrade_atk_mult"] * (1.0 + atk_pct)
        s["upgrade_atk_mult"] = minf(new_mult, cap)
        # ...
```

`SOURCE_CAPS = {"world": 3.0, "boss": INF, "upgrade": INF, "commander": INF}`

**장점**:
- 분리 layer 불필요 — 단일 stack mult layer 유지 (unification 의도와 정합)
- world만 cap, 다른 source는 자유

**단점**:
- `multiply_stats` 시그니처 변경 → 모든 호출처 수정 필요 (boss, commander, druid, % upgrade 등)
- cap 값 자체가 매직 넘버 — design 결정 필요
- 합성 시 폭발 방지가 cap에 의존 → 캐스케이드 합성에서 도너 누적분 흡수 가능 (cap에 도달 안 했으면)

#### 옵션 (iii): ★3 evolve_star 시점 댐핑

**핵심**: 합성 시 stack mult 통합 곱셈 누적 그대로. 단 evolve_star가 ★3에 도달할 때 "댐핑 함수" 적용.

```gdscript
func evolve_star() -> void:
    star_level = mini(star_level + 1, 3)
    if star_level == 3:
        # ★3 도달 시 stack mult sqrt 댐핑 (mult가 너무 큰 경우만)
        for s in stacks:
            if s["upgrade_atk_mult"] > 5.0:
                s["upgrade_atk_mult"] = 5.0 + sqrt(s["upgrade_atk_mult"] - 5.0)
            # 동일 hp_mult
```

**장점**:
- 분리 layer 없이 통합 정책 유지
- 합성 자체는 곱셈 누적 그대로 — ★1/★2까지는 정책 일관

**단점**:
- 댐핑 함수 자체가 임의적 — 디자인 결정 필요
- ★3 도달 시 점프 (continuous하지 않음) — UI 표시 surprise 가능
- 다른 ★3 카드(non-dr_world)에도 영향

### 결정 매트릭스

| 기준 | 현행 (unique layer) | (i) 덮어쓰기 | (ii) per-source cap | (iii) ★3 댐핑 |
|------|--------------------|--------------|---------------------|----------------|
| 코드 복잡도 | 중 (분리 layer) | 저 (단일 layer) | 중 (signature 변경) | 저 (단일 함수) |
| 합성 정책 일관성 | 낮음 (max/곱셈 혼재) | 높음 (단일) | 높음 (단일) | 중 (★3만 예외) |
| dr_world ★3 fantasy 보존 | 높음 | **낮음** | 높음 | 중 |
| 다른 [고유효과] 카드 확장성 | 높음 (layer 재사용) | 낮음 | 중 | 낮음 |
| 사용자 sycophancy 우려 | 재발 (분리 layer) | 해소 | 해소 | 해소 |

### 권장 진행

1. **사용자에게 4가지 옵션 + trade-off 표 제시** (handoff item으로 옮김)
2. **옵션 (i) 덮어쓰기를 우선 검토**: 메커니즘 단순함이 가장 큼. 단 dr_world fantasy 약화는 별도 균형 작업으로 보강 가능 (★3 atk_base 1.30 → 1.50 등 수치 강화)
3. **사용자 결정 후 구현** — 현행을 유지할지, 옵션 (i)/(ii)/(iii)로 변경할지

### 영향 범위 (옵션 (i) 채택 시 예상)

- `godot/core/card_instance.gd`: `unique_*_mult` 필드 제거, `multiply_unique_stats` 제거, `eff_atk_for/eff_hp_for` `layer_unique` 제거, `absorb_donor`에서 unique 처리 제거
- `godot/core/druid_system.gd`: dr_world의 `multiply_unique_stats`를 새 mechanism으로 교체
- `godot/sim/headless_runner.gd`, `godot/scripts/game/game_manager.gd`: AS 계산에서 `unique_as_mult` 제거
- 모든 unique 관련 테스트 (5개) 제거 또는 변환
- `docs/design/upgrade.md`, evolution/021 갱신

---

## 추가 잔여 (별도 backlog)

- **태고의 분노 cap 27 정체성 약화** — `min(units, cap)` 부분 적용 메카닉 변환 검토
- **multi-review test self-evaluation bias** — 정책/테스트 generator 분리 검토 (Fixed Evaluator 도입)

## Next entry point

다음 세션 첫 작업:

```
1. 사용자에게 작업 1 (마지막 카드 미흡수) 결정 매트릭스 제시 → 식별 방법, 캐스케이드 정책 확정
2. 사용자에게 작업 2 (메커니즘 대안) 4안 비교 표 제시 → 옵션 선택
3. 결정 후 TDD: RED → GREEN → 회귀 → main 머지
```
