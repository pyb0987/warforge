## Status: in_progress
## Last completed: P0 (test_unit_db.gd 28개 + test_card_db.gd 26개) — 132/132 pass ✅
## Current state:
- godot/tests/ 에 6개 파일, 132 테스트 전부 통과
- 테스트 범위: combat_basics/advanced, upgrade_data/attach, unit_db, card_db

## Remaining:
- [ ] P1: test_card_instance.gd (~25)
- [ ] P2: test_game_state.gd (~20)
- [ ] P3: test_chain_engine.gd (~20)
- [ ] P4: test_druid_system.gd, test_steampunk_system.gd, test_predator_system.gd, test_military_system.gd (각 ~10)
- [ ] P5: test_combat_integration.gd (~10)

## Next entry point: test_card_instance.gd 작성부터

테스트 실행 명령:
```bash
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

---

# 상세 구현 가이드

## P1: test_card_instance.gd

**파일:** `godot/core/card_instance.gd`
**클래스:** `CardInstance` (class_name)
**생성법:** `CardInstance.create("sp_assembly")` — CardDB + UnitDB Autoload 의존
**sp_assembly 초기 구성:** sp_spider×2 + sp_rat×1 = 3기 합계

### 스탯 공식 (3-레이어)
```
eff_atk = base_atk × (1 + growth_atk_pct) × upgrade_atk_mult × temp_atk_mult + temp_atk
eff_hp  = base_hp  × (1 + growth_hp_pct)  × upgrade_hp_mult  + base_hp × shield_hp_pct
get_total_atk() = 모든 스택의 count × eff_atk_for(s) 합산
```

### 주요 API
```gdscript
CardInstance.create(id) -> CardInstance | null  # static
card.get_total_atk() -> float
card.get_total_hp() -> float
card.get_total_units() -> int
card.enhance(tag_filter, atk_pct, hp_pct) -> int   # growth_atk_pct/hp_pct 누적
card.multiply_stats(atk_pct, hp_pct) -> void        # upgrade_atk_mult/hp_mult ×= (1+pct)
card.spawn_random(rng) -> bool                       # 60기 상한
card.add_specific_unit(unit_id, count) -> int
card.breed_strongest() -> bool                       # CP 최고 유닛 +1
card.metamorphosis(consume_count) -> bool            # N기 소비 → 최강+1 (최소 consume+1 필요)
card.can_activate() -> bool                          # max_act==-1 or used < max_act
card.reset_round() -> void                           # activations_used=0, tenure+=1
card.evolve_star() -> void                           # star_level min(+1,3), _s2 템플릿 있으면 교체
card.attach_upgrade(id) -> bool
card.star_level: int   # 1/2/3
card.tenure: int
card.activations_used: int
card.stacks: Array     # [{"unit_type":dict, "count":int, "upgrade_atk_mult":float, ...}]
```

### 테스트 함수 목록 (25개)

```gdscript
extends GutTest

func before_each() -> void:
    pass  # 각 테스트에서 직접 생성

# 생성
func test_create_valid_id_returns_non_null()
func test_create_invalid_id_returns_null()
func test_initial_star_level_1()
func test_initial_upgrades_empty()
func test_initial_tenure_0()

# Layer1: enhance (growth)
func test_enhance_null_increases_atk_pct()
    # base = get_total_atk(), enhance(null, 0.10, 0) → ×1.10
func test_enhance_hp_pct()
    # enhance(null, 0, 0.10) → hp ×1.10
func test_enhance_tag_gear_affects_only_gear_units()
    # sp_assembly: spider(gear)×2, rat(steam)×1
    # enhance("gear", 0.20) → total ATK > base, < base×1.20
func test_enhance_unknown_tag_no_effect()
    # enhance("nonexistent", 0.50) → total ATK 불변

# Layer2: multiply_stats
func test_multiply_stats_atk()
    # base × 1.30
