# Backlog — 현재 상태 + 앞으로 할 일

> 마지막 갱신: 2026-07-02
> Branch: `claude/charming-jones-3aaeef` (main 동기화)
> Tests: 1141/1141 (handoff 기준, full GUT)

설계 결정 / 기술부채는 [docs/design/backlog.md](../docs/design/backlog.md) 별도 관리. 본 문서는 **구현 로드맵**.

---

## 현재 상태 스냅샷

### 코드 / 구현 완료
- ✅ **Sprint 11** — 테마 시스템 4종 (`steampunk_system`, `druid_system`, `predator_system`, `military_system`) + `neutral_system`
- ✅ **데이터** — `unit_db`, `card_db` (codegen), `upgrade_db`, `boss_reward_db`, `keyword_glossary` autoload 등록
- ✅ **autoload** — `Commander`, `Talisman`, `Difficulty` 데이터/규칙 클래스 + 런 시작 선택 UI 연결
- ✅ **Popup UI 9종** — `battle_result`, `boss_reward`, `game_over`, `theme_choice` (ne_masquerade), `upgrade_choice`, `card_tooltip`, `commander_select`, `talisman_select`, `run_start_screen`
- ✅ **장면** — `build_phase`, `battle_phase`, `chain_visual`, `card_visual`, `upgrade_visual`, `unit_visual`
- ✅ **하네스** — codegen + protect-files + lint hook + r_conditional ★ parity validator + keyword glossary drift guard
- ✅ **카드 spawn 단일 진입점** (P5 2.5단계, SS-009)

### 시뮬 / AI 베이스라인 (2026-04-30)
| 지표 | 현재 | 목표 | 갭 |
|------|------|------|-----|
| `weighted_score` (Layer 1) | 0.546 | 0.65+ | -0.10 |
| `weighted_score` (Layer 2 AI) | 0.438 | baseline 이상 | 미달 |
| `card_coverage` | 23% | 70%+ | -47%p |
| 전략 승률 σ | ≈ 0.21 (max 0.8 / min 0.2) | < 0.10 | 2× 초과 |
| 평균 승률 | 52.9% | 5-10% (감정 곡선) | 너무 쉬움 |
| `theme_ratio_variance` | 0.405 | 낮을수록 좋음 | 테마 편중 잔존 |

### 카드 풀 — **68장 확정** (2026-04-30, multi-review veto-conditional pass 후 채택)

| 테마 | 장수 | T1 | T2 | T3 | T4 | T5 |
|------|------|----|----|----|----|----|
| 중립 | 24 | 4 | 7 | 6 | 5 | 2 |
| 스팀펑크 | 11 | 3 | 2 | 3 | 2 | 1 |
| 드루이드 | 11 | 2 | 3 | 2 | 3 | 1 |
| 포식종 | 11 | 2 | 3 | 3 | 2 | 1 |
| 군대 | 11 | 2 | 3 | 3 | 2 | 1 |
| **합계** | **68** | **13** | **18** | **17** | **14** | **6** |

multi-review 결론 (4 critic): 분배 자체는 정체성/아키타입/sim 영향 면에서 결함 없음. 단 critic 4 (frame-level) veto 가 사전 액션 3건 요구 — 본 backlog 항목들로 추적.

---

## P0 — multi-review veto 사후 액션

### B-1. ✅ 카드 풀 68장 확정 + 문서 동기화 (2026-04-30 완료)
DESIGN.md / themes.md / upgrade.md / card-codegen-schema.md / units-neutral.md / CLAUDE.md 갱신 완료.
**잔여**: `godot/sim/program.md` (Tier 0 protect-file, 사용자 chmod +w 필요)

### B-2. ✅ sim 회귀 인과 분리 (2026-04-30 완료)
**조사 결과** (`traces/experiments/007-pool-expansion-causal-isolation.md`):
- baseline.json 이 5일 stale (3ffb89e, 2026-04-25 측정 = 55장 시점)
- HEAD 재측정: weighted_score **0.4407** (stale 0.5456 대비 **-0.1049, -19%**)
- 풀 확장(55→68) 가 회귀 원인 = REJECT. 실제 원인 = **카드 너프 누적 효과** (per_round_wr_match -0.44, soft_steampunk/soft_druid/economy 전략 0% 붕괴).

**Critic 4 veto 가치 확인**: stale baseline 으로 가려진 -0.10 회귀를 발견. veto 없었으면 잘못된 점수 위에서 balance 작업 계속됐을 것.

