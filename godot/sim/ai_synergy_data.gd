class_name AISynergyData
extends RefCounted
## Static synergy/priority data for AI decision making.
## Extracted from AIAgent to keep it under 800 lines.

# Chain synergy map (Layer1 event chains: RS → OE listeners)
const CHAIN_PAIRS := {
	"sp_assembly":  ["sp_workshop", "sp_line", "sp_charger"],
	"sp_furnace":   ["sp_workshop", "sp_charger"],
	"sp_workshop":  ["sp_circulator"],
	"sp_circulator": ["sp_workshop", "sp_line", "sp_charger"],
	"sp_line":      ["sp_workshop", "sp_line", "sp_charger"],
	"ne_earth_echo":     ["ne_wanderers", "ne_mana_crystal"],
	"ne_wild_pulse":     ["ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_ruin_resonance": ["ne_wanderers", "ne_mana_crystal", "ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_wanderers":      ["ne_mutant_adapt", "ne_ancient_catalyst"],
	"ne_mutant_adapt":   ["ne_wanderers", "ne_mana_crystal"],
	"ne_mana_crystal":   ["ne_wanderers"],
	"ne_ancient_catalyst": ["ne_mutant_adapt"],
}

# Theme-internal synergy (Layer2 systems)
const THEME_SYNERGY := {
	"dr_cradle":     ["dr_origin", "dr_deep", "dr_wt_root", "dr_earth"],
	"dr_origin":     ["dr_cradle", "dr_deep", "dr_wt_root"],
	"dr_earth":      ["dr_cradle", "dr_origin", "dr_deep"],
	"dr_deep":       ["dr_cradle", "dr_origin", "dr_wt_root", "dr_world"],
	"dr_wt_root":    ["dr_cradle", "dr_origin", "dr_deep", "dr_world"],
	"dr_world":      ["dr_deep", "dr_wt_root", "dr_earth"],
	"dr_lifebeat":   ["dr_cradle", "dr_origin"],
	"dr_spore_cloud": ["dr_cradle", "dr_origin", "dr_deep"],
	"dr_grace":      ["dr_cradle", "dr_origin"],
	"pr_nest":       ["pr_molt", "pr_queen", "pr_carapace", "pr_harvest"],
	"pr_farm":       ["pr_molt", "pr_harvest"],
	"pr_queen":      ["pr_molt", "pr_carapace", "pr_harvest", "pr_apex_hunt"],
	"pr_molt":       ["pr_harvest", "pr_carapace", "pr_apex_hunt"],
	"pr_harvest":    ["pr_nest", "pr_queen", "pr_carapace"],
	"pr_carapace":   ["pr_molt", "pr_harvest", "pr_apex_hunt"],
	"pr_apex_hunt":  ["pr_molt", "pr_carapace"],
	"pr_transcend":  ["pr_molt", "pr_harvest", "pr_apex_hunt", "pr_swarm_sense"],
	"pr_swarm_sense": ["pr_nest", "pr_queen", "pr_transcend"],
	"pr_parasite":   ["pr_swarm_sense", "pr_nest", "pr_queen"],
	"ml_barracks":   ["ml_academy", "ml_conscript", "ml_tactical"],
	"ml_outpost":    ["ml_conscript", "ml_factory"],
	"ml_academy":    ["ml_barracks", "ml_special_ops", "ml_command"],
	"ml_conscript":  ["ml_outpost", "ml_factory"],
	"ml_command":    ["ml_academy", "ml_barracks", "ml_special_ops"],
	"ml_special_ops": ["ml_academy", "ml_tactical"],
	"ml_factory":    ["ml_outpost", "ml_conscript"],
	"ml_tactical":   ["ml_barracks", "ml_command", "ml_assault"],
	"ml_assault":    ["ml_barracks", "ml_outpost", "ml_command"],
	"ml_supply":     ["ml_barracks", "ml_outpost"],
}

# Critical path cards per theme — essential infrastructure
const THEME_CRITICAL := {
	Enums.CardTheme.STEAMPUNK: ["sp_assembly", "sp_furnace", "sp_workshop", "sp_circulator", "sp_charger"],
	Enums.CardTheme.DRUID: ["dr_cradle", "dr_origin", "dr_deep", "dr_wt_root"],
	Enums.CardTheme.PREDATOR: ["pr_nest", "pr_farm", "pr_queen", "pr_molt"],
	Enums.CardTheme.MILITARY: ["ml_barracks", "ml_outpost", "ml_academy", "ml_conscript"],
}

# Position priority for board arrangement (1-90 scale, lower = leftmost)
const POSITION_PRIORITY := {
	"sp_assembly": 10, "sp_furnace": 10,
	"sp_workshop": 30, "sp_circulator": 40, "sp_line": 50,
	"sp_interest": 60, "sp_barrier": 70, "sp_warmachine": 80, "sp_charger": 35,
	"sp_arsenal": 90,
	"ne_earth_echo": 10, "ne_wild_pulse": 10, "ne_ruin_resonance": 15,
	"ne_wanderers": 30, "ne_mutant_adapt": 40,
	"ne_mana_crystal": 35, "ne_ancient_catalyst": 45,
	"ne_merchant": 80, "ne_ruins": 20, "ne_awakening": 25,
	"ne_wildforce": 70, "ne_chimera_cry": 85, "ne_spirit_blessing": 75,
	"ne_dim_merchant": 15,
	"dr_cradle": 10, "dr_origin": 11, "dr_earth": 20,
	"dr_deep": 25, "dr_wt_root": 30, "dr_world": 35,
	"dr_lifebeat": 50, "dr_spore_cloud": 55, "dr_grace": 60, "dr_wrath": 45,
	"pr_nest": 10, "pr_farm": 15, "pr_queen": 12, "pr_transcend": 5,
	"pr_molt": 30, "pr_harvest": 35, "pr_carapace": 40,
	"pr_swarm_sense": 50, "pr_apex_hunt": 45, "pr_parasite": 55,
	"ml_barracks": 10, "ml_outpost": 15, "ml_command": 5,
	"ml_academy": 30, "ml_conscript": 35,
	"ml_special_ops": 20, "ml_factory": 40,
	"ml_tactical": 50, "ml_assault": 55, "ml_supply": 60,
}

# Per-strategy behavior parameters.
# levelup_schedule: {round: target_shop_level}
# core_cards: highest priority cards (beyond critical path)
# capstone_cards: T4/T5 game-changers that warrant extra rerolls
const STRATEGY_CONFIG := {
	"steampunk_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 3,
		"max_rerolls_late": 6,
		"gold_reserve": 1,
		"core_cards": ["sp_charger", "sp_circulator", "sp_workshop"],
		"capstone_cards": ["sp_charger", "sp_arsenal", "sp_warmachine"],
	},
	"druid_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 3,
		"max_rerolls_late": 5,
		"gold_reserve": 1,
		"core_cards": ["dr_world", "dr_wt_root", "dr_deep"],
		"capstone_cards": ["dr_world", "dr_wrath", "dr_grace"],
	},
	"predator_focused": {
		"levelup_schedule": {3: 2, 5: 3, 7: 4, 9: 5},
		"max_rerolls_base": 4,
		"max_rerolls_late": 6,
		"gold_reserve": 0,
		"core_cards": ["pr_apex_hunt", "pr_queen", "pr_molt"],
		"capstone_cards": ["pr_apex_hunt", "pr_transcend"],
	},
	"military_focused": {
		"levelup_schedule": {3: 2, 5: 3, 8: 4, 10: 5},
		"max_rerolls_base": 2,
		"max_rerolls_late": 4,
		"gold_reserve": 2,
		"core_cards": ["ml_command", "ml_academy", "ml_special_ops"],
		"capstone_cards": ["ml_command", "ml_assault"],
	},
}