func test_multiply_stats_stacks_multiplicatively()
    # ×1.30 × ×1.30 = ×1.69
func test_three_layer_combined()
    # enhance(0.10) + multiply_stats(0.30) → base × 1.10 × 1.30

# 유닛 관리
func test_get_total_units_initial_3()
    # sp_assembly: spider×2 + rat×1 = 3
func test_spawn_random_increases_by_1()
    # rng.seed=42, spawn_random(rng) → get_total_units() == 4
func test_spawn_random_respects_60_cap()
    # 57번 spawn → 60기, 다음 spawn → false
func test_add_specific_unit_creates_new_stack()
    # sp_titan (sp_assembly에 없음) → stacks.size() +1
func test_add_specific_unit_existing_stack()
    # sp_spider 추가 → 기존 스택 count +N
func test_breed_strongest_picks_highest_cp_unit()
    # sp_spider CP=2/0.5×20=80, sp_rat CP=2/0.5×15=60
    # breed → sp_spider count +1
func test_metamorphosis_reduces_units_correctly()
    # 초기 3기, metamorphosis(2) → 2기 소비 +1 추가 = 2기
func test_metamorphosis_fails_if_not_enough()
    # 3기에서 metamorphosis(3) → false (3소비+1생존=4 필요)

# 활성화 제한
func test_can_activate_unlimited()
    # sp_assembly max_activations=-1 → 항상 true
func test_can_activate_limited_sp_workshop()
    # sp_workshop max_activations=2
    # activations_used=2 → false
func test_reset_round_clears_activations()
func test_tenure_increments_on_reset()

# 진화
func test_evolve_star_increments()
    # ★1→★2→★3
func test_evolve_star_capped_at_3()
    # 4번 호출해도 3
```

### 주의
- `sp_workshop` 사용: max_activations=2인 카드
- `metamorphosis(3)` 실패 조건: 3소비 후 최강 +1 = 총 4 필요, 현재 3기 → 부족

---

## P2: test_game_state.gd

**파일:** `godot/core/game_state.gd`
**생성법:** `GameState.new()` — Autoload 불필요

### 주요 상수
```gdscript
Enums.MAX_FIELD_SLOTS = 8
Enums.MAX_BENCH_SLOTS = 8
Enums.SELL_REFUND_RATE = 1.0  # 전액 환급
Enums.MAX_INTEREST = 2
```

### 주요 API
```gdscript
GameState.new()
gs.gold: int = 0
gs.terazin: int = 0
gs.hp: int = 30
gs.board: Array  # [null|CardInstance] × 8
gs.bench: Array  # [null|CardInstance] × 8
gs.board_count() -> int
gs.get_active_board() -> Array      # null 제외
gs.add_to_bench(card) -> int        # 슬롯 인덱스 or -1
gs.remove_card(zone, idx) -> CardInstance | null
gs.move_card(from_zone, from_idx, to_zone, to_idx) -> bool
gs.sell_card(zone, idx) -> int      # 환급 골드
gs.calc_interest() -> int           # min(gold/5, 2)
gs.try_merge(template_id) -> Dictionary  # {card,old_star,new_star} or {}
```

### try_merge 주의사항
- `template_id` 기준 매칭: `board[i].template_id == template_id`
- `evolve_star()` 후 template_id가 `"sp_assembly_s2"` 로 바뀜
- ★2→★3 테스트: `try_merge("sp_assembly_s2")` 로 호출
- ★2 합성 보너스: `multiply_stats(0.30, 0.30)` 자동 적용

### 테스트 함수 목록 (20개)

```gdscript
extends GutTest

var _gs: GameState = null

func before_each() -> void:
    _gs = GameState.new()

# 초기 상태
func test_initial_gold_zero()
func test_initial_hp_30()
func test_board_size_8()
func test_bench_size_8()
func test_initial_board_count_0()

# calc_interest
func test_interest_zero_gold() -> 0
func test_interest_5_gold() -> 1
func test_interest_100_gold_capped() -> 2

