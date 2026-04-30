# Backlog — 현재 상태 + 앞으로 할 일

> 마지막 갱신: 2026-04-30
> Branch: `claude/charming-jones-3aaeef` (main 동기화)
> Tests: 1017/1017 (handoff 기준, cache 재빌드 후)

설계 결정 / 기술부채는 [docs/design/backlog.md](../docs/design/backlog.md) 별도 관리. 본 문서는 **구현 로드맵**.

---

## 현재 상태 스냅샷

### 코드 / 구현 완료
- ✅ **Sprint 11** — 테마 시스템 4종 (`steampunk_system`, `druid_system`, `predator_system`, `military_system`) + `neutral_system`
- ✅ **데이터** — `unit_db`, `card_db` (codegen), `upgrade_db`, `boss_reward_db`, `keyword_glossary` autoload 등록
- ✅ **autoload** — `Commander`, `Talisman` 데이터 클래스 존재 (UI 미구현)
- ✅ **Popup UI 6종** — `battle_result`, `boss_reward`, `game_over`, `theme_choice` (ne_masquerade), `upgrade_choice`, `card_tooltip`
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

### B-3. 신규 13장 활용도 검증 (Critic 4 권고)
**질문**: `0fd2d5e` 커밋 확장분 13장이 sim 빌드 경로에 등장하는가? `card_coverage 0.19` (B-2 재측정) 이 죽은 카드 다수 때문인지, AI 미탐색 때문인지.
**완료 조건**: 카드별 등장 빈도 추출 → 죽은 카드 / 활성 카드 / 신규 아키타입 카드 분류 표.
**제안 절차**:
1. `headless_runner.gd` 또는 별도 스크립트로 70 run × 카드별 등장 횟수 카운트
2. 분류 임계: 등장률 < 5% = 죽은 카드 후보
3. 결과를 backlog 에 등재
**우선순위**: B-2 finding (soft_steampunk/druid/economy 0% 붕괴) 의 원인 분리에 도움 — 캡스톤 너프 영향 vs AI 미탐색 분별

### B-5. ✅ baseline.json 갱신 (2026-04-30 완료)
**조치**: 옵션 2 (사용자 승인 chmod +w) 채택. 8회 측정 결과:
- 측정값 (8 samples, --runs=10 --seed=42): 0.4368, 0.4386, 0.4401, 0.4407, 0.4459, 0.4491, 0.4525, 0.4565
- mean = 0.4444, median = 0.4407, stdev = 0.0075, range = 0.0197
- baseline.json 에 저장된 측정값: **0.4491** (8번째 샘플, mean 근접)

**부작용 발견**: 동일 seed=42 에서도 측정값이 ±0.01 변동 → **sim 비결정성**. seed 가 RandomNumberGenerator 에 정상 전달되지만 다른 출처에서 randomness 유입 추정. 별도 조사 필요 → B-7 신규 등재.

### B-7. sim 비결정성 진단 (B-5 부작용)
**증상**: `batch_runner.gd --seed=42 --runs=10` 동일 호출에서 weighted_score ±0.01 변동.
**가능 원인**:
- `Time.get_ticks_msec()` 또는 비-seeded 글로벌 RNG 사용처
- Dictionary iteration order (Godot 4 는 insertion-ordered 이지만 일부 경로 의심)
- multi-instance RNG 의 interleaving (state[`rng`] 외 hidden RNG)
**완료 조건**: variance 원인 파일/라인 식별 + seed 일원화 patch.
**우선순위**: 중 — autoresearch ADOPT 판정의 noise floor 직접 영향 (현재 stdev 0.0075 = 일반 ADOPT delta 와 동급)

### B-6. stale baseline 감지 hook (P5 사다리 검토)
**Why**: Tier 0 보호로 baseline 이 자동 갱신 안 되어, 카드 변경 후 한참 지나서 누적 영향 발견 위험. 본 세션의 -0.10 회귀가 그 사례.
**제안**: PostToolUse hook — 마지막 baseline 갱신 commit 이후 카드/genome 변경이 일정 수 이상 누적되면 경고.
**우선순위**: 낮음 (P3) — 즉시 위험 아님

### B-4. AI Layer 2 baseline 회복 (B-2 완료 후)
**Why**: ai_baseline weighted_score 0.438 < Layer 1 0.546. Layer 2 autoresearch 는 현재 Layer 1 baseline 미달 상태에서 시작 — gradient 신호 약함.
**완료 조건**: `ai_research/` 에서 Layer 1 baseline 동등 이상 회복 (≥ 0.54).

