# Handoff — 재착수 상태 (2026-05-30)

## 2026-07-02 Codex autonomous update

- G-4 D5-D8 난이도 후속 캘리브레이션 완료: D4 적 유닛 수 보정은 ×1.15에서 ×1.10으로 완화. D7 적 ATK는 ×1.30에서 ×1.10으로 완화. D7 보스 업그레이드는 R12 레어, R15 에픽으로 지연하고 R15의 레어+에픽 중첩을 제거.
- 70-run D7-D8 확인 sweep (`--runs=10`, 7 strategies, seed=42, best_genome): D7 clear 1.4%, avg rounds 9.03; D8 clear 1.4%, avg rounds 8.13. 이전 0% 벽은 깨졌지만 여전히 극고난도 영역.
- Small full sweep (`--runs=5`, 7 strategies, seed=42, best_genome): D1 28.6%, D2 25.7%, D3 22.9%, D4 5.7%, D5 8.6%, D6 2.9%, D7 0.0%, D8 0.0%. 작은 표본은 D7-D8 희박 clear를 놓칠 수 있어 대형 sweep/사람 플레이 표본으로 미세 튜닝 권장.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_difficulty.gd -glog=1 -gexit` — 7/7
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1109/1109 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` — 10 tests OK
  - PASS `git diff --check`