# 벤치 관리
func test_add_to_bench_first_slot_index_0()
func test_add_to_bench_full_returns_minus1()

# remove_card / sell_card
func test_remove_card_returns_card_and_nulls_slot()
func test_remove_card_null_slot_returns_null()
func test_sell_card_tier1_refunds_2_gold()
    # sp_assembly: cost=2, refund=2×1.0=2

# move_card
func test_move_bench_to_board_success()
func test_move_swaps_if_target_occupied()
func test_move_card_null_source_returns_false()

# try_merge
func test_try_merge_3_copies_star1_to_star2()
    # board[0..2] = sp_assembly×3, try_merge("sp_assembly") → {old_star:1, new_star:2}
func test_try_merge_removes_2_copies_from_board()
func test_try_merge_applies_130_stat_boost()
    # merged.get_total_atk() > base_atk × 1.30 (유닛 수도 3배 흡수됨)
func test_try_merge_below_3_returns_empty()
func test_try_merge_star2_to_star3()
    # 카드 3장 evolve_star() 후 try_merge("sp_assembly_s2")
    # → {old_star:2, new_star:3}
```

---

## P3: test_chain_engine.gd

**파일:** `godot/core/chain_engine.gd`
**생성법:** `ChainEngine.new()` — 내부에서 테마 시스템 4개 자동 생성

### 주요 API
```gdscript
ChainEngine.new()
engine.set_seed(seed: int) -> void
engine.run_growth_chain(board: Array, verbose: bool = false) -> Dictionary
# board = Array of CardInstance (null 없음, GameState.board와 다름)
# 반환: {"chain_count": int, "gold_earned": int, "terazin_earned": int}
# 내부에서 reset_round() 호출됨 → tenure 자동 증가
```

### 설계 핵심
- **Phase 1**: ROUND_START 카드 → 좌→우 순서 발동
- **Phase 2**: BFS 큐 → ON_EVENT 카드가 이벤트 구독 조건 맞으면 반응
- `can_activate()` false이면 스킵
- `MAX_EVENTS = 100` 무한루프 방지

### 카드 조합 예시
| 카드 | timing | 이벤트 방출 | 이벤트 구독 |
|------|--------|------------|------------|
| `sp_assembly` | ROUND_START | UNIT_ADDED+MANUFACTURE | — |
| `sp_workshop` | ON_EVENT | ENHANCED+UPGRADE | UNIT_ADDED+MANUFACTURE (max_act=2) |
| `sp_furnace` | ROUND_START | UNIT_ADDED+MANUFACTURE | — |
| `ne_earth_echo` | ROUND_START | UNIT_ADDED (L1=UNIT_ADDED) | — |
| `ne_wanderers` | ON_EVENT | — | UNIT_ADDED |

### 테스트 함수 목록 (20개)

```gdscript
extends GutTest

var _engine: ChainEngine = null

func before_each() -> void:
    _engine = ChainEngine.new()
    _engine.set_seed(42)

# 기본 발동
func test_round_start_fires_and_spawns()
    # board=[sp_assembly], run → get_total_units() +1
func test_chain_count_at_least_1()
    # board=[sp_assembly], result["chain_count"] >= 1
func test_tenure_increments_after_run()
    # run 후 board[0].tenure == 1
func test_returns_required_keys()
    # result.has("chain_count"), "gold_earned", "terazin_earned"

# 좌→우 순서
func test_left_fires_before_right()
    # board=[sp_assembly, sp_furnace]
    # sp_assembly(idx0)가 right_adj spawn → board[1] 유닛 증가 확인
func test_rightmost_no_right_adj_spawn()
    # board=[sp_assembly] 단독 → 자기 자신만 spawn (+1)

# BFS 연쇄
func test_on_event_reacts_to_manufacture()
    # board=[sp_assembly, sp_workshop]
    # sp_assembly 발동 → MANUFACTURE 이벤트 → sp_workshop 반응 → board[0] ATK 증가