### B-3. ✅ 신규 13장 활용도 검증 (2026-04-30 완료)
**조사 결과** (`traces/experiments/008-card-coverage-decomposition.md`):

- 측정: 7 strategy × 20 run = 140 run (deterministic, B-7 fix 후)
- 도구: 기존 `godot/sim/dump_coverage.gd` + 신규 `scripts/analyze_card_coverage.py`

**분류 분포**: dead 0 / weak 19 / active 49 (총 68장)

**Evaluator 메트릭 재현**:
- `card_coverage = min(per-theme avg usage_rate) = 0.1896` (B-2 의 0.19 재현)
- 병목 = **드루이드 (0.1896)**, 다른 테마 0.23–0.28

**신규 13장 결과**:
- 0장 dead, 3장 weak (`dr_resonance` 7.9%, `ne_masquerade` 11.4%, `sp_global_workshop` 11.4%)
- 10장 active (`ne_pawnbroker` 62.9% 가 최고)
- ★풀 확장이 dead pool 을 만든 것은 아님. multi-review Critic 4 의 풀 확장 직접 영향 가설 REJECT.

**전략별 미구매 카드** (theme lock 가시화):
- economy: **2장만** 미구매 (전체 풀 활용)
- adaptive: 5장 (모두 드루이드)
- soft_druid/military/predator/steampunk: **21–26장 미구매** (자기 테마 외 회피)

**Key Finding**: B-2 의 0.19 는 dead pool 이 아니라 **AI 의 theme lock**. 드루이드는 `soft_druid` 외 거의 안 사며 `adaptive` 마저 드루이드 회피.

**B-2 0% 붕괴 원인 분리**:
- soft_druid: 풀 활용 21/68. AI 평가 함수의 테마 외 시너지 무시 가설 강함 → B-4 검증 영역
- soft_steampunk: 풀 활용 11+일부 ne. 카드 자체 너프 + 좁은 풀 복합
- economy: 풀 활용 66/68 (정상). **풀 활용 문제 아님** — AI 평가/자원 로직 검토 필요

### B-5. ✅ baseline.json 갱신 (2026-04-30 완료)
**조치**: 옵션 2 (사용자 승인 chmod +w) 채택. 8회 측정 결과:
- 측정값 (8 samples, --runs=10 --seed=42): 0.4368, 0.4386, 0.4401, 0.4407, 0.4459, 0.4491, 0.4525, 0.4565
- mean = 0.4444, median = 0.4407, stdev = 0.0075, range = 0.0197
- baseline.json 에 저장된 측정값: **0.4491** (8번째 샘플, mean 근접)

**부작용 발견**: 동일 seed=42 에서도 측정값이 ±0.01 변동 → **sim 비결정성**. seed 가 RandomNumberGenerator 에 정상 전달되지만 다른 출처에서 randomness 유입 추정. 별도 조사 필요 → B-7 신규 등재.

### B-7. ✅ sim 비결정성 진단 + 수정 (2026-04-30 완료)
**원인**: `combat_engine.gd:475` (separation jitter) + `mechanics_handler.gd:150` (critical hit roll) 가 **글로벌 `randf()`** 호출. seed 와 무관하게 Godot 글로벌 RNG state 사용 → 같은 seed 에 다른 결과.

**수정**:
- `combat_engine.gd`: `_rng: RandomNumberGenerator` 추가 + `set_seed()` 메서드 + 글로벌 `randf()` → `_rng.randf()`
- `mechanics_handler.gd`: `_e._rng.randf()` 사용
- `headless_runner.gd`: 매 라운드 `engine.set_seed(_seed + round_num * 100003)` 호출
- `unit_tournament.gd`, `preset_parity_runner.gd`: 동일하게 `engine.set_seed()` 추가
- UI 경로 (`game_manager.gd`): `_init()` 에서 `_rng.randomize()` — 기존 비-deterministic 동작 유지

**검증**:
- 5회 측정 (seed=42, runs=10): 모두 **0.445902** 동일. variance 0.
- GUT 테스트 921건 모두 통과.
- baseline.json 갱신: 0.4491 → **0.445902** (이제 결정적 측정값)