---

## P1 — UI / 게임 플레이 미완

### G-1. 커맨더 선택 UI (런 시작)
- `commander.gd`에 데이터 7종 등록 + TODO 4건 명시
- 화면 부재: 런 시작 시 커맨더 선택 → `GameState.commander_type` 세팅
- 의존: 전략가/단조사/수집가 시작 보너스 UI (단조사 = 커먼 업글 3택1)

### G-2. 부적 선택 UI + 적용
- `talisman.gd` 데이터만 존재. 12종 효과 적용 코드 / 선택 UI 없음
- 흐름: 메타 진행 → 부적 해금 → 런 시작 시 1개 장착

### G-3. 업그레이드 상점 UI (테라진 구매)
- `upgrade_choice_popup`은 ★합성 보상용. 일반 상점에서 테라진으로 구매하는 흐름 미구현
- ★1=커먼 / ★2=레어 / ★3=에픽 풀 분리 부착 흐름 검증 필요

### G-4. 메타 진행 / 런 시작 화면
- 현재 `main.tscn` 진입 즉시 build_phase 시작. 메뉴 / 메타 진행 / 커맨더 선택 / 부적 장착 화면 없음
- 해금 데이터 영속화 (save file) 미구현

### G-5. 튜토리얼 / 온보딩
- 트리거 체인 / 2층 이벤트 / ★합성 / 2화폐 학습 곡선 가파름. 첫 런 가이드 부재

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

### S-3. 평균 승률 압축
- 현재 52.9%. 감정 곡선 목표: R1-R3 80%+ → R8-R12 30-60% → R13-R15 20-50%
- `cp_curve` upper bound 50.0까지 열려있으나 후반 라운드 적 강화 부족 추정

---

## P3 — 시각 연출 / 폴리시

- 성장 체인 시각 연출 (체인 카운터, ★별 이펙트, 유닛 성장 애니메이션)
- 합성 시각 연출 (파티클, 카드 합체 애니메이션)
- 트리거 발동 순서 시각화 (왼→오 진행 표시)
- 카드/유닛 아트 (현재 Kenney CC0 placeholder)

---

## P4 — 후순위 (Phase B/C)

- 적 파워 곡선 수치 확정 (P2 sim 결과 + 플레이테스트 기반)
- 경제 수치 미세조정 (테라진 가격/수입)
- 난이도 8단계 상세 (replay.md 초안 → 구현)
- T1~T3 ★2/★3 카드 템플릿 (T4/T5 14장은 등록 완료, T1~T3 약 40장 잔여 — codegen 자동 처리되는지 검증 필요)
- PvP 모드 (PvE 확정 후)
- 플랫폼 결정 (모바일 / 데스크톱)

---

## 기술부채 (active, [docs/design/backlog.md](../docs/design/backlog.md) 와 동기화)

본 영역의 새 항목은 docs/design/backlog.md 에 기록. 본 문서엔 **구현 우선순위 영향만** 표시.

| 항목 | 영향 | 우선순위 |
|------|------|---------|
| desc_gen multi-block listen 분리 (`pr_transcend` UI 오해) | 사용자 노출 | **높음** — UI 작업 전 |
| sim ON_REROLL trigger 미처리 | sim 비대칭 (sp_interest, ne_pawnbroker 과소평가) | 중 — Sim 밸런스 작업 시 |
| `_c()` flat hoist 전면 제거 | 장기 리팩터링 | 낮음 — 별도 세션 |
| multi-block scalar timing_override 누락 | latent (현재 카드 0건) | 낮음 — 발생 시 |

---

## 다음 1주 권장 스프린트

1. **B-1 결정**: 사용자 확인 — 풀 정원 (확장 / Trim / 절충)
2. **desc_gen multi-block fix** (UI 직결, 다음 카드 작업 전)
3. **B-2 ai_baseline 회복** (sim 작업 진행 위한 gradient 확보)
4. 그 후 **G-1 커맨더 선택 UI** (런 시작 흐름의 시작점)

> 자문: "이 스프린트 끝에 사용자가 '런 1회 풀로 돌려본다'가 가능한가?"
> — 현재 No (커맨더 선택 / 메타 진행 화면 부재로 직접 main.tscn 진입만 가능)
