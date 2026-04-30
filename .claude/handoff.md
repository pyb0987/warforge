# Handoff — B-3 + B-4 완료 (2026-04-30, 2nd session)

## Status: ready

이번 세션은 **B-3 (카드 풀 활용도 분해) + B-4 (AI Layer 2 baseline 회복)** 까지 완료.
다음 세션은 **soft_X 5–10% 승률 회복** (S-2 / autoresearch) 또는 **드루이드 회피 진단** (B-3 follow-up) 부터 시작 가능.

## 이번 세션 변경사항 (커밋 2건)

| Commit | 내용 |
|--------|------|
| `1e19801` | docs(traces): B-3 카드 풀 활용도 분해 — theme lock 진단 |
| (pending) | chore(ai): ai_baseline.json 갱신 — Layer 1 동등 회복 (B-4) |

## 최종 상태

- **Layer 1 baseline**: 0.445902 (deterministic, B-7 fix 후)
- **Layer 2 AI baseline**: **0.4457** (B-4 완료 후 — 갭 0.0002, 사실상 동등)
- **AI quality**: 0.7730 (card_diversity 1.0, board_strength_curve 0.97, economy 0.67, merge 0.46)
- 카드 풀: 68장 확정. 0 dead, 19 weak, 49 active
- GUT 921/921 통과 (B-7 fix 이후 변경 없음)
- main 동기화 (33 commits ahead of origin/main, 미푸시)

## B-3 핵심 finding

### Evaluator card_coverage = 0.1896 의 진짜 원인
- **드루이드 테마** 가 병목 (0.1896, 다른 테마 0.23–0.28)
- **0장 dead** — 모든 68장이 5% 이상 등장
- 신규 13장 (0fd2d5e) 0 dead / 3 weak / 10 active. **풀 확장 직접 영향 가설 REJECT**
- 진짜 원인: **AI theme lock**
  - soft_X 4종이 자기 테마 외 21–26장을 안 산다
  - adaptive 마저 드루이드 5장 (`dr_deep`, `dr_origin`, `dr_resonance`, `dr_spore_cloud`, `dr_world`) 회피
  - economy 는 정반대 — 66/68 카드 구매 (풀 활용 양호)

### 0% 붕괴 원인 분리
- soft_steampunk: 풀 잠금 + 너프 누적 = 5%
- soft_druid: 풀 잠금 + AI 의 드루이드 시너지 평가 부재 가설 → 10%
- economy: 풀 활용 정상이지만 10% — **풀 문제 아님, 다른 메커니즘**

## B-4 핵심 finding

### baseline 16일 stale 발견
- 마지막 갱신: 2026-04-14 (`d745193`). 전략 이름 stale (`steampunk_focused` → `soft_steampunk` 미반영)
- 재측정 (20 run × 7 strategy, seed=42): **0.4457**
- 2회 측정 byte-identical → 결정성 확인됨

### 갭 해소 메커니즘 (자연스러운 회복)
- B-7 결정성 fix 직접 효과는 작음 (variance 0 ↔ 0.0075)
- **누적 효과 합산**: 군대 strict_anti, adaptive R1 가드, has_bench_space fix, 기타 4월 18~26 AI/sim 개선
- AI quality 0.69 → 0.77 (card_diversity max, board_strength_curve 0.97)

### 잔존 문제 (다음 세션 영역)
- **승률 분포 좁음**: 5–30% (max 30%, aggressive). Layer 1 의 σ < 0.10 목표 미달
- **soft_X 5–10%**: 풀 잠금 (B-3) + 카드 너프 (B-2) 합작
- **adaptive 드루이드 회피**: ai_agent.gd 평가 함수에서 드루이드 시너지 인식 부재 추정

## 다음 세션 진행 — 옵션 3가지

### 옵션 A. AI v2 의사결정 함수 검토 (B-3/B-4 follow-up)
**Why**: adaptive 가 드루이드 5장 회피 → 평가 함수에 드루이드 시너지 부재 가설 검증
**파일**: `godot/sim/ai_agent.gd` (`STRATEGY_NAMES`, theme bonus 로직), `ai_theme_scorer.gd`
**예상 hours**: 2–4시간
**완료 조건**: adaptive 가 드루이드 카드 회피하지 않음 (퍼-strategy zero-coverage 5장 → 0–2장)

### 옵션 B. autoresearch Layer 2 시도 (S-2 영역)
**Why**: B-4 baseline 회복으로 gradient 신호 정상화. 17개 ai_params 탐색 가능.
**명령**:
```bash
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=30 --strength=0.20 --runs=20
```
**예상 hours**: 2–6시간 (autoresearch 자체는 자율, 모니터링만)
**완료 조건**: weighted_score ≥ 0.50 (현재 0.4457) OR soft_druid 0% 탈출

### 옵션 C. UI 작업 (G-1 커맨더 선택, P1)
**Why**: sim 영역은 회복됨. UI 미완 5종 (G-1~5) 이 "런 1회 풀로 돌려본다" 의 진짜 병목.
**파일**: 새 scene + `commander.gd` UI 연결
**예상 hours**: 4–8시간 per scene

## 미해결 backlog (다음 세션 영역 외)

- **B-6**: stale baseline 감지 hook (P3, 별도 세션) — **본 세션이 16일 stale 의 2번째 사례**, 재발 검토 가치 있음
- **G-1~5**: UI 미완
- **S-1~3**: card_coverage 70% 추격, 전략 σ < 0.10, 평균 WR 압축
- **기술부채**: desc_gen multi-block listen 분리 (높음), sim ON_REROLL trigger (중)

상세는 `.claude/backlog.md` 참조.

## Next entry point

```bash
# 옵션 A 시작
cat godot/sim/ai_agent.gd | head -50
grep -n "druid\|theme" godot/sim/ai_theme_scorer.gd | head -20

# 옵션 B 시작 (autoresearch)
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=30 --strength=0.20

# 옵션 C 시작 (UI)
ls godot/scenes/popups/   # 기존 popup 패턴 참조
```