### B-6. stale baseline 감지 hook (P5 사다리 검토)
**Why**: Tier 0 보호로 baseline 이 자동 갱신 안 되어, 카드 변경 후 한참 지나서 누적 영향 발견 위험. 본 세션의 -0.10 회귀가 그 사례.
**제안**: PostToolUse hook — 마지막 baseline 갱신 commit 이후 카드/genome 변경이 일정 수 이상 누적되면 경고.
**우선순위**: 낮음 (P3) — 즉시 위험 아님

### B-4. ✅ AI Layer 2 baseline 회복 (2026-04-30 완료)
**조사 결과**:

- 기존 baseline 16일 stale (마지막 갱신 `d745193`, 2026-04-14). Stale 전략 이름 (`steampunk_focused` 등) → 현재 `soft_steampunk` 등.
- 재측정 (20 run × 7 strategy = 140 run, seed=42): `weighted_score = 0.4457`
- 결정성 검증: 2회 측정 byte-identical
- baseline 갱신: 0.4384 → **0.4457**
- Layer 1 baseline 0.4459 와 갭 = **0.0002** (사실상 동등, noise floor 내)

**전략별 승률** (handoff "0% 붕괴" 패턴 검증):
| Strategy | Win rate | avg_hp |
|----------|----------|--------|
| soft_steampunk | 5% (1/20) | -22.7 |
| economy | 10% (2/20) | -21.8 |
| soft_druid | 10% (2/20) | -23.1 |
| adaptive | 15% (3/20) | -18.6 |
| soft_military | 20% (4/20) | -12.9 |
| soft_predator | 25% (5/20) | -14.9 |
| aggressive | 30% (6/20) | -5.3 |

→ 0% 붕괴는 5–10% 로 약간 회복됐으나 **여전히 매우 낮음**. weighted_score 회복은 다른 축 (board_utilization 0.67, dominance_moment 1.00, AI quality 0.77) 의 개선 누적 결과로 추정.

**AI quality 4축**:
- card_diversity: 1.0000 (max — 풀 활용 양호)
- board_strength_curve: 0.9663 (CP 단조 성장)
- economy_efficiency: 0.6682
- merge_rate: 0.4577 (★합성 빈도 낮음 — 개선 여지)

**완료 조건 충족**: weighted_score(0.4457) ≈ Layer 1(0.4459). Layer 2 autoresearch gradient 신호 회복.

**다음 단계 영역**:
- soft_X 의 5–10% 승률 — 풀 잠금 (B-3) + 카드 너프 누적 (B-2) 합작. autoresearch 로 ai_params 개선 시도 가치 있음.
- ~~B-3 의 adaptive 드루이드 회피~~ — 2026-06-02 B-8에서 완료. adaptive Druid zero coverage 5장→2장.

### B-8. ✅ adaptive 드루이드 회피 진단 + 수정 (2026-06-02 완료)
**조사 결과** (`traces/experiments/009-druid-ai-avoidance.md`):

- 재현: adaptive가 `dr_origin`, `dr_deep`, `dr_spore_cloud`, `dr_world`, `dr_resonance` 5장을 한 번도 구매하지 않음.
- 원인: R4 이후 카드 2장 수준의 작은 초반 리드만으로 dominant theme을 확정 → Military 고정 후 Druid engine/payoff가 full off-theme penalty를 받아 음수 점수로 탈락.
- 수정:
  - `AIHelpers.detect_dominant_theme`: best theme 최소 3장 + 2장 리드일 때만 adaptive commit.
  - `AIThemeScorer`: Druid producer 보유 시 payoff 구매 보너스, Druid 카드 보유 시 engine producer 구매 보너스.
  - `dr_world` unit-cap penalty가 있으면 Druid synergy 보너스보다 우선.
- 결과:
  - evaluator card_coverage 0.1896 → 0.2130
  - Druid theme coverage 0.1896 → 0.2468
  - adaptive Druid buys 25 → 60
  - adaptive Druid zero coverage 5장 → 2장 (`dr_wt_root`, `dr_resonance`)
  - weighted_score 0.4614 (`+0.0155` vs baseline)
- 잔여: `soft_druid` 자체 승률은 여전히 0/20. 다음 AI 작업은 Druid-only recognition이 아니라 S-2 전략 승률/ai_params 쪽.

---

## P1 — UI / 게임 플레이 미완

