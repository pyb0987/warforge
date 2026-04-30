---
session: "manual-investigation/2026-04-30"
date: "2026-04-30"
experiment_range: "single re-baseline"
adopts: 0
rejects: 0
metric_start: 0.5456
metric_end: 0.4407
---

## Episode 007: 카드 풀 68장 확정 후 sim 회귀 인과 분리 (multi-review veto 사후 액션 2)

### Context

multi-review (4 critic) Critic 4 (frame-level) veto 의 핵심 우려:
> "experiments/002 v2 에서 weighted_score 0.6583 도달 → 현재 baseline 0.5456 회귀. 원인 미진단."
> "0.5456 의 원인이 정원 (55→68 확장) 인지 다른 변수 인지 격리 안 됨."

본 조사는 **인과 격리** 를 위해 git 메타데이터 + 베이스라인 재측정으로 회귀 원인을 분해.

- program.md 방향: weighted_score 0.65+ 목표
- 이전 에피소드 교훈:
  - 002 (v2 era): peak 0.6583 — AI v6 + pre-CP-refactor era
  - 005 (v2 AI 변경 후): 0.3661 → 0.5929 재탐색
  - 현재 baseline.json: 0.5456 (실제 측정 시점 = 3ffb89e, 2026-04-25)

### Raw Output

#### 1단계: git 메타데이터 — baseline.json 의 진짜 측정 시점 추적

```
$ git log --all --pretty=format:'%h %ad' --date=short -- godot/sim/baseline.json | head -3
3ffb89e 2026-04-25 refactor(sim): recalibrate target_cp + baseline for new CP formula
5ef9d27 2026-04-24 chore(sim): autoresearch baseline 재측정
e40af38 2026-04-24 refactor(evaluator): per_round_wr_match replaces ...

$ git hash-object godot/sim/baseline.json
670eb59833b2a0a2558b8e8705ddaefb6d7b9962
$ git rev-parse 3ffb89e:godot/sim/baseline.json
670eb59833b2a0a2558b8e8705ddaefb6d7b9962
$ git rev-parse HEAD:godot/sim/baseline.json
670eb59833b2a0a2558b8e8705ddaefb6d7b9962
```

→ HEAD baseline.json = 3ffb89e (2026-04-25) hash 동일. **5일 stale**.
→ 측정 시점 풀 크기: neutral 15 / 테마 10 = **55장** (post-CP-refactor, pre-pool-expansion).

#### 2단계: 풀 확장 + 후속 변경 후 baseline 재측정

```
$ godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=10 --seed=42

[CardDB] Registered 68 cards.
weighted_score: 0.4407
card_coverage: 0.1909
theme_ratio_variance: 0.3885
per_round_wr_match: 0.4258
strategy_stats:
  adaptive       0.80
  aggressive     0.40
  economy        0.10
  soft_druid     0.00
  soft_military  0.50
  soft_predator  0.50
  soft_steampunk 0.00
mean_wr: 0.329, σ: 0.304
```

#### 3단계: 회귀 분해

| Metric | stale 0.5456 (3ffb89e, 55장) | 재측정 0.4407 (HEAD, 68장) | Δ |
|--------|------------------------------|---------------------------|---|
| weighted_score | 0.5456 | 0.4407 | **-0.1049** |
| per_round_wr_match | 0.8632 | 0.4258 | **-0.4374** ★ |
| loss_resilience | 0.6231 | 0.5479 | -0.0752 |
| activation_utilization | 0.7685 | 0.7275 | -0.0411 |
| tipping_point_quality | 0.0706 | 0.0286 | -0.0421 |
| card_coverage | 0.2300 | 0.1909 | -0.0391 |
| dominance_moment | 0.7997 | 0.7804 | -0.0193 |
| theme_ratio_variance | 0.4048 | 0.3885 | -0.0163 (개선) |
| board_utilization | 0.6907 | 0.6917 | +0.0009 |
| **mean WR** | 0.529 | 0.329 | -0.200 (감정 곡선엔 가까워짐) |
| **strategy σ** | 0.243 | 0.304 | +0.061 (악화) |

전략별 변화:
- adaptive 0.80 → 0.80 (불변, 베이스라인)
- soft_steampunk 0.40 → **0.00** ★ 붕괴
- soft_druid 0.20 → **0.00** ★ 붕괴
- economy 0.50 → **0.10** ★ 붕괴
- aggressive 0.70 → 0.40
- soft_predator 0.80 → 0.50
- soft_military 0.30 → 0.50 (개선)