func test_on_event_does_not_fire_without_event()
    # board=[sp_workshop] 단독 → OE 카드는 이벤트 없으면 반응 없음

# 활성화 상한
func test_max_activations_2_respected()
    # board=[sp_assembly, sp_assembly, sp_assembly, sp_workshop]
    # MANUFACTURE 이벤트 3개 → sp_workshop은 2번만 반응
    # sp_workshop.activations_used == 2
func test_activations_reset_second_run()
    # 1회 run 후 activations_used=1, 2회 run → reset_round() → 다시 카운트 시작

# 이벤트 없는 카드는 chain_count에 불포함
func test_battle_start_card_not_counted_in_chain()
    # board=[sp_barrier] (BATTLE_START 카드) → chain_count == 0

# 안전 장치
func test_no_infinite_loop()
    # board=[sp_assembly, sp_workshop], result["chain_count"] < 200

# 특수 케이스
func test_empty_board_returns_zero_chain()
    # run_growth_chain([]) → chain_count == 0
func test_single_on_event_card_no_fire()
    # board=[ne_wanderers] → chain_count == 0 (아무 이벤트도 없으므로)

# require_other_card
func test_sp_line_requires_other_card_for_manufacture()
    # sp_line (require_other=true): 자신이 방출한 이벤트에는 자신이 반응 안 함
    # 단독 배치 시 OE 리스너 반응 없음

# gold / terazin 반환
func test_gold_earned_in_result()
    # grant_gold 효과 카드 사용: CardDB에서 확인 필요
    # ne_merchant (ON_REROLL이라 growth chain 미발동 가능)
    # → diversity_gold 효과 카드 검색 후 사용
    # 우선은 result["gold_earned"] >= 0 로만 확인

func test_terazin_earned_in_result()
    # sp_charger 10카운터 도달 시 terazin=1
    # 직접 counter=9 세팅 후 MANUFACTURE 이벤트로 trigger
    # → chain_engine을 통해 trigger 어려우면 P4 steampunk 테스트로 이동

# Helper
func _make_board(ids: Array) -> Array:
    var board: Array = []
    for id in ids:
        board.append(CardInstance.create(id))
    return board
```

---

## P4-A: test_druid_system.gd

**파일:** `godot/core/druid_system.gd`
**생성법:** `DruidSystem.new()` — standalone

### 트리 상태 접근
```gdscript
card.theme_state.get("trees", 0)      # 현재 트리 수
card.theme_state["trees"] = N          # 직접 설정 가능
```

### 테스트 함수 목록 (15개)

```gdscript
extends GutTest

var _sys: DruidSystem = null
var _rng: RandomNumberGenerator = null

func before_each() -> void:
    _sys = DruidSystem.new()
    _rng = RandomNumberGenerator.new()
    _rng.seed = 42

# dr_cradle (RS): 🌳+1 self, +1 right druid
func test_cradle_adds_1_tree_to_self()
func test_cradle_adds_1_tree_to_right_druid_adj()
    # board=[dr_cradle, dr_origin], process_rs_card(card,0,board,rng)
    # → card.trees==1, card2.trees==1
func test_cradle_no_tree_to_non_druid_right()
    # board=[dr_cradle, sp_assembly] → sp_assembly.trees 변화 없음

# dr_deep (RS): 🌳+1, growth = trees × 0.008
func test_deep_adds_1_tree_per_round()
    # trees=0 → process → trees=1
func test_deep_star1_growth_rate_0008()
    # trees=0 → process → trees=1, growth=1×0.008
    # base_atk × 1.008 ≈ get_total_atk()
func test_deep_mult_threshold_10_applies_130()
    # trees=9 → process → trees=10, growth=10×0.008=0.08, ×1.3 → growth=0.104

# dr_world (RS): 🌳+2, multiply_stats ×1.10
func test_world_applies_multiply_stats_atk_110()
    # trees=0, process → ATK ×1.10