### G-1. ✅ 커맨더 선택 UI (런 시작) — 완료 (2026-07-01)
- 완료: `commander_select_popup` 추가. 런 시작 시 7종 커맨더 선택 → `GameState.commander_type` 세팅 후 기존 build flow 진입.
- 완료: 단조사 시작 보너스. 첫 빌드 확정 전 커먼 업그레이드 3택1 → 필드 카드 1장에 무료 부착.
- 완료: 커맨더 시대 기준 일반 업그레이드 상점 R1 공개 + 단조사 커먼 할인 가격 표시.
- 완료: 선택 팝업 계약 테스트 추가 (`test_commander_select_popup.gd`).
- 완료: 수집가 시작 상점 T2+ 4장 보장. UI 상점과 headless sim 상점 모두 첫 refresh 1회만 적용.
- 완료: 전략가 영웅 능력 UI. 빌드 페이즈에서 `SWAP (H)`로 보드 카드 2장 교환, 빌드당 1회.

### G-2. ✅ 부적 선택 UI + 적용 — 1차 완료 (2026-07-01)
- 완료: 런 시작 시 `TalismanSelectPopup`에서 12종 부적 선택 → `GameState.talisman_type` 반영.
- 완료: 12종 자동/상점/전투 효과는 기존 `Talisman` hooks와 UI flow에 연결.
- 완료: 녹슨 렌치 `DETACH (D)` 빌드 페이즈 분리 UI 추가. 마지막 업그레이드 제거 + 50% 테라진 환급.
- 잔여: 메타 진행/해금/저장 연동은 G-4에서 처리.

### G-3. ✅ 업그레이드 상점 UI (테라진 구매) — 1차 완료 (2026-07-01)
- 완료: BuildPhase에 R1부터 업그레이드 상점 2칸 표시. 커먼/레어 업그레이드를 테라진으로 구매하고 필드 카드 선택 즉시 부착.
- 완료: 명시적 `REROLL (T)` 버튼 추가. 테라진 부족, 대상 선택 중, 녹슨 렌치 분리/전략가 교환 중에는 리롤 비활성.
- 완료: 구매 취소/대상 없음/대상 invalid 시 테라진 환불 및 `upgrade_refunded` 신호 emit.
- 완료: 구매 가능 여부에 따라 업그레이드 카드 표시를 흐리게 하고 비용 색상을 변경.
- 완료: 단조사 커먼 할인, 군수공장 할인, 터진 자루 상점 슬롯 +1과 공존.
- 잔여: 업그레이드 부착 대상 추천/비교 UI, 업그레이드별 상세 툴팁 고도화.

### G-4. ✅ 메타 진행 / 런 시작 화면 — 1차 완료 (2026-07-01)
- 완료: `RunStartScreen` 추가. 게임 진입 시 프로필 요약을 먼저 보여주고 `START RUN` 이후 커맨더/부적 선택으로 진행.
- 완료: `MetaProgress` 저장 모델 추가. `user://meta_progress.cfg`에 시작/완료 횟수, 승리 수, 최고 라운드, 해금 커맨더/부적, 최대 난이도 저장.
- 완료: 초기 해금은 `replay.md` 기준으로 커맨더 2종(도박꾼/양성가), 부적 3종(부싯돌/양면 동전/금간 해골), 난이도 1.
- 완료: 커맨더/부적 선택 팝업이 해금 목록 필터를 받을 수 있음. 기본 테스트 모드에서는 기존처럼 전체 목록 표시 유지.
- 완료: 런 시작/종료 시 메타 저장 갱신. 난이도 클리어 보상은 다음 난이도 해금 데이터까지만 반영.
- 완료: 난이도 선택 버튼 추가. 해금된 최대 난이도 안에서 선택하고 런 시작 시 `GameState.difficulty`에 반영.
- 완료: 난이도별 전투/경제 modifier 1차 적용. D2 HP, D3 시작 골드, D4 적 수, D5/D7 보스 업그레이드, D6 상점/리롤, D7 ATK, D8 플레이어 HP가 live/sim 공통 경로에 연결.
- 완료: 난이도 승률 sweep 도구 추가. `godot/sim/difficulty_sweep_runner.gd`로 D1-D8 clear rate/라운드별 승률/전략별 승률 측정 가능.
- 완료: 1차 캘리브레이션. D3 고정 -3g는 현재 3g economy에서 cliff라 13→10 상대 페널티로 스케일 조정. D4 적 수 ×1.3은 clear 0% cliff라 ×1.15로 보정.
- 완료: D5-D8 후속 캘리브레이션(2026-07-02). D4 적 수 ×1.15도 D4 cliff가 남아 ×1.10으로 완화. D7 적 ATK ×1.30은 초반부터 clear 0%를 만들어 ×1.10으로 완화. D7 보스 업그레이드는 R12 레어, R15 에픽으로 지연하고 R15의 레어+에픽 중첩을 제거.
- 완료: 업적 기반 커맨더/부적 해금 조건 추가. 런 종료 시 최고 필드 유닛 수, 장착 업그레이드 수, 필드 유니크 카드 수, 연승, 판매 수, 성장 이벤트, ★2+ 카드 수, 수적 우위 승리를 평가해 잠긴 보상을 해금.
- 완료: 난이도 클리어 전용 부적 해금 추가. D2/D3/D5/D7 클리어가 각각 유리 눈/구리 전선/황금 주사위/전쟁 북을 해금.
- 잔여: 상세 메타 진행 화면, D7-D8 고난도 사람 플레이 표본/추가 대형 sweep 기반 미세 튜닝.

