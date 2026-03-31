extends Node
## Unit database. Autoloaded as "UnitDB".
## 50종 유닛. 설계 문서(units-*.md) 기준 정확 이식.

var _units: Dictionary = {}


func _ready() -> void:
	_register_all()


func get_unit(id: String) -> Dictionary:
	return _units.get(id, {})


func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_units.keys())
	return ids


func _reg(id: String, uname: String, atk: int, hp: int,
		attack_speed: float, urange: int, move_speed: int,
		tags: PackedStringArray) -> void:
	_units[id] = {
		"id": id, "name": uname, "atk": atk, "hp": hp,
		"attack_speed": attack_speed, "range": urange,
		"move_speed": move_speed, "tags": tags,
	}


func _register_all() -> void:
	# ═══ 스팀펑크 (10종) — units-steampunk.md ═══
	_reg("sp_spider",   "태엽 거미",      2,  20, 0.5, 0, 3, PackedStringArray(["steampunk","gear","small","melee"]))
	_reg("sp_rat",      "증기 쥐",        2,  15, 0.5, 2, 3, PackedStringArray(["steampunk","steam","small","melee"]))
	_reg("sp_sawblade", "톱날 구동체",    4,  40, 1.0, 0, 2, PackedStringArray(["steampunk","gear","medium","melee"]))
	_reg("sp_scorpion", "증기 전갈",      6,  55, 1.0, 2, 2, PackedStringArray(["steampunk","steam","armor","medium","melee"]))
	_reg("sp_crab",     "철갑 게",        5,  70, 1.5, 0, 1, PackedStringArray(["steampunk","armor","medium","melee"]))
	_reg("sp_titan",    "증기 타이탄",    4, 100, 1.5, 0, 1, PackedStringArray(["steampunk","steam","large","melee"]))
	_reg("sp_cannon",   "황동 포차",      5,  35, 1.0, 4, 2, PackedStringArray(["steampunk","firearm","medium","ranged"]))
	_reg("sp_drone",    "전기 드론",      4,  20, 0.5, 4, 2, PackedStringArray(["steampunk","electric","small","ranged"]))
	_reg("sp_turret",   "증기 터렛",      8,  30, 1.5, 6, 1, PackedStringArray(["steampunk","firearm","steam","medium","ranged"]))
	_reg("sp_scout",    "태엽 정찰기",    2,  25, 0.5, 2, 3, PackedStringArray(["steampunk","gear","electric","small","melee"]))

	# ═══ 중립 (10종) — units-neutral.md ═══
	_reg("ne_scrap",    "고철 수집가",    2,  25, 0.5, 0, 3, PackedStringArray(["neutral","machine","small","melee"]))
	_reg("ne_golem",    "야생 골렘",      3,  70, 1.5, 0, 1, PackedStringArray(["neutral","machine","medium","melee"]))
	_reg("ne_spirit",   "마력 정령",      6,  20, 1.0, 4, 2, PackedStringArray(["neutral","machine","small","ranged"]))
	_reg("ne_eagle",    "기계 독수리",    5,  15, 0.5, 2, 3, PackedStringArray(["neutral","machine","small","melee"]))
	_reg("ne_guardian", "고대 파수꾼",   10,  35, 1.5, 6, 1, PackedStringArray(["neutral","machine","medium","ranged"]))
	_reg("ne_merc",     "떠돌이 용병",    5,  45, 1.0, 0, 2, PackedStringArray(["neutral","organic","medium","melee"]))
	_reg("ne_archer",   "방랑 궁수",      5,  30, 1.0, 4, 2, PackedStringArray(["neutral","organic","small","ranged"]))
	_reg("ne_chimera",  "키메라",         7,  50, 1.0, 0, 2, PackedStringArray(["neutral","organic","medium","melee"]))
	_reg("ne_beast",    "광란의 야수",    8,  35, 0.5, 0, 3, PackedStringArray(["neutral","organic","medium","melee"]))
	_reg("ne_mutant",   "돌연변이 거수",  6, 100, 1.5, 0, 1, PackedStringArray(["neutral","organic","large","melee"]))

	# ═══ 드루이드 (10종) — units-druid.md ═══
	_reg("dr_wolf",     "숲 늑대",        7,  40, 0.5, 0, 3, PackedStringArray(["druid","organic","medium","melee"]))
	_reg("dr_boar",     "가시 멧돼지",    9,  60, 1.0, 0, 2, PackedStringArray(["druid","organic","medium","melee"]))
	_reg("dr_treant_y", "젊은 나무정령",  8,  80, 1.0, 0, 1, PackedStringArray(["druid","organic","medium","melee"]))
	_reg("dr_spirit",   "숲의 정령",      7,  60, 1.0, 2, 2, PackedStringArray(["druid","organic","medium","melee"]))
	_reg("dr_turtle",   "이끼 거북",      4, 100, 1.5, 0, 2, PackedStringArray(["druid","organic","large","melee"]))
	_reg("dr_treant_a", "고대 나무정령",  6, 150, 1.5, 0, 1, PackedStringArray(["druid","organic","large","melee"]))
	_reg("dr_rootguard","뿌리 수호자",    5,  70, 1.0, 2, 1, PackedStringArray(["druid","organic","medium","melee"]))
	_reg("dr_vine",     "가시 덩굴",      8,  50, 1.0, 4, 1, PackedStringArray(["druid","organic","medium","ranged"]))
	_reg("dr_toad",     "독 두꺼비",      7,  45, 1.0, 4, 2, PackedStringArray(["druid","organic","medium","ranged"]))
	_reg("dr_spore",    "포자 대포",     14,  40, 1.5, 6, 1, PackedStringArray(["druid","organic","medium","ranged"]))

	# ═══ 포식종 (10종) — units-predator.md ═══
	_reg("pr_larva",    "칼날 유충",      2,  15, 0.5, 0, 3, PackedStringArray(["predator","organic","small","melee"]))
	_reg("pr_worker",   "갑충 일꾼",      2,  20, 1.0, 0, 2, PackedStringArray(["predator","organic","carapace","small","melee"]))
	_reg("pr_spider",   "산성 거미",      2,  12, 0.5, 2, 3, PackedStringArray(["predator","organic","small","melee"]))
	_reg("pr_warrior",  "돌격 전사충",    3,  25, 1.0, 0, 3, PackedStringArray(["predator","organic","carapace","small","melee"]))
	_reg("pr_charger",  "뿔 돌진자",      4,  30, 1.0, 0, 3, PackedStringArray(["predator","organic","carapace","medium","melee"]))
	_reg("pr_sniper",   "독침 사수",      3,  15, 1.0, 4, 2, PackedStringArray(["predator","organic","small","ranged"]))
	_reg("pr_flyer",    "비행 포식자",    3,  20, 0.5, 4, 3, PackedStringArray(["predator","organic","small","ranged"]))
	_reg("pr_queen",    "여왕충",         2,  40, 1.5, 0, 1, PackedStringArray(["predator","organic","medium","melee"]))
	_reg("pr_guardian", "변태 수호충",    6,  45, 1.5, 0, 2, PackedStringArray(["predator","organic","carapace","medium","melee"]))
	_reg("pr_apex",     "거대 포식자",    8,  30, 1.0, 2, 2, PackedStringArray(["predator","organic","medium","melee"]))

	# ═══ 군대 (10종) — units-military.md ═══
	_reg("ml_recruit",  "신병",           3,  30, 0.5, 0, 3, PackedStringArray(["military","organic","small","melee"]))
	_reg("ml_infantry", "보병",           6,  50, 1.0, 0, 2, PackedStringArray(["military","organic","medium","melee"]))
	_reg("ml_shield",   "에너지 방패병",  3,  75, 1.5, 0, 1, PackedStringArray(["military","organic","medium","melee"]))
	_reg("ml_drone",    "정찰 드론",      3,  20, 0.5, 2, 3, PackedStringArray(["military","machine","small","melee"]))
	_reg("ml_biker",    "강습 바이커",    5,  40, 0.5, 0, 3, PackedStringArray(["military","organic","medium","melee"]))
	_reg("ml_plasma",   "플라즈마 사수",  6,  35, 1.0, 4, 2, PackedStringArray(["military","organic","medium","ranged"]))
	_reg("ml_sniper",   "저격 드론",      8,  25, 1.5, 4, 2, PackedStringArray(["military","machine","small","ranged"]))
	_reg("ml_artillery","궤도 포대",     12,  40, 1.5, 6, 1, PackedStringArray(["military","machine","medium","ranged"]))
	_reg("ml_commander","전술 지휘관",    4,  55, 1.0, 0, 2, PackedStringArray(["military","organic","medium","melee"]))
	_reg("ml_walker",   "중장갑 워커",    9,  85, 1.5, 2, 1, PackedStringArray(["military","machine","large","melee"]))