- 자율 진행 셋업 완료: 난이도 수치는 버그 수정 외 동결하고, `Plans.md`의 "Playable Prototype Completion After Difficulty"를 새 Active Plan으로 전환.
- 다음 우선순위: G-6 상세 메타 진행 화면 → G-7 업그레이드 부착 비교 UX → G-8 실제 플레이 중 튜토리얼 오버레이 → G-9 성장 체인 가독성 → G-10 sim ON_REROLL parity → G-11 stale design backlog cleanup.
- 다음 착수 권장: G-6. `godot/scripts/ui/run_start_screen.gd`, `godot/scenes/ui/run_start_screen.tscn`, `godot/core/meta_progress.gd`, `godot/tests/test_run_start_screen.gd`, `godot/tests/test_meta_progress.gd`를 같이 수정해 전체 해금/업적 상태를 시작 화면에서 확인 가능하게 만든다.
- G-6 상세 메타 진행 화면 완료: `MetaProgress.get_full_progress_text()`와 unlock/achievement status row API 추가. `RunStartScreen`의 `PROGRESS` 버튼으로 접힘형 상세 패널을 열어 전체 커맨더/부적 해금 상태, 완료 업적, 잠긴 목표를 확인 가능.
- G-6 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta_progress.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 6/6
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1111/1111 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-7. `godot/scripts/build/build_phase.gd`, `godot/scenes/build/build_phase.tscn`, `godot/scripts/build/upgrade_shop.gd`, `godot/scripts/ui/upgrade_visual.gd`, `godot/tests/test_build_phase_upgrade_shop.gd`를 중심으로 업그레이드 대상 선택 시 슬롯/부착 가능 여부/효과 미리보기를 표시한다.
- G-7 업그레이드 부착 비교 UX 완료: `TargetSelectOverlay`가 context/detail/preview label을 받을 수 있게 확장됨. 업그레이드 구매/무료 업그레이드 대상 선택 시 업그레이드 효과, 카드별 `Slots n/m -> n+1/m`, full slot `FULL n/m` 표시.
- G-7 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_rusty_wrench_detach.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_attach.gd -glog=1 -gexit` — 14/14
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1113/1113 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-8. `BuildPhase`에 첫 런/초기 런용 in-run tutorial hint overlay를 추가한다. 시작 화면 가이드는 이미 있으므로, 상점 구매/보드 배치/업그레이드/BUILD 확정의 맥락형 힌트와 저장된 dismiss 상태를 우선 검토한다.
- G-8 실제 플레이 중 튜토리얼 오버레이 완료: 첫 런 BuildPhase에서 `TUTORIAL` 패널을 표시한다. 상태별 힌트는 카드 구매 → 벤치에서 FIELD 배치 → UPGRADES 구매 → 업그레이드 대상 선택 → BUILD COMPLETE 준비 순서로 갱신된다. `DISMISS` 버튼은 현재 런에서 숨기고 `tutorial_dismissed` 신호를 emit한다.
- G-8 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 6/6
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1119/1119 across 49 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-9. `godot/scripts/chain/chain_visual.gd`, `godot/scenes/chain/chain_visual.tscn`, `godot/tests/test_chain_engine.gd` 또는 신규 `test_chain_visual.gd`를 중심으로 trigger count/source-target/reward event 가독성을 개선한다.
- G-9 성장 체인 가독성 완료: `ChainVisual`에 페이즈/최근 이벤트 로그 패널을 추가했다. 체인 이벤트는 `소스 카드 -> 대상 카드`, `+Unit`/`+ATK%` 같은 보상 요약, Layer1/Layer2 키워드를 함께 표시하고, 완료 시 trigger count와 gold 보상을 요약한다. 빈 상태에서는 새 로그 패널을 숨겨 빌드 화면 방해를 줄인다.
- G-9 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit` — 18/18
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1124/1124 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: G-10. `godot/sim/shop_logic.gd`, `godot/sim/headless_runner.gd`, `godot/core/chain_engine.gd`, `godot/tests/test_sim_shop_logic.gd`, `godot/tests/test_steampunk_system.gd`를 중심으로 headless sim reroll path가 live `game_manager.gd`의 ON_REROLL trigger와 같은 효과를 내도록 맞춘다.
- G-10 sim ON_REROLL parity 완료: `ShopLogic.reroll()`에 선택적 trigger callback을 추가했다. `HeadlessRunner`는 이 callback에서 `chain_engine.process_reroll_triggers(state.get_active_board())`를 호출하고 gold/terazin/levelup_discount를 state에 반영한다. `sp_interest` 리롤 성장, `ne_pawnbroker` 리롤 레벨업 할인, 실패 리롤 미발동을 테스트로 고정했다. `docs/design/backlog.md`에서는 ON_REROLL parity를 해결로 표시하고, RS/pending free-reroll 생성·소비는 별도 latent 항목으로 분리했다.
- G-10 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 20/20
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 12/12
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_steampunk_system.gd -glog=1 -gexit` — 50/50
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_pawnbroker_reroll.gd -glog=1 -gexit` — 6/6
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1129/1129 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: G-11. `docs/design/backlog.md`, `docs/design/boss-rewards.md`, `docs/design/upgrade.md`, `DESIGN.md`, `.claude/backlog.md`를 대조해 이미 구현된 보스 보상/시스템 미결 항목을 현재 코드 상태와 맞춘다.
- G-11 stale design backlog cleanup 완료: 이미 구현된 보스 보상 27종, 테라진 1차 경제, 리플레이/메타/난이도 1차 구현, 적 파워 곡선, 성장 체인 가시화, 업그레이드/Rusty Wrench/Alchemist epic shop, 금간 해골 상한 문구를 현재 구현 상태와 동기화했다. G6-G11 "Playable Prototype Completion After Difficulty" 계획은 완료로 닫고, 새 Active Plan은 "Prototype Hardening After Player-Facing Loop"로 전환했다.
- G-11 검증:
  - PASS doc review against `docs/design/backlog.md`, `docs/design/upgrade.md`, `docs/design/talismans.md`, `.claude/backlog.md`, and `Plans.md`.
  - PASS `git diff --check`
- 다음 착수 권장: H-1 desc_gen multi-block listen separation. `scripts/card_desc_gen.py`, `docs/design/card-desc-codegen.md`, generated `godot/core/data/card_descs.gd`, and the current `pr_transcend` description should be checked so separate OE listen targets do not collapse into one misleading reaction prefix.
- H-1 desc_gen multi-block listen separation 완료: 현재 codegen projection은 same-timing/non-primary block action에 `listen_override`를 주입하고, desc_gen은 `(timing, listen_key)` section별로 prefix/max_act를 분리한다. 설계 문서의 `generate_star_desc` 설명을 현재 계약에 맞췄고, `pr_transcend`가 `부화 시`/`변태 시`를 별도 `[반응]` 문장으로 유지하는 Python 회귀 테스트를 추가했다.
- H-1 검증:
  - PASS `python3 -m unittest scripts.tests.test_card_desc_codegen` — 2/2
  - PASS `python3 scripts/codegen_card_db.py --check`
  - PASS `git diff --check`