func test_world_adds_2_trees_to_self()
    # process 후 trees == 2

# on_sell: 판매 시 다른 드루이드에게 🌳 분배
func test_on_sell_distributes_all_trees_to_others()
    # sold.trees=6, board=[other_druid]
    # → other.trees == 6
func test_on_sell_divides_evenly_multiple_druids()
    # sold.trees=6, board=[dr1, dr2]
    # → dr1.trees=3, dr2.trees=3
func test_on_sell_ignores_non_druid_sold()
    # sold = sp_assembly(steampunk) → board[0].trees 변화 없음

# apply_battle_start: dr_lifebeat → shield
func test_lifebeat_battle_adds_base_shield_005()
    # trees=0, ★1: shield = 0.05 + 0×0.03 = 0.05
func test_lifebeat_shield_increases_with_trees()
    # trees=3, shield = 0.05 + 3×0.03 = 0.14

# apply_post_combat: dr_grace
func test_grace_victory_earns_gold()
    # trees=0, won=true → gold = 1 + 0/3 = 1
func test_grace_trees_bonus_gold()
    # trees=6, won=true → gold = 1 + 6/3 = 3
```

---

## P4-B: test_steampunk_system.gd

**파일:** `godot/core/steampunk_system.gd`
**생성법:** `SteampunkSystem.new()`

### 테스트 함수 목록 (10개)

```gdscript
extends GutTest

var _sys: SteampunkSystem = null
var _rng: RandomNumberGenerator = null

func before_each() -> void:
    _sys = SteampunkSystem.new()
    _rng = RandomNumberGenerator.new()
    _rng.seed = 42

# sp_charger: 제조 카운터 10마다 terazin+1 + enhance(0.05)
func _make_manufacture_event() -> Dictionary:
    return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.MANUFACTURE,
            "source_idx": 0, "target_idx": 0}

func test_charger_counter_increments()
    # counter 0 → process_event → counter 1
func test_charger_below_10_no_terazin()
    # counter=9 → process → counter=0, terazin=1? NO: 9+1=10 → 발동
    # counter=0 → process → counter=1, terazin=0
func test_charger_at_10_gives_terazin()
    # counter=9 → process → terazin=1, counter=0
func test_charger_at_10_also_enhances_atk()
    # counter=9 → process → ATK 증가 (enhance(null, 0.05, 0))

# sp_warmachine: apply_persistent → #firearm 수 / 8 = range_bonus
func test_warmachine_low_firearm_count_range_0()
    # sp_warmachine 구성: sp_turret×1+sp_cannon×1+sp_drone×2 (firearm=2)
    # 2 < 8 → range_bonus=0
func test_warmachine_range_bonus_calculation()
    # firearm 8기 추가 시 range_bonus=1 확인
    # add_specific_unit("sp_turret", 6) → firearm=8 → range_bonus=1

# sp_arsenal: on_sell_trigger → 최강 유닛 3기 흡수
func test_arsenal_absorbs_3_strongest_units()
    # arsenal = sp_arsenal, sold = sp_assembly(steampunk)
    # on_sell_trigger 후 arsenal.get_total_units() += 3
func test_arsenal_ignores_non_steampunk_sold()
    # sold = dr_cradle → no change
func test_arsenal_absorbed_unit_is_highest_cp()
    # sp_assembly 최강 유닛은 sp_spider(CP=80)
    # arsenal 스택에서 sp_spider count 증가 확인

# process_rs_card → empty (steampunk RS는 generic effects 사용)
func test_process_rs_card_returns_empty()
    # SteampunkSystem.process_rs_card(...) → events=[], gold=0, terazin=0
```

---

## P4-C: test_predator_system.gd

**파일:** `godot/core/predator_system.gd`
**상수:** `LARVA_ID = "pr_larva"`

### 테스트 함수 목록 (10개)

```gdscript
extends GutTest

