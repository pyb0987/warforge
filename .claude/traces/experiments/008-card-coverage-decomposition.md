---
session: "manual-investigation/2026-04-30"
date: "2026-04-30"
experiment_range: "single coverage decomposition"
adopts: 0
rejects: 0
metric_start: 0.1896
metric_end: 0.1896
---

## Episode 008: 카드 풀 68장 등장 빈도 분해 (multi-review veto 사후 액션 3 / B-3)

### Context

multi-review (4 critic) Critic 4 (frame-level) 2번째 우려:
> "0.5456 의 원인이 정원 (55→68 확장) 인지 다른 변수 인지 격리 안 됨."
> + B-2 finding: HEAD 재측정 weighted_score 0.4407, card_coverage 0.19, soft_steampunk/druid/economy 0% 붕괴.

본 조사는 **카드 풀의 진짜 활용도** 를 분해. card_coverage 0.19 가 (a) 죽은 카드 다수 때문인지 (b) AI 가 카드를 안 사기 때문인지 격리.

- 이전 에피소드 교훈:
  - 007 (B-2): baseline.json stale 5일 + 카드 너프 누적 → -0.10 회귀
  - B-7 (handoff): sim 결정성 복원, variance → 0
- 측정 도구: 기존 `godot/sim/dump_coverage.gd` (per-run purchase_log + final_deck dump)
- 분석 도구: 신규 `scripts/analyze_card_coverage.py`

### Raw Output

#### 측정 명령

```bash
godot --headless --path godot/ -s sim/dump_coverage.gd -- --out=/tmp/coverage.json
# → 7 strategy × 20 runs = 140 runs, 2:19 wall time
python3 scripts/analyze_card_coverage.py /tmp/coverage.json
```

#### 결과 핵심 — Evaluator 메트릭 재현

```
evaluator.gd card_coverage = min(per-theme avg usage_rate) = 0.1896

  druid     : 0.1896  ← 병목
  predator  : 0.2266
  military  : 0.2364
  steampunk : 0.2766
```

→ B-2 의 0.19 가 **드루이드 테마의 평균 19%** 임이 확인됨. min() 게이트가 드루이드를 잡고 있음.

#### 결과 핵심 — 분류 분포

```
Pool: 68 cards | dead 0 | weak 19 | active 49
Threshold: dead < 5% | weak 5–15% | active ≥ 15% (purchase appearance rate)
```

**dead = 0**. 140 run 동안 모든 68장이 적어도 한 번 구매됨. (5% 임계 = 7 run 이상)

#### 신규 13장 (commit 0fd2d5e, 2026-04-25 풀 확장)

| Card | Tier | Theme | Class | Purch% | Final% |
|------|------|-------|-------|--------|--------|
| dr_resonance | 4 | druid | weak | 7.9% | 0.0% |
| ne_masquerade | 4 | neutral | weak | 11.4% | 0.7% |
| sp_global_workshop | 3 | steampunk | weak | 11.4% | 1.4% |
| pr_parasitic_swarm | 3 | predator | active | 15.0% | 0.7% |
| ml_alliance | 3 | military | active | 15.0% | 3.6% |
| ne_fusion_end | 4 | neutral | active | 16.4% | 1.4% |
| ne_nexus | 5 | neutral | active | 16.4% | 1.4% |
| ne_council | 5 | neutral | active | 17.1% | 3.6% |
| ne_hoarder | 3 | neutral | active | 17.9% | 0.0% |
| ne_void_force | 4 | neutral | active | 20.0% | 0.0% |
| ne_legion | 3 | neutral | active | 26.4% | 0.0% |
| ne_envoy | 2 | neutral | active | 40.0% | 0.7% |
| ne_pawnbroker | 1 | neutral | active | 62.9% | 7.9% |

신규 13장 중 **10장이 active**, 3장만 weak. **0장 dead**. 풀 확장이 dead pool 을 만든 것은 아님.

다만 `final_deck_rate` 은 매우 낮음 (대부분 0–4%) — **사긴 사지만 끝까지 안 들고 감**. 추측: 합성/판매되어 빠지거나 팔려나가는 transient buy. (T3 `ne_hoarder`/`ne_void_force`/`ne_legion` 의 0% final 이 특히 인상적.)

#### 전략별 미구매 카드 분포 (zero-coverage breakdown)

