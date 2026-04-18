## Status: paused
## Last completed: 군대 AI drift 수정 + CHAIN_PAIRS 추가 (2026-04-18). 4 commits (125698d, dfb8f6d, b245482, b414b3c).
- ai_theme_scorer: RANK_THRESHOLDS R3/5/8 → R4/R10 통일, TRAINING 카드 스왑 반영
- ai_synergy_data: THEME_SYNERGY/CRITICAL/STRATEGY 군대 부분 재작성, CHAIN_PAIRS 군대 체인 추가
- ai_build_path: military_elite/mass paths 재설계 반영 (branch=barracks vs conscript)
- 4-seed sim: weighted_score 0.4529→0.4545, soft_military 0.463±0.096 (변동 noise 범위)

## 이전 완료: 설계문서 YAML 중복 정리 (2026-04-18, df83fd1).

## 이전 완료: baseline.json 재촬영 + program.md 동기화 + OBS-047 GUT 커버리지 검증 (2026-04-18).

## Current state:

### 군대 R4/R10 재설계 (2026-04-16, 완료)
- **설계**: R3/5/8 임계점 → R4/R10 milestone 2단계 축소. ★(양)/R(질) 두 축 직교.
- **10장 카드 전체 재구성** + 징병국↔전진기지 스왑, 돌격편대 BS→RS 전환 + 재정의
- **Phase 1~4 구현 12 action types**: enhance_convert_card, spawn_unit, crit_buff, crit_splash, rank_buff_hp, buff, lifesteal, grant_gold, grant_terazin, high_rank_mult, conscript_pool_tier, revive_scope_override, upgrade_shop_bonus, enhance_convert_target, spawn_enhanced_random (총 15개)
- **새 target 이름 4개**: left_adj, far_military, event_target_adj, far_event_military
- **Enhanced 유닛 6종** (`ml_*_enhanced`) unit_db.gd 등록
- **Multi-review 5회 수행** — iter 5 "converging" + "stop_and_finalize" 권고
- **숨은 bug 2건 발견/수정**:
  - 군수공장 counter rewards key mismatch (`enhance_atk_pct` vs `global_military_atk_pct`)
  - 통합사령부 apply_persistent dead path (ml_command는 RS timing인데 chain_engine.process_persistent는 PERSISTENT만 순회 → revive가 실제로 동작하지 않던 상태)
- **78/78 GUT 테스트 통과**, 공통 R4/R10 전 10장 커버, combat integration 스모크 포함
- **Evolution trace**: `.claude/traces/evolution/012-military-r4-r10-axis-split.md`

### 이전 작업 (카드 텍스트 재작성, 이미 완료)
- 기획문서 5개 (55장 × 3★ = 165개) ★별 독립 형식 재작성
- 보스 보상 텍스트 27개 재작성
- card_descs.gd 165개 재작성
- OBS-039 해결: ne_merchant star_overrides (card_db.gd)
- OBS-045 해결: card_tooltip.gd — card_descs 우선 + ★별 template
- OBS-041 해결: keyword_glossary.gd (14키워드) + tooltip 호버 연동

### YAML SSOT 전환 작업 (2026-04-17, 완료)
- **trace 013**: r_conditional ★ parity validator (codegen 내장, exit 2)
- **trace 014**: 통합사령부 revive scope_override YAML target 직접 파싱
- **trace 015**: codegen silent drop 구조 제거 (CARD_DB_ACTIONS hard-fail)
- **docs/design/cards-military.md**: 효과 섹션 삭제 → YAML이 SSOT
- **Multi-review 2차**: PASS with known gaps → P0/P1/P2 순차 개선
- **description 4-iteration** (Critic 2 UX 5 → 9): 숨은 bug 3건 포함 처리
  - dr_deep tree_bonus.mult: bonus_growth_pct dead field → mult 이관, ★3=1.5 실적용
  - ml_assault swarm_buff: enhanced_count 런타임 연결 (atk buff + ms thresh 양쪽)
  - ml_tactical enhanced_shield_bonus: (강화) 유닛 보유 카드에 shield +%p 실적용
- **ml_academy R10 대체 bug fix**: rank 내림차순 순회 + tenure 공유 슬롯
- **keyword_glossary 확장**: 계급/랭크/부대/비(강화) 정의 추가
- **용어 통일**: "숲의 깊이" → "전체 나무 수" (5 파일)
- **Evolution traces**: 013, 014, 015
- **Review reports**: military-ssot-verification-2026-04-17, yaml-to-desc-validity-2026-04-17, yaml-to-desc-iteration2-2026-04-17

