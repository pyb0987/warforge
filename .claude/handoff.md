## Status: paused
## Last completed: YAML → description validity 4-iteration multi-review 완료 (Critic 2: 5 → 7 → 8 → 9 PASS). iter4 LOW 3건까지 해결, 숨은 bug 3건(dr_deep tree_bonus mult, ml_assault swarm_buff enhanced_count, ml_tactical enhanced_shield_bonus) runtime 연결 — 2026-04-17, 898/898 passing

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
- [ ] **시뮬 밸런스 검증**: ★3+R10 power curve, 정예형 vs 물량형 승률, 훈련 가속 영향
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
- [ ] OBS-047 (S5-R14): ★3 캐스케이드 머지 시 중간 레어 업그레이드 미지급 의심 — GUT 테스트로 검증

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
- [ ] ai_build_path.gd → ai_agent.gd 연결 (plan: piped-jumping-unicorn.md)
- [ ] AI v3 (build path 연결) 후 genome 재탐색
- [ ] Tier B multiplicative 파라미터 — 비군대 CP 격차 해소
- [ ] starting_resources mutator 구현

## Next entry point:

**옵션 A (권장)**: 시뮬 밸런스 검증
- 목적: 재설계 후 ★3+R10 조합이 실제로 엔드게임 "사기" 효과로 작동하는지
- 측정: 정예형/물량형 승률, 훈련 가속 복리 영향, ★3 도달 타이밍
- 기존 시뮬 인프라 사용: `godot/sim/`

**옵션 B**: OBS-047 (S5-R14) ★3 캐스케이드 머지 레어 업그레이드 미지급 검증
- GUT 테스트로 재현 시도
- 핫픽스 가능성 높음

**옵션 C**: AI v3 (build path 연결)
- ai_build_path.gd → ai_agent.gd 연결 (plans/piped-jumping-unicorn.md)
- 후속으로 AI 재탐색 가능

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