var _sys: PredatorSystem = null
var _rng: RandomNumberGenerator = null

func before_each() -> void:
    _sys = PredatorSystem.new()
    _rng = RandomNumberGenerator.new()
    _rng.seed = 42

# pr_nest (RS): hatch 2 self, 1 right
func test_nest_hatches_2_larvae_on_self()
    # board=[pr_nest], process_rs_card → get_total_units() +2
func test_nest_larvae_type_is_pr_larva()
    # stacks 중 "pr_larva" 존재
func test_nest_hatches_1_to_right_adj()
    # board=[pr_nest, pr_farm], board[1] units +1
func test_nest_emits_hatch_event()
    # result["events"][0]["layer2"] == Enums.Layer2.HATCH

# pr_farm (RS): hatch 1
func test_farm_rs_hatches_1_larva()
    # board=[pr_farm], before → after: +1

# pr_molt (OE): metamorphosis(3)
func test_molt_triggers_metamorphosis()
    # pr_molt 초기 유닛 확인 필요: CardDB에서 pr_molt 구성 조회
    # add_specific_unit("pr_larva", 5) 추가 후 테스트
    # consume=3 → total -2
    var event := _make_hatch_event(0, 0)
    ...

# pr_harvest (OE): terazin=1, hatch 1
func test_harvest_earns_terazin()
    var event := _make_metamorphosis_event(0, 0)
    # result["terazin"] == 1
func test_harvest_hatches_1()
    # get_total_units() +1

# PredatorSystem hatch helper
func _make_hatch_event(src: int, tgt: int) -> Dictionary:
    return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.HATCH,
            "source_idx": src, "target_idx": tgt}

func _make_metamorphosis_event(src: int, tgt: int) -> Dictionary:
    return {"layer1": Enums.Layer1.ENHANCED, "layer2": Enums.Layer2.METAMORPHOSIS,
            "source_idx": src, "target_idx": tgt}
```

---

## P4-D: test_military_system.gd

**파일:** `godot/core/military_system.gd`

### 랭크 상태 접근
```gdscript
card.theme_state.get("rank", 0)
card.theme_state["rank"] = N  # 직접 설정
```

### 테스트 함수 목록 (12개)

```gdscript
extends GutTest

var _sys: MilitarySystem = null
var _rng: RandomNumberGenerator = null

func before_each() -> void:
    _sys = MilitarySystem.new()
    _rng = RandomNumberGenerator.new()
    _rng.seed = 42

# ml_barracks (RS): train +1 self, +1 adj military
func test_barracks_trains_self_plus1()
    # process_rs_card(card, 0, [card], rng) → rank=1
func test_barracks_trains_adjacent_military()
    # board=[ml_barracks, ml_outpost] → ml_outpost.rank=1
func test_barracks_no_train_to_non_military_adj()
    # board=[ml_barracks, sp_assembly] → sp_assembly.rank 변화 없음

# ml_barracks threshold: rank3→infantry, rank5→plasma, rank8→walker
func test_barracks_rank3_adds_infantry()
    # rank=2 → process → rank=3 → ml_infantry 1기 추가
func test_barracks_rank_threshold_fires_once_only()
    # rank=2 → process (rank=3, infantry 추가) → 다시 process (rank=4) → infantry 추가 없음

# ml_outpost (RS): conscript 2
func test_outpost_conscripts_2_units()
    # process_rs_card → get_total_units() +2
func test_outpost_conscript_ids_in_pool()
    # 추가된 유닛이 CONSCRIPT_POOL에 있는 ID인지 확인

# ml_academy (OE): TRAIN 이벤트 → target 추가 훈련
func test_academy_adds_rank_to_train_target()
    # board=[ml_academy, ml_barracks], event=TRAIN(target=1)
    # → ml_barracks.rank = 1
func test_academy_star1_bonus_train_1()
    # ★1: bonus_train=1, growth=0