## Remaining:

### 군대 재설계 후속 (우선순위 순)
- [x] **시뮬 밸런스 검증** — 2026-04-18, reviews/sim-snapshot-2026-04-18.md.
  - soft_military 50% WR (soft_steampunk 55%와 근접, 다른 focused 테마 35~70% 범위 내 중간)
  - avg_hp +3.80 (다른 focused +10~14 대비 가장 낮음 → "이기되 빡빡하게" 설계 의도에 근접)
  - bug fix 3건(enhanced_count, enhanced_shield_bonus, tree_bonus.mult) 반영 후에도 과강/과약 없음
  - 단 거시 이슈 존재: weighted_score 0.4642 (목표 0.65), mean WR 54.3% (목표 5-10% 초과), card_coverage 15% (목표 70%), win_rate_band 0.0000 (emotional arc 붕괴)
  - baseline.json stale (strategy naming 불일치) — 향후 delta 비교를 위해 재촬영 필요
- [x] **YAML delta/cumulative validator** (P5 structural debt, multi-review iter 5 합의) — 2026-04-17, trace 013.
  - 구현: `validate_r_conditional_star_parity()` + per-card `star_scalable_actions` allowlist
  - 검증: 12 unit tests 통과, 3개 과거 bug 합성 재현 모두 차단 (exit 2)
- [x] **통합사령부 revive scope_override YAML↔코드 일관성** — 2026-04-17, trace 014.
  - MilitarySystem.resolve_command_revive + resolve_revive_scope helper 도입
  - game_manager._materialize_army 리팩터: rank 하드코딩 → YAML target 직접 파싱
  - 10 신규 테스트 (rank 0/4/9/10 + target 3종 + 경계 + fallback)
- [ ] **OBS-022 (S2-R8)**: 군대 ★2 도달 속도 < 게임 진행 속도 — 재설계 후 재측정 필요

### 일반 버그/검증
- [x] **card_tooltip.gd `\x01` parse error** — 2026-04-17, commit f8d824b. `char(1)` placeholder로 교체.
- [x] **OBS-047 (S5-R14)**: ★3 캐스케이드 머지 시 중간 레어 업그레이드 미지급 의심 — 2026-04-18 검증 완료.
  - `shop.gd:98-104` cascade 시 step마다 card_merged emit → `build_phase.gd:_on_card_merged` 매 ★1→★2 step에서 rare 팝업 호출
  - GUT 커버리지: test_merge_system.gd(cascade_returns_2_steps, cascade_step1_has_star2_for_reward, cascade_preserves_upgrades_through_star3) + test_build_phase_merge_bonus.gd(star1_to_star2 rare popup)
  - 53/53 통과

### 밸런스/설계 결정 (플레이 데이터 축적 필요)
- [ ] OBS-013 (S1-R9): 드루이드 ★ 합성 시 유닛 상한 도달 패널티
- [ ] OBS-029 (S3-R12): R11→R12 CP 점프 +42% 과도
- [ ] OBS-033 (S4-R2~R3): HP=30 초반 2패 → hp=15, 전략 여지 제한
- [ ] OBS-034 (S4-R6): 고티어 CP/gold ≈ 저티어 → 용병 가치 부재
- [ ] OBS-035 (S4-R7~R11): ★2 후 5연속 전멸 무풍지대
- [ ] OBS-042 (S5-R5): 보스 보상 밸런스 (영구 >> 즉시)
- [ ] OBS-048 (S5-R14): 세계수 ≤30 조건이 ★합성을 패널티화

### 게임 설계 (별도 설계 세션 필요)
- [ ] OBS-025 (S2-R11): 후반 빌드 페이즈 빈 턴 반복 — 빌드 페이즈 자동 단축 검토

### AI 관련
- [x] ai_build_path.gd → ai_agent.gd 연결 (이미 9c6c8a4에서 완료, 확인 2026-04-18)
- [x] 군대 AI drift 수정 (4 commits, 2026-04-18)
- [x] **군대 AI 추가 개선** — 2026-04-18, commit 05dd53e.
  - 2. POSITION_PRIORITY — **dead code**로 확인(ai_position_solver가 timing 기반 동적 산출). 스킵.
  - 3. _score_buy_military cross-chain (TR/CO 체인 양방향 +4) 추가
  - 4. _value_military enhanced_count 보너스 (assault/tactical, 1기당 +0.5 cap 20기)
  - 신규 테스트 4건, 902/902 GUT 통과