### G-5. ✅ 튜토리얼 / 온보딩 — 1차 완료 (2026-07-01)
- 완료: 런 시작 화면에 첫 런 가이드 표시. 상점 구매/보드 배치, BUILD→성장 체인→전투 흐름, 3장 자동 ★합성을 짧게 안내.
- 완료: `MetaProgress.tutorial_seen` 저장. `START RUN` 이후 다음 런부터 첫 런 가이드를 접음.
- 완료: 런 시작 화면에 다음 해금 목표와 최근 해금 목록 표시.
- 잔여: 실제 플레이 중 단계별 튜토리얼 오버레이, 카드/업그레이드 툴팁 중심 심화 온보딩.

### G-6~G-11. 자율 진행 큐 — 난이도 일시 동결 (2026-07-02 셋업)
- 운영 방침: D1-D8 난이도 수치는 버그 수정 외에는 건드리지 않는다. 다음 완성도 작업은 플레이어가 런/해금/업그레이드/성장 체인을 이해하는 데 필요한 UI와 피드백부터 진행한다.
- G-6 완료: `RunStartScreen`에 접힘형 `PROGRESS` 상세 패널 추가. 전체 커맨더/부적 해금 상태, 완료 업적, 잠긴 목표를 런 시작 전 확인 가능.
- G-7 완료: 업그레이드 구매/무료 업그레이드 대상 선택 시 선택 중인 업그레이드 효과, 필드 카드별 슬롯 상태, full slot 비대상 표시를 overlay preview로 보여준다.
- G-8 완료: 첫 런 BuildPhase에 dismiss 가능한 `TUTORIAL` 힌트 패널 추가. 카드 구매, 벤치→필드 배치, 업그레이드 구매, 업그레이드 대상 선택, BUILD 확정 준비 상태에 맞춰 문구가 갱신된다.
- G-9 완료: `ChainVisual`에 체인 카운터, 페이즈, 최근 source→target 이벤트 로그, 완료 보상 요약을 추가했다. 빈 상태에서는 새 로그 패널을 숨기고, 실제 체인 신호가 들어오면 최근 성장 원인을 보여준다.
- G-10 완료: `ShopLogic.reroll()`에 선택적 trigger callback을 추가하고 `HeadlessRunner`가 ON_REROLL 결과를 골드/테라진/레벨업 할인에 반영한다. `sp_interest` 리롤 성장과 `ne_pawnbroker` 리롤 할인 모두 sim 경로에서 발동한다.
- G-11 완료: 이미 구현된 보스 보상/시스템 미결 항목을 현재 코드 상태와 맞췄다. 보스 보상 27종, 테라진 1차 경제, 리플레이/메타/난이도 1차 구현, 적 파워 곡선, 업그레이드/Rusty Wrench/Alchemist epic shop, 금간 해골 상한 문구를 정리했다.
- 완료 계획: `Plans.md`의 "Playable Prototype Completion After Difficulty" 참조. 다음 Active Plan은 "Prototype Hardening After Player-Facing Loop".
- H-1~H-6 완료: desc_gen multi-block listen separation, sim pending free-reroll parity, combat talisman regression coverage, 합성 결과 HUD + 체인 라인 순번 표시, sim 다양성 triage, AI bench-space 판매 버그 수정을 닫았다. 다음 Active slice는 military target warning cleanup 또는 focused 전략 payoff 후속.

---

## P2 — 시뮬 / 밸런스 (정원 확정 후)

