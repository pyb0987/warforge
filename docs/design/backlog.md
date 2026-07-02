# 미결정 항목

## 경제 (남은 결정)

| 항목 | 상태 | 비고 |
|------|------|------|
| 보스 보상 개별 내용 | 완료 (27종) | `docs/design/boss-rewards.md` 기준 R4/R8/R12 각 9종 확정. `BossRewardDB`/`BossReward` 구현 및 `test_boss_reward.gd`로 데이터+적용 경로 검증 |
| 테라진 가격/수입 조정 | 1차 구현, 미세조정 후보 | 승리/패배 2t/1t, 커먼 4t, 레어 8t, 업그레이드 리롤 1t로 live/sim 연결. 고난도·사람 플레이 표본 기반 미세조정은 후속 |

## 시스템

| 항목 | 상태 | 비고 |
|------|------|------|
| 업그레이드 시스템 | 대상 비교 UX 1차 완료 | 1슬롯 통일, 커먼/레어 테라진 상점, 에픽 보스/특수 보상, 구매 즉시 필드 카드 부착. 대상 선택 overlay에서 슬롯 상태와 효과 미리보기 표시 |
| 리플레이 시스템 | 1차 구현 완료 | 커맨더 7종, 부적 12종, 난이도 8단계 선택과 메타 해금/저장/UI 연결 완료. 고난도 표본 기반 튜닝은 후속 |
| 유물 시스템 | 불필요 | 부적 + 보스 보상 3회로 역할 충분 |
| 보조 태그 시너지 | 별도 시스템 불필요 | 카드 효과의 한 유형 (패시브 태그 참조). 카드 풀 설계 시 반영 |
| 적 파워 곡선 | 1차 구현 완료, 튜닝 지속 | `EnemyDB.generate`와 `Difficulty` 보정 레이어로 라운드별 적 생성, 보스 CP 보정, D5/D7 보스 업그레이드가 live/sim 공통 적용됨. D7-D8은 추가 표본으로 미세조정 |
| 전투 시스템 구체화 | 확정 | SC1 스타일. AS/Range/MS 유닛별. DEF 기본0, 업글로 부여. 가장가까운적 타겟팅 |
| 예시 카드 풀 세트 | 완료 (2026-04-30) | 68장 전 카드 YAML 등록 + codegen. 분배 24/11/11/11/11. multi-review veto-conditional pass — sim 회귀 진단 사후 액션은 .claude/backlog.md B-2/B-3 |

## 콘텐츠 & 폴리시

| 항목 | 상태 | 비고 |
|------|------|------|
| 테마/세계관 | 확정 | 4테마(스팀펑크/드루이드/포식종/군대) + 중립. 24/11/11/11/11 = 68장. 테마별 키워드 확정 |
| 아트 스타일 | 방향 확정 | SC 스타일. 프로토타입은 Kenney CC0 사용 |
| 성장 체인 시각 연출 | 1차 완료 | 체인 카운터 + 페이즈 + 최근 source→target 이벤트 로그 구현. ★별 이펙트, 사운드, 유닛 성장 애니메이션은 후속 polish |
| 메타 진행 상세 | 상세 화면 1차 완료 | 초기 해금, 난이도 해금, 업적 기반 커맨더/부적 해금, 첫 런 가이드 저장 흐름 구현. 시작 화면의 `PROGRESS` 패널에서 전체 커맨더/부적 해금 상태, 완료 업적, 잠긴 목표 확인 가능 |
| 난이도 곡선 상세 | 1차 구현 완료, 고난도 미세 튜닝 필요 | `Difficulty` 보정 레이어로 전투/경제/헤드리스 sim 연결. D4/D7 cliff 완화 완료. D7-D8은 70-run에서 희박한 clear 확인, 사람 플레이/대형 sweep 표본 필요 |
| PvP 모드 | 후순위 | PvE 확정 후 설계 |
| 플랫폼 | 후순위 | 기획 확정 후 결정 |

## 기술부채 (Phase 2 effect-timing 구조 개편 이월)

2026-04-20 Phase 2 B-direct 마이그레이션 중 "unified store" 80% 달성으로 멈춘 잔여 항목. C4 Convergence Critic이 지적한 drift 위험을 **합리적 수준에서 수용한 타협**. 밸런싱 작업 중에는 유지, 별도 리팩터링 세션에서 해결.