- 다음 착수 권장: H-2 sim pending free-reroll parity. G10의 paid reroll ON_REROLL callback은 해결됐으므로, 남은 범위는 live의 pending free-reroll 생성/소비와 headless AI reroll 의사결정의 표현 차이를 분리해 처리한다.
- H-2 sim pending free-reroll parity 완료: `ShopLogic.reroll()`이 pending 무료 리롤을 골드보다 먼저 소비하고, 무료/유료 성공 리롤 모두 ON_REROLL trigger callback을 발동한다. `AIAgent`는 pending 무료 리롤이 있으면 gold reserve 조건을 우회해 리롤할 수 있다. `HeadlessRunner`는 chain 시작 시 pending/round reroll을 live처럼 리셋하고 보스 보상 매턴 무료 리롤을 충전하며, chain callback으로 전당포/폐품 상회의 무료 리롤 적립을 `GameState.pending_free_rerolls`에 반영한다.
- H-2 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 22/22
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_pawnbroker_reroll.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_neutral_system.gd -glog=1 -gexit` — 57/57
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1133/1133 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: H-3 combat talisman regression coverage. 금간 해골/전쟁 북은 데이터/query 테스트보다 전투 엔진 적용 경로가 중요하므로 combat-level 회귀 테스트로 고정한다.
- H-3 combat talisman regression coverage 완료: `test_talisman.gd`에 전투 엔진 fixture를 추가해 전쟁 북의 수적 우위 ATK 감소가 실제 전투 피해로 반영되는지, 금간 해골의 `undying` 주입이 아군에게만 들어가는지, 첫 치사 피해만 HP 1 생존으로 막고 두 번째 치사 피해에는 사망하는지 고정했다.
- H-3 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit` — 38/38
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1136/1136 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- H-4 착수 배경: 플레이어가 합성 결과와 체인 순서를 텍스트 로그 없이도 더 잘 읽도록 합성/체인 feedback을 개선한다.
- H-4 merge/chain polish pass 완료: `BuildPhase`가 최근 합성 결과를 HUD 라벨로 표시한다. ★1→★2는 무료 Rare 업그레이드 대기, ★2→★3는 최종 합성 또는 캐스케이드 보상 대상 이전을 요약한다. `ChainVisual`의 라인 위 플로팅 텍스트는 `#1 +Unit`처럼 발동 순번을 포함해 로그 패널을 보지 않아도 순서를 읽을 수 있다.
- H-4 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1137/1137 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- H-5 sim diversity next-slice triage 완료: 난이도 수치는 계속 동결하고 140-run sim 기준선을 재측정했다. 현재 best_genome, seed=42, 20 runs × 7 strategies 결과는 weighted 0.4850, card_coverage 0.2175, soft_steampunk 1/20, soft_druid 2/20, adaptive 11/20, aggressive 12/20. 다음 축은 broad difficulty가 아니라 낮은 focused 전략의 payoff/전환 안정성으로 확정.
- H-6 AI bench-space sale bug fix 완료: `_sell_weakest_for_upgrade()`가 벤치 공간 확보 중 보드를 팔 수 있던 버그를 제거하고 bench-only 판매로 제한했다. 대표 soft_steampunk seed에서 보드 판매 후 구매 실패 패턴이 사라졌고, 140-run 기준선은 weighted 0.4903, card_coverage 0.2195, soft_steampunk 2/20, soft_druid 3/20으로 개선.
- H-6 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_board_eval.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json` — weighted 0.4903
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1139/1139 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- H-7 military target warning cleanup 완료: `MilitarySystem._dispatch_r_effect()`가 모든 r_conditional inner effect의 target을 선해석하던 흐름을 제거하고, 실제 target 리스트가 필요한 `train`/`conscript` 액션 안에서만 `_resolve_targets()`를 호출한다. `revive_scope_override`의 `self_all`/`self_and_adj_all`은 `resolve_command_revive()`/`resolve_revive_scope()` 전용 target으로 남아 generic dispatcher 경고를 내지 않는다.
- H-7 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_military_system.gd -glog=1 -gexit` — 81/81. 새 rank 4/10 `ml_command` RS 회귀 테스트 포함.
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=1 --seed=42 --baseline=res://sim/baseline.json` — `[military r_conditional]` warning 없음.
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1141/1141 across 50 scripts. At this point the remaining GUT warnings were the expected unknown revive-scope fallback test plus pre-existing float/int assertion warnings in `test_genome.gd`; H-8 cleaned those next. Godot still reports ObjectDB/resource warnings on exit.
- H-8 GUT warning-noise cleanup 완료: `test_genome.gd`의 JSON float 값 비교를 float-aware assertion으로 바꾸고, unknown revive-scope fallback warning을 `assert_push_warning()`으로 명시해 GUT summary warning total을 8개에서 0개로 줄였다.
- H-8 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_genome.gd -glog=1 -gexit` — 10/10, warning 없음.
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_military_system.gd -glog=1 -gexit` — 81/81, expected push_warning 명시.
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1141/1141 across 50 scripts, GUT warning total 없음. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: H-9 next playability slice selection. 이제 경고 노이즈가 줄었으므로 밸런스보다 “작동하는 완성 게임”에 필요한 UX/flow gap을 우선 골라 진행한다.