- [x] AI 행동 트레이스 인프라 — 2026-04-18, commits 855a9bc / b059d03.
  - ai_tracer.gd + --trace-dir + scripts/analyze_ai_trace.py
  - sell 이벤트 + score breakdown 확장
  - 인사이트: `.claude/traces/ai_runs/insights-2026-04-18-{baseline,deep-dive}.md`
- [x] **has_bench_space() 구조 버그 수정** — 2026-04-18, commit bd897f1.
  - 원인: _try_buy_best가 board+bench 빈칸을 체크했지만 shop은 bench만 사용 → 58% 구매 실패
  - 효과: predator 70→85%, aggressive 65→80%, steampunk 45→55% / merges 2x
- [x] **position_solver _THEME_ADJ_HINTS 확장** — 2026-04-18, commit 260a93c.
  - YAML target 감사 → theme_system 12장 추가 (druid/predator/steampunk/military)
  - 'all' adj_type fallthrough 버그 수정
  - **soft_druid WR 25→45% (+20%p), R15 42→82% (+40%p)**
- [x] **adaptive R1 levelup 가드 + reroll 트레이스 누락 수정** — 2026-04-18, commit fb8263c.
  - adaptive R1 100% 패배 (R1 levelup → 2-card army → 0% WR) 원인 수정
  - _play_aggressive/_play_adaptive reroll emit 추가 (진단 정확도)
  - **adaptive WR 25%→75% (+50%p)**
- [ ] **soft_military 35% 정체** — 별도 조사 필요 (R8/R15 약점, C fix 이후도)
- [x] 드루이드 AI drift 수정 — 2026-04-18, commit 5807f83.
  - P0: 유닛캡 페널티 재정의 (dr_world 자체만), TREE_THRESHOLDS 근접 보너스 추가
  - P1: DRUID_PAYOFF↔PRODUCER 시너지 교정, dr_world THEME_SYNERGY forest_depth 반영
  - 신규 테스트 5건, 906/906 GUT 통과
- [ ] soft_steampunk drift 점검 (51% WR, 동일 4-레이어)
- [ ] AI 안정화 후 genome 재탐색
- [ ] Tier B multiplicative 파라미터 — 비군대 CP 격차 해소
- [ ] starting_resources mutator 구현

## Next entry point:

**옵션 C (권장, 이제 남은 주요 작업)**: 거시 밸런스 autoresearch Phase
- 거시 이슈 4건(weighted_score 0.4679→0.65, mean WR 55.7%→5-10%, card_coverage 15%→70%, win_rate_band≈0 회복) 개선
- genome 재탐색 (적 CP 곡선 + enemy 스탯 튜닝)
- 긴 세션 (autoresearch skill + Tier 0 정책 준수)

**옵션 D**: AI v3 (build path 연결)
- ai_build_path.gd → ai_agent.gd 연결 (plans/piped-jumping-unicorn.md)

## 참고 파일

### 군대 재설계 (2026-04-16)
- `data/cards/military.yaml` — 10장 카드 단일 진실 소스
- `docs/design/cards-military.md` — 설계 의도 + 타임라인
- `godot/core/military_system.gd` — 15 action handlers + 공통 헬퍼 (1012 라인)
- `godot/tests/test_military_system.gd` — 78 테스트
- `.claude/traces/evolution/012-military-r4-r10-axis-split.md` — 진화 기록 + multi-review 5회 요약

### 시뮬 (Next entry point 옵션 A)
- `godot/sim/headless_runner.gd` — batch 시뮬 실행
- `godot/sim/best_genome.json` — Layer 1 고정값 (protected)

### 기타
- `docs/playtests/2026-04-{08,09,10,11}-session-analysis.md` — S1~S5 분석
- `.claude/plans/piped-jumping-unicorn.md` — AI build path 연결 계획

## OBS 검색
```bash
grep -n '🔴 open' docs/playtests/2026-04-*-session-analysis.md
```

## 군대 재설계 검증 명령
```bash
# 전체 테스트
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_military_system.gd -gexit

# codegen 정합성
python3 scripts/codegen_card_db.py --check
```
