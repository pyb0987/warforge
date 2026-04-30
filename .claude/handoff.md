# Handoff — multi-review 액션 1/2 + B-5 + B-7 완료 (2026-04-30)

## Status: ready

이번 세션은 **카드 풀 68장 확정 + multi-review 검증 + sim 결정성 복원** 까지 완료. main 까지 머지됨.
다음 세션은 **B-3 (카드별 등장 빈도 분해) + B-4 (Layer 2 baseline 회복)** 부터 시작.

## 이번 세션 변경사항 (커밋 4건)

| Commit | 내용 |
|--------|------|
| `84e542d` | docs(card-pool): 55→68장 동기화 — multi-review 액션 1, 14 파일 |
| `c35fa55` | docs(traces): 풀 확장 후 baseline 회귀 인과 분리 — multi-review 액션 2 |
| `84ae987` | chore(sim): baseline.json 갱신 — stale 5일치 회귀 흡수 (B-5) |
| `f71994d` | fix(sim): combat_engine 결정성 복원 — 글로벌 randf() 제거 (B-7) |

## 최종 상태

- GUT **921/921 통과** (cache 재빌드 후)
- main FF-merged (33 commits ahead of origin/main, 미푸시)
- baseline.json: **0.445902** (deterministic, 8회 측정 stdev 0)
- 카드 풀 확정: **68장** (중립24/스팀펑크11/드루이드11/포식종11/군대11)

## 핵심 finding (다음 세션 출발점)

### multi-review 결과 (4 critic)
| Critic | Verdict | Score |
|--------|---------|-------|
| 1. 테마 정체성 | pass | 9 |
| 2. 빌드 아키타입 | concern | 7 |
| 3. 시뮬/경제 | concern | 6 |
| 4. Frame-level | **veto** | 3 |

Critic 4 veto 가 "사전 진단 부재" 우려를 정확히 짚음. 사용자 (A) 채택으로 사후 액션 3건 진행.

### B-2 (sim 회귀 인과 분리)
- baseline.json 이 5일 stale (3ffb89e, 55장 시점 측정값) 발견
- HEAD 재측정: 0.5456 → **0.4407** (-0.1049, -19% 회귀 발견)
- 회귀 원인 ≠ 풀 확장. 진짜 원인 = **카드 너프 누적 효과** (per_round_wr_match -0.44, soft_steampunk/druid/economy 0% 붕괴)

### B-7 (sim 비결정성 진단 + 수정)
- 원인: `combat_engine.gd:475` (separation jitter) + `mechanics_handler.gd:150` (critical hit) 가 글로벌 `randf()` 호출
- 수정: combat_engine 에 `_rng + set_seed()` + 호출처 (headless_runner / unit_tournament / preset_parity_runner) 가 매번 set_seed
- 결과: variance 0.0075 → **0.000000**

## 다음 세션 진행 — B-3 / B-4

### B-3. 신규 13장 활용도 검증 (즉시 진행 가능)

**질문**: 0fd2d5e (2026-04-25) 확장분 13장이 sim 빌드 경로에 등장하는가? `card_coverage 0.190` 이 죽은 카드 다수 때문인지 AI 미탐색 때문인지.

**왜 즉시 가능**: B-7 fix 로 sim 결정성 복원. 측정값이 noise 위가 아니라 신호 위에 있음.

**제안 절차**:
1. **카드별 등장 카운트 계측 추가** — 옵션:
   - (a) `headless_runner.gd` 에 `_card_pickup_count: Dictionary` 추가 → 매 구매 시 +1
   - (b) 별도 분석 스크립트 — `scripts/analyze_card_coverage.py` 생성 후 batch_runner 결과 파싱
   - 권고: (a). 진입점 명확하고 기존 패턴과 일관.
2. **70 run × 카드별 빈도 측정**:
   ```bash
   godot --headless --path godot/ -s sim/batch_runner.gd -- --runs=10 --seed=42 > /tmp/coverage.json
   python3 scripts/parse_card_coverage.py /tmp/coverage.json
   ```
3. **분류 임계**:
   - 죽은 카드: 등장률 < 5% (70 run 중 < 4회)
   - 약체: 5% ≤ 등장률 < 15%
   - 활성: 등장률 ≥ 15%
4. **결과 표 등재**: `.claude/backlog.md` B-3 항목 + `traces/experiments/008-card-coverage-decomposition.md`

**0fd2d5e 신규 13장 ID** (분류 대상 핵심):
- `ne_pawnbroker, ne_envoy, ne_hoarder, ne_legion, ne_masquerade, ne_void_force, ne_fusion_end, ne_council, ne_nexus` (중립 9장)
- `sp_global_workshop, dr_resonance, pr_parasitic_swarm, ml_alliance` (테마 4장)

**예상 hours**: 1-2시간

### B-4. AI Layer 2 baseline 회복 (B-3 후)

**왜 B-3 다음**: B-3 가 "어느 카드가 죽었나" 데이터를 주고, 이게 AI 빌드 경로 결정의 핵심 입력. AI 가 죽은 카드를 사면 안 됨 → AI 평가 함수 조정 신호로 사용.

**완료 조건**:
- `ai_research/ai_baseline.json` 재측정 (B-7 fix 후 결정적 값으로)
- weighted_score ≥ 0.4459 (Layer 1 baseline 동등 이상)

**제안 절차**:
1. `ai_research/` 의 evaluator / baseline 도 결정성 영향 받았는지 확인 (B-7 수정으로 자연스레 갱신)
2. 재측정 후 갭이 사라졌는지 확인 — 사라졌다면 종료
3. 갭이 남으면 AI v2 의사결정 함수 (`ai_agent.gd::STRATEGY_NAMES` 별 로직) 검토

**예상 hours**: 1-2시간 (재측정만 하면 30분, 갭 추가 진단 시 길어짐)

## 미해결 backlog (다음 세션 영역 외)

- **B-6**: stale baseline 감지 hook (P3, 별도 세션)
- **G-1~5**: UI 미완 (커맨더/부적 선택, 메타 진행, 튜토리얼)
- **S-1~3**: card_coverage 70% 추격, 전략 σ < 0.10, 평균 WR 압축
- **기술부채**: desc_gen multi-block listen 분리 (높음 — UI 작업 전), sim ON_REROLL trigger 미처리 (중)

상세는 `.claude/backlog.md` 참조.

## Next entry point

```bash
# 다음 세션 첫 명령 — B-3 카드별 등장 빈도 측정 시작
cat .claude/backlog.md | grep -A 10 "B-3\."
ls godot/sim/headless_runner.gd
# 옵션 (a): headless_runner 에 _card_pickup_count 계측 필드 추가
```