| 항목 | 종류 | 설명 |
|------|------|------|
| sim ON_REROLL trigger | ~~sim ↔ 게임 본체 비대칭~~ **해결** | `ShopLogic.reroll()`에 선택적 trigger callback을 추가하고 `HeadlessRunner`가 `chain_engine.process_reroll_triggers` 결과를 골드/테라진/레벨업 할인에 반영한다. 검증: `test_sim_shop_logic.gd`, `test_headless_runner.gd`, `test_steampunk_system.gd`, `test_pawnbroker_reroll.gd` |
| sim pending free-reroll 생성/소비 | ~~latent~~ **해결** | `ShopLogic.reroll()`이 pending 무료 리롤을 골드보다 먼저 소비하고 성공 시 ON_REROLL trigger를 발동한다. `HeadlessRunner`는 chain 시작 시 pending/round reroll을 live처럼 리셋한 뒤 보스 보상 매턴 무료 리롤을 충전하고, chain callback으로 `ne_pawnbroker`/`ne_scrapyard` 무료 리롤 적립을 state에 반영한다. AI reroll 조건은 무료 리롤 보유 시 gold reserve를 우회한다. |
| `_c()` flat hoist | 암묵적 계약 | `template["trigger_timing"]` 등 top-level accessor가 "첫 block의 hoist". multi-block 카드에서 대표 timing 개념이 암묵화. 주석 보강으로 완화, 장기적으론 전면 제거 |
| sim의 이중 쓰기 (max_activations) | ~~단일 진실 소스 위반~~ **해결** | `CardInstance.max_activation_override` 필드 + `get_max_activations()` + `can_activate_with` Option A 도입 (Task 4, 2026-04-21). `headless_runner` / `diagnostic_game` 의 template mutation 제거, 보스 `activation_bonus` 는 `chain_engine.activation_bonus` 일원화. `grep 'template\["max_activations"\]\s*='` 결과 0건 (test fixture 제외). |
| `retrigger` action 하드코드 | ~~latent~~ **해결** | ~~`chain_engine.gd:585-588`에서 `ROUND_START` 블록만 찾음. theme_system 타겟이면 actions 빈 리스트.~~ `validate_no_retrigger` codegen hard-fail 추가 (Task 2, 2026-04-20). YAML에 retrigger 등장 시 즉시 차단. |
| `impl: theme_system` 누락 validator 부재 | ~~사람 실수 방어~~ **해결** | `validate_impl_theme_system` (d18d1ce, v2 codegen)으로 해결. action 기반 검사. |
| `_find_block` first-match | ~~latent~~ **해결** | `_find_eff` push_error 강화 (Task 2, 2026-04-20). 4개 theme_system.gd에서 중복 매칭 시 runtime push_error 방출. |
| steampunk_system에 `apply_battle_start`/`apply_post_combat` 부재 | ~~theme_system 완결성~~ **해결** | `theme_system.gd` base class 에 `_warn_missing_override` push_error guard 추가 (Task 3, 2026-04-21). `impl: theme_system` 카드가 override 없는 hook에 도달 시 runtime 경고. apply_persistent 는 quiet 유지. |
| `is_threshold` + `impl: theme_system` mismatch | ~~latent~~ **해결** | ~~`chain_engine.gd:110-141`에서 `threshold_fired` 플립이 theme_system dispatch 전에 발생.~~ `validate_is_threshold_with_theme_system` codegen hard-fail 추가 (Task 2, 2026-04-20). |
| POST_COMBAT phase conditional_effects 누락 | ~~phase 비대칭~~ **해결** | `chain_engine.process_post_combat` 에 RS/OE/BS 와 동일한 conditional_effects 순회 추가 (Task 3, 2026-04-21). PC + conditional 조합 카드 silent drop 차단. |
| flat hoist 전면 제거 | 장기 리팩터링 | 위 flat hoist 의 전면 제거 = sim + AI evaluator + game_manager + tests의 수십 곳 마이그레이션. 현재 "v2 공식 backward-compat"으로 문서화한 상태. Phase 2 scope 초과 |
| multi-block projection: scalar action timing_override 누락 | latent | `codegen_card_db._project_v2_to_desc_gen_input`가 dict 값 actions에만 `timing_override` 주입. scalar 값(`gold: 5` 등)이 non-primary block에 있으면 설명에서 primary timing으로 오배치. 현재 multi-block 카드 1장(sp_warmachine)에 scalar 없음 |
| multi-block projection: 비-primary block conditional silent drop | ~~latent~~ **해결** | `validate_multiblock_nonprimary_conditional` codegen hard-fail 추가 (2026-04-21). multi-block 카드의 non-primary block에 conditional/r_conditional/post_threshold 쓰면 차단. |
| multi-block primary timing validator 부재 | ~~사람 실수 방어~~ **해결** | `validate_multiblock_primary_timing_consistency` codegen hard-fail 추가 (2026-04-21). multi-block 카드가 ★별로 첫 block trigger_timing 달라지면 차단 (single-block 카드의 star-level timing override는 허용). |
| conditional/r_conditional/post_threshold depth 비일관성 | ~~follow-up~~ **해결** | v2 block 수준은 dict-of-actions, conditional 내부는 v1-style `effects:` list 였음. depth 1 감소 마이그레이션(59a36f1, 2026-04-21): `{when, ...actions}` mini-block + post_threshold `{...actions}` 단일 dict 로 통일. `validate_conditional_effects_key_removed` 로 역전 차단. |
| desc_gen: multi-block 같은 timing 의 listen 별 분리 | ~~description 직결~~ **해결** | `codegen_card_db._project_to_desc_gen_input`가 same-timing/non-primary block action에 `listen_override`를 주입하고, `generate_star_desc`가 `(timing, listen_key)` section별로 그룹핑한다. `pr_transcend`는 `부화 시`/`변태 시`를 별도 `[반응]` 문장과 section별 max_act suffix로 출력한다. 검증: `scripts.tests.test_card_desc_codegen`, `codegen_card_db.py --check` |