### Key Experiments

| # | Hypothesis | Verdict | Metric | Δ | Insight |
|---|-----------|---------|--------|---|---------|
| E1 | "pool expansion 0fd2d5e 가 회귀 원인" | **REJECT** | — | — | 0fd2d5e 의 baseline 은 5ef9d27 (pre-CP) 의 stale 값. 직접 인과 격리 불가하나, T2 단독 변경(+13 카드) 으로 -0.10 수준 회귀는 이론적으로 어려움 |
| E2 | "현재 baseline.json 이 실제 상태 반영" | **REJECT** | hash | identical | 3ffb89e 시점 파일과 hash 동일. 풀 확장 + 5일 변경 후 재측정 안 됨 |
| E3 | "회귀의 일부는 stale baseline 이 가렸다" | **CONFIRM** | -0.1049 | observed | HEAD 에서 재측정 = 0.4407. stale = 0.5456. -0.1049 가 측정 안 된 회귀 |
| E4 | "회귀의 주범은 카드 너프 누적 효과" | **PROBABLE** | per_round_wr_match -0.4374 | dominant axis | 감정 곡선 일치도가 가장 크게 붕괴. 5일간 sp_workshop / sp_warmachine / dr_world / ne_envoy / ne_merchant / pr_carapace 너프 + ne_council 재설계 + ne_masquerade 등 누적 |
| E5 | "soft_steampunk / soft_druid / economy 가 0% 로 붕괴" | **CONFIRM** | -0.40 ~ -0.20 | per-strategy | 너프된 카드들이 해당 전략의 캡스톤. 캡스톤 약화로 빌드 자체 실패 |

### 인과 격리 결론

**Critic 4 가정 ("정원이 회귀 원인")**: REJECT.

**실제 원인 분해** (-0.1049 weighted_score):
1. **카드 너프 누적 효과** (가장 큰 기여): per_round_wr_match -0.44 + soft_steampunk/soft_druid/economy 0% 붕괴
2. **풀 확장 직접 영향**: 작거나 중립 (격리 측정 데이터 부재 — 0fd2d5e baseline 이 stale 이라 차이 측정 불가)
3. **CP formula refactor**: 5일 전 이미 흡수됨 (3ffb89e 가 그 baseline)
4. **AI 변경 + evaluator 변경**: per_round_wr_match 가 추가된 e40af38 시점에 이미 baseline 재측정됨

### 후속 액션 권고

1. **baseline.json 갱신** (Tier 0 정책상 autoresearch ADOPT 가 정식 경로 — 사용자 결정 필요)
2. **액션 3 (카드별 등장 빈도 분해)** 즉시 수행 — 0% 전략의 실패 원인이 캡스톤 카드 너프인지, AI 가 캡스톤 못 사는지 분리
3. **카드 너프 retrospective**: 4-25 ~ 4-30 사이 너프 commit 별로 영향도 측정 (per-card sim ablation)
   - sp_workshop: faa7b25
   - sp_warmachine: a815bd1
   - dr_world: 25a1137
   - ne_envoy: a815bd1
   - ne_merchant ★2: 509a4ba
   - pr_carapace: 7952867
   - pr_swarm_sense / pr_queen: 1c4d787
4. **Layer 1 autoresearch 재시작**: 0.4407 → 0.65+ 까지 거리 멀어짐. genome 재탐색 단계 가능성

### Exhausted Axes
- 단순 git 메타데이터 만으로 풀 확장의 직접 영향 격리 불가 — baseline 갱신이 우선

### Lesson

- **stale baseline 위험**: Tier 0 보호로 baseline 이 자동 갱신 안 되어, 카드 변경 후 한참 지나서야 누적 영향 발견. multi-review Critic 4 의 "진단 부재" 우려가 정확히 이 지점에 부합.
- **stale baseline 의 위험성에 대한 P5 사다리 검토 필요**: hook 으로 "마지막 baseline 측정 후 일정 commit 누적 시 경고" 같은 메커니즘 가능. backlog 등재.
- **카드 밸런스 너프의 누적 sim 영향**: 개별 너프는 의도적이지만 합계 -0.10 weighted_score 회귀. 너프 단위로 sim 회귀 측정 절차가 부재. CLAUDE.md "완료 기준" 에 sim 영향 측정 추가 검토.
- **Critic 4 veto 의 가치**: framing 검증이 진단 부재를 정확히 짚었음. veto 가 아니었다면 stale baseline 위에서 balance 작업 계속됐을 것.