## 2026-07-01 Codex autonomous update

- G-1 수집가 follow-up 완료: 첫 상점 refresh 1회에 한해 T2+ 카드 4장 이상 보장. UI 상점(`shop.gd`)과 headless sim 상점(`shop_logic.gd`) 모두 공통 `ShopPicker.apply_min_tier_guarantee` 경유.
- G-1 전략가 follow-up 완료: BuildPhase에 `SWAP (H)` 버튼/단축키 추가. 보드 카드 2장 좌클릭으로 교환하며 `Commander.hero_swap`가 `card_moved`/`board_changed`/`state_changed`를 방출.
- G-2 부적 선택 UI 1차 완료: 런 시작 시 `TalismanSelectPopup`에서 12종 부적을 선택하고 `GameState.talisman_type`에 반영.
- G-2 녹슨 렌치 UX 완료: BuildPhase에 `DETACH (D)` 버튼/단축키 추가. 업그레이드가 붙은 필드 카드를 선택해 마지막 업그레이드를 제거하고 50% 테라진을 환급.
- G-3 업그레이드 상점 UX 1차 완료: R1부터 커먼/레어 업그레이드 상점 표시, 테라진 구매→필드 카드 선택→즉시 부착 흐름 연결. `REROLL (T)` 버튼/단축키, 대상 취소 환불, 구매 불가 dim 상태 추가.
- G-4 런 시작 화면 1차 완료: `RunStartScreen`을 `main.tscn` 첫 화면으로 추가. `START RUN` 이후 해금된 커맨더/부적 선택으로 이어짐.
- G-4 메타 저장 1차 완료: `MetaProgress`가 `user://meta_progress.cfg`에 run stats, 초기 해금, 최대 난이도를 저장. 승리 시 다음 난이도를 해금하고, 런 시작 화면에서 해금 범위 안의 난이도를 선택 가능.
- G-4 난이도 전투/경제 1차 완료: `Difficulty` autoload 추가. live + headless sim 공통으로 D2 적 HP, D3 시작 골드, D4 적 유닛 수, D5/D7 보스 업그레이드, D6 상점/리롤 비용, D7 적 ATK, D8 플레이어 HP 적용.
- G-4 난이도 캘리브레이션 1차 완료: `difficulty_sweep_runner.gd` 추가. D3 시작 골드는 13→10 상대 페널티로 스케일 조정(현재 best genome 3g→2g). D4 적 수는 초기안 ×1.3이 clear 0% cliff를 만들어 ×1.15로 완화.
- G-4 업적 해금 1차 완료: 런 종료 시 필드 유닛, 장착 업그레이드, 필드 유니크 카드, 연승, 판매 수, 성장 이벤트, ★2+ 카드, 수적 우위 승리를 평가해 커맨더/부적을 해금.
- G-5 튜토리얼/온보딩 1차 완료: 런 시작 화면에 첫 런 가이드, 다음 해금 목표, 최근 해금 목록 표시. `tutorial_seen` 저장으로 첫 가이드는 `START RUN` 이후 접힘.
- 35-run sweep (`--runs=5`, 7 strategies, seed=42, best_genome): D1 28.6%, D2 25.7%, D3 22.9%, D4 5.7%, D5 0.0%, D6 5.7%, D7 0.0%, D8 0.0%. D5-D8은 표본 확대 후 추가 튜닝 권장.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_difficulty.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_db.gd -glog=1 -gexit` — 18/18
  - PASS `godot --headless --path godot/ -s sim/difficulty_sweep_runner.gd -- --genome=res://sim/best_genome.json --runs=5 --seed=42` — completed 280 runs
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_shop_logic.gd -glog=1 -gexit` — 44/44
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 17/17
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit` — 36/36
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_strategist_swap.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman_select_popup.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit` — 35/35
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta_progress.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 10/10
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_rusty_wrench_detach.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 4/4
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 5/5
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` — 10 tests OK
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_pool.gd -glog=1 -gexit` — 17/17
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_combat_chain.gd -glog=1 -gexit` — 9/9
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_merge_system.gd -glog=1 -gexit` — 61/61
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_neutral_system.gd -glog=1 -gexit` — 57/57
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1109/1109 across 48 scripts, no ignored test files. Godot still reports ObjectDB/resource warnings on exit.
- Verification-health follow-up 완료: `test_combat_chain.gd`, `test_merge_system.gd`, `test_neutral_system.gd` 수집 실패 해소. Neutral stale expectations were synced to current YAML/contracts (`ne_envoy` 1/2/4g, `ne_awakening` ★1 guard requires a matching common upgrade).
- G-1, G-2, G-3, G-4, and G-5 are now complete at playable prototype level. Next playable-run targets: detailed meta progression screen, richer upgrade comparison tooltips, or D5-D8 difficulty win-rate calibration.

