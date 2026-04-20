# 미결정 항목

## 경제 (남은 결정)

| 항목 | 상태 | 비고 |
|------|------|------|
| 보스 보상 개별 내용 | 유형별 원칙 확정, 개별 내용 미정 | ⚡즉시행동/🔄영구규칙/💥직접강화/📐구조 설계 원칙 완료. 개별 27개 보상은 카드 풀 후 |
| 테라진 가격/수입 조정 | 프로토타입 후 | 1슬롯 전환에 따른 수치 재조정 |

## 시스템

| 항목 | 상태 | 비고 |
|------|------|------|
| 업그레이드 시스템 | 구조 확정 | 1슬롯 통일, 5축 효과, 범용+태그한정, 23~28종 (커먼10~12/레어8~10/에픽5~6). 개별 항목은 카드 풀 확정 후 |
| 리플레이 시스템 | 초안 완료 | 커맨더 7종, 부적 12종, 난이도 8단계. 해금 루프 포함 |
| 유물 시스템 | 불필요 | 부적 + 보스 보상 3회로 역할 충분 |
| 보조 태그 시너지 | 별도 시스템 불필요 | 카드 효과의 한 유형 (패시브 태그 참조). 카드 풀 설계 시 반영 |
| 적 파워 곡선 | 프레임워크 확정, 수치 미정 | 프리셋형(라운드당 3~4개 풀) + 랜덤 업그레이드 + 특성 보스. 구체 수치는 카드 풀 확정 후 |
| 전투 시스템 구체화 | 확정 | SC1 스타일. AS/Range/MS 유닛별. DEF 기본0, 업글로 부여. 가장가까운적 타겟팅 |
| 예시 카드 풀 세트 | 미완 | 50장 중 10장만 설계. 빌드 검증 필요 |

## 콘텐츠 & 폴리시

| 항목 | 상태 | 비고 |
|------|------|------|
| 테마/세계관 | 확정 | 4테마(스팀펑크/드루이드/포식종/군대) + 중립. 14/9/9/9/9 = 50장. 테마별 키워드 확정 |
| 아트 스타일 | 방향 확정 | SC 스타일. 프로토타입은 Kenney CC0 사용 |
| 성장 체인 시각 연출 | 미설계 | 체인 카운터, ★별 이펙트, 유닛 성장 애니메이션 |
| 메타 진행 상세 | 초안 완료 | 세부 밸런스 미설계 |
| 난이도 곡선 상세 | 재설계 필요 | 새 경제에 맞춰 sim/simulate.py 재조정 |
| PvP 모드 | 후순위 | PvE 확정 후 설계 |
| 플랫폼 | 후순위 | 기획 확정 후 결정 |

## 기술부채 (Phase 2 effect-timing 구조 개편 이월)

2026-04-20 Phase 2 B-direct 마이그레이션 중 "unified store" 80% 달성으로 멈춘 잔여 항목. C4 Convergence Critic이 지적한 drift 위험을 **합리적 수준에서 수용한 타협**. 밸런싱 작업 중에는 유지, 별도 리팩터링 세션에서 해결.

| 항목 | 종류 | 설명 |
|------|------|------|
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