| Strategy | Runs | 미구매 카드 수 | 설명 |
|----------|------|---------------|------|
| economy | 20 | **2** | 거의 전체 풀을 산다 (sp_barrier, ne_spirit_blessing 만 제외) |
| adaptive | 20 | **5** | 드루이드 5장만 회피 (dr_deep, dr_origin, dr_resonance, dr_spore_cloud, dr_world) |
| aggressive | 20 | 6 | 흩어진 6장 (ml_command, ne_chimera_cry, ne_council, ne_merchant, pr_transcend, sp_interest) |
| soft_druid | 20 | **21** | 드루이드 외 테마 거의 전부 회피 (ml/pr/sp 21장) |
| soft_military | 20 | **21** | 군대 외 테마 회피 (dr/pr/sp 21장) |
| soft_predator | 20 | **23** | 포식종 외 테마 회피 (dr/ml/sp 23장) |
| soft_steampunk | 20 | **26** | 스팀펑크 외 테마 회피 (dr/ml/pr/일부 ne 26장) |

→ `soft_X` 4종은 자기 테마 외를 거의 안 산다. 이들이 평균을 끌어내림.

### Key Finding

**B-2 의 0.19 는 dead pool 가설 REJECT.**

- ❌ "신규 13장이 죽었다" — 실제 13장 중 0장 dead, 10장 active
- ❌ "풀 확장이 평균을 희석시켰다" — 모든 카드가 5% 이상 등장
- ✅ **AI 의 테마 잠금 (theme lock)** 이 진짜 원인. soft_X 4종이 자기 테마 외를 안 사면서 드루이드/포식종/스팀펑크/군대 카드 평균을 분산시킴.
- ✅ **드루이드가 병목** — adaptive 마저 드루이드 5장을 회피 (21 vs 26 회피 카드 분포 보면 드루이드는 soft_druid 외 거의 안 산다)

### Adopted Changes
없음. 본 에피소드는 진단만 수행.

**도구 추가**:
- `scripts/analyze_card_coverage.py` — 재사용 가능한 분석 스크립트
- 기존 `godot/sim/dump_coverage.gd` 의 측정 정확성 확인됨 (별도 계측 추가 불필요)

### Exhausted Axes

축 자체는 소진되지 않음. 본 조사로 다음 진단이 명확해짐:
- **soft_druid 0% 붕괴 원인**: 드루이드 풀 자체가 약하거나 (밸런스), AI 의 드루이드 평가 함수가 다른 테마 카드 시너지를 인식 못 함 (Layer 2 AI). adaptive 마저 드루이드 회피하는 것은 후자 가설을 강하게 지지.
- **soft_steampunk 0% 붕괴 원인**: 스팀펑크 풀이 26 카드 회피 가운데에서 11장만 활용 가능. 스팀펑크 카드 자체의 너프 누적 (B-2 finding) + 좁은 풀 = 0%.
- **economy 0% 붕괴 원인**: 풀 활용 문제 아님 (66/68 카드 구매). **다른 메커니즘** — economy AI 평가 함수 / 자원 운용 로직 검토 필요.

### Lesson

**유망한 방향**:
1. **B-4 (AI Layer 2 baseline)** 으로 진행 정당화. 드루이드 풀이 살아있음에도 adaptive 마저 회피한다 → AI 평가 함수가 드루이드 시너지 인식 못 함 가설 검증 가능.
2. `final_deck_rate` 와 `purchase_rate` 격차 (예: ne_hoarder 17.9% buy / 0% final) 는 **합성 흡수** 또는 **판매 빠짐** 이 원인일 가능성. 합성 메커니즘 (★1→★2) 분석으로 분리 가능.

**경고**:
- **풀 확장이 직접 회귀 원인이 아님**. multi-review Critic 4 의 풀 확장 직접 영향 가설은 본 에피소드로 REJECT.
- soft_X 의 0% 는 풀 활용 문제가 아니라 **카드 자체의 약함** + **AI 의 테마 외 시너지 무시** 의 복합 원인. B-4 후속에서 분리.

### Reproducibility
- coverage 측정: `godot --headless --path godot/ -s sim/dump_coverage.gd -- --out=/tmp/coverage.json`
- 분석 재실행: `python3 scripts/analyze_card_coverage.py /tmp/coverage.json`
- 측정 시점: HEAD = 2e9913a (handoff B-7 fix 후, deterministic)