# ml_factory (OE): 징집 카운터 10마다 terazin
func test_factory_counter_increments()
func test_factory_at_10_gives_terazin()
    # counter=9 → process → terazin=1, counter=0

# ml_command: apply_persistent → revive 설정
func test_command_sets_revive_hp_50pct()
    # apply_persistent(card) → theme_state["revive_hp_pct"] ≈ 0.50

func _make_train_event(src: int, tgt: int) -> Dictionary:
    return {"layer1": Enums.Layer1.ENHANCED, "layer2": Enums.Layer2.TRAIN,
            "source_idx": src, "target_idx": tgt}

func _make_conscript_event(src: int, tgt: int) -> Dictionary:
    return {"layer1": Enums.Layer1.UNIT_ADDED, "layer2": Enums.Layer2.CONSCRIPT,
            "source_idx": src, "target_idx": tgt}
```

---

## P5: test_combat_integration.gd

**파일:** `godot/combat/combat_engine.gd`
**주의:** `run_to_completion()` 메서드 없을 수 있음 → helper로 직접 구현

### Helper 패턴
```gdscript
const CombatEngineScript = preload("res://combat/combat_engine.gd")

func _make_unit(atk, hp, mechs = [], def = 0) -> Dictionary:
    return {"atk": atk, "hp": hp, "attack_speed": 1.0, "range": 1,
            "move_speed": 50, "def": def, "mechanics": mechs, "radius": 6.0}

func _run_to_end(engine) -> int:
    var ticks := 0
    while ticks < 6000:
        engine.tick()
        ticks += 1
        var any_ally := false
        var any_enemy := false
        for i in engine._base_count:
            if engine.alive[i] == 1:
                if engine.team[i] == 0: any_ally = true
                else: any_enemy = true
        if not any_ally or not any_enemy:
            break
    return ticks
```

### 테스트 함수 목록 (10개)

```gdscript
func test_stronger_unit_wins()
    # ally ATK=100, HP=500 vs enemy ATK=1, HP=1
    # ally alive[0]=1, enemy alive[1]=0
func test_weaker_unit_loses()
    # 반대 경우
func test_combat_terminates_before_max_ticks()
    # 동등 유닛 전투, ticks < 6000
func test_team_assignment_correct()
    # engine.team[0]==0 (ally), engine.team[1]==1 (enemy)
func test_slow_aura_sets_slow_factor()
    # ally에 slow_aura 부착, 적이 range 이내일 때 slow_factor < 1.0
    # tick() 1번 후 engine.slow_factor[1] ≈ 0.70
func test_multiple_allies_vs_one_enemy()
    # 3 ally vs 1 weak enemy → all allies 생존, enemy 사망
func test_fission_clones_survive_after_death()
    # fission 유닛 사망 후 클론 2기 alive
func test_regen_heals_over_time()
    # regen 유닛: HP 낮추고 여러 틱 후 HP 회복 확인
func test_berserk_activates_below_30pct()
    # 수동으로 hp를 29%로 낮춘 후 tick → berserk_active[i]==1
func test_soul_harvest_stacks_on_kill()
    # soul_harvest 유닛이 kill 후 soul_atk_bonus > 0
```

---

## 알려진 주의사항 (모든 테스트 공통)

1. **GUT strict typing**: `var x: Dictionary = func_returning_dict()` 패턴 사용 (`:=` 금지)
2. **try_merge ★2→★3**: `evolve_star()` 후 `template_id = "sp_assembly_s2"` → `try_merge("sp_assembly_s2")` 호출
3. **ChainEngine board**: null 없는 순수 CardInstance 배열 (GameState.board와 다름)
4. **ML factory event**: `layer2: Enums.Layer2.CONSCRIPT` 포함 필요
5. **pr_molt 유닛 수**: CardDB에서 pr_molt 구성 확인 후 필요시 add_specific_unit으로 보충
6. **combat_engine._base_count**: setup() 완료 후 기본 유닛 수 (fission 슬롯 제외)