## 2026-05-30 Codex restart update

- `fc90850` 에서 Codex용 meta-harness surface 커밋 완료.
- G-1 첫 조각 완료: 런 시작 시 `CommanderSelectPopup`에서 7종 커맨더를 선택하고 `GameState.commander_type`에 반영한 뒤 BuildPhase로 진입.
- 단조사 UX follow-up 완료: 일반 업그레이드 상점은 커맨더 시대 기준 R1부터 표시하고, 단조사 커먼 할인은 실제 표시 가격에 반영. 단조사 시작 보너스는 첫 빌드 확정 전 커먼 업그레이드 3택1 → 필드 카드 선택 → 무료 부착으로 동작.
- 2026-06-02 B-3 follow-up 완료: adaptive 드루이드 회피 원인을 AI 조기 테마 확정 + Druid producer/payoff scoring 부재로 진단하고 수정. adaptive Druid zero coverage 5장→2장, Druid theme coverage 0.1896→0.2468, weighted_score 0.4614(+0.0155 vs baseline). 상세: `.claude/traces/experiments/009-druid-ai-avoidance.md`.
- 추가 파일: `godot/scenes/ui/commander_select_popup.tscn`, `godot/scripts/ui/commander_select_popup.gd`, `godot/tests/test_commander_select_popup.gd`.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander_select_popup.gd -glog=1 -gexit` — 2/2
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit` — 35/35
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_shop_logic.gd -glog=1 -gexit` — 19/19
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 4/4
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit` — 32/32
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_theme_scorer.gd -glog=1 -gexit` — 11/11
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit` — 12/12
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json` — weighted_score 0.4614
  - Full GUT command exited 0 with 926 passing tests, but collection emitted pre-existing parse warnings for `test_combat_chain.gd`, `test_merge_system.gd`, and `test_neutral_system.gd`; those files were ignored by GUT and should be cleaned up in a separate verification-health pass.
- Remaining G-1 follow-up: 전략가 hero swap UI, 수집가 starting shop guarantee. Remaining AI follow-up: `soft_druid` win-rate is still 0/20 in the B-3 follow-up measurement.

# Prior Handoff — B-3 + B-4 완료 (2026-04-30, 2nd session)

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