### S-1. card_coverage 23% → 70% 추격
**원인 후보**:
- `shop_picker` 가중치 편향
- AI 빌드 경로의 테마 편식 (theme_ratio_variance 0.405)
- T4/T5 카드 도달 빈도 낮음
**접근**: Layer 2 autoresearch (AI 결정) + Layer 1 (적 CP / 경제) 동시 탐색

### S-2. 전략 다양성 (σ < 0.10)
- 현재 max 0.8 (adaptive/soft_predator) / min 0.2 (soft_druid)
- **soft_druid 0% 탈출**이 ai_program.md 명시 목표
- 드루이드 빌드 자체가 경쟁력 부족인지, AI 평가 함수가 드루이드 인지 못 하는지 분리 필요
- 2026-07-02 H5/H6 재측정: 140-run 기준 weighted 0.4903, card_coverage 0.2195. focused 최저는 여전히 soft_steampunk 2/20, soft_druid 3/20이라 전략 다양성 후속은 payoff/전환 안정성 쪽이 우선.
- 2026-07-02 H7 완료: Military `revive_scope_override` 전용 target이 generic `r_conditional` dispatcher에서 선해석되며 발생하던 batch warning을 제거. full GUT 1141/1141.
- 2026-07-02 H8 완료: full GUT warning total을 8개에서 0개로 정리. 남은 ObjectDB/resource 메시지는 Godot 종료 시점 기존 잔여 이슈.

### S-3. 평균 승률 압축
- 현재 52.9%. 감정 곡선 목표: R1-R3 80%+ → R8-R12 30-60% → R13-R15 20-50%
- `cp_curve` upper bound 50.0까지 열려있으나 후반 라운드 적 강화 부족 추정

---

## P3 — 시각 연출 / 폴리시

- 성장 체인 시각 연출 1차 완료 (체인 카운터, 페이즈, 최근 source→target 로그, 라인 위 순번 표시). 잔여: ★별 이펙트, 사운드, 유닛 성장 애니메이션 polish
- 합성 시각 연출 1차 완료 (최근 합성 결과/보상 상태 HUD). 잔여: 파티클, 카드 합체 애니메이션
- 트리거 발동 순서 시각화 후속 (현재 최근 이벤트 로그로 source→target은 표시, 왼→오 진행 강조는 미구현)
- 카드/유닛 아트 (현재 Kenney CC0 placeholder)

---

## P4 — 후순위 (Phase B/C)

- 적 파워 곡선 수치 확정 (P2 sim 결과 + 플레이테스트 기반)
- 경제 수치 미세조정 (테라진 가격/수입)
- 난이도 8단계 고난도 미세 튜닝 (선택/해금/UI/live+sim 적용은 1차 구현 완료)
- 카드 풀/★ 템플릿 후속 검증 (68장 전 카드 YAML/codegen 등록 완료. 잔여는 신규 카드 추가 시 drift guard 유지)
- PvP 모드 (PvE 확정 후)
- 플랫폼 결정 (모바일 / 데스크톱)

---

## 기술부채 (active, [docs/design/backlog.md](../docs/design/backlog.md) 와 동기화)

본 영역의 새 항목은 docs/design/backlog.md 에 기록. 본 문서엔 **구현 우선순위 영향만** 표시.

| 항목 | 영향 | 우선순위 |
|------|------|---------|
| desc_gen multi-block listen 분리 (`pr_transcend` UI 오해) | 해결됨 | H1에서 회귀 테스트 + 설계 문서 동기화 완료 |
| sim ON_REROLL trigger | 해결됨 | G10에서 paid reroll trigger callback과 `HeadlessRunner` 반영 완료 |
| sim pending free-reroll 생성/소비 | 해결됨 | H2에서 `ShopLogic` 무료 리롤 소비, chain callback 적립, 보스 매턴 충전, AI reserve 우회 반영 |
| `_c()` flat hoist 전면 제거 | 장기 리팩터링 | 낮음 — 별도 세션 |
| multi-block scalar timing_override 누락 | latent (현재 카드 0건) | 낮음 — 발생 시 |

---

## 다음 1주 권장 스프린트

1. **합성/체인 polish** 또는 **P2 sim 다양성 회복** 중 표본 필요도에 따라 선택

> 자문: "이 스프린트 끝에 사용자가 '런 1회 풀로 돌려본다'가 가능한가?"
> — 현재 Yes. 다음 스프린트는 오해를 줄이고 반복 플레이/검증 품질을 높이는 단계.
