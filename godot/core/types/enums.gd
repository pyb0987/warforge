extends Node
## Global enums and constants. Autoloaded as "Enums".

# --- Layer 1: 결과 범주 (테마 무관) ---
enum Layer1 {
	UNIT_ADDED,
	ENHANCED,
}

# --- Layer 2: 테마 키워드 ---
enum Layer2 {
	NONE,
	# 스팀펑크
	MANUFACTURE,
	UPGRADE,
	# 드루이드
	TREE_GROW,
	BREED,
	# 포식종
	HATCH,
	METAMORPHOSIS,
	# 군대
	TRAIN,
	CONSCRIPT,
}

# --- 트리거 타이밍 ---
enum TriggerTiming {
	ROUND_START,
	ON_EVENT,
	BATTLE_START,
	ON_COMBAT_ATTACK,
	POST_COMBAT,
	POST_COMBAT_DEFEAT,
	POST_COMBAT_VICTORY,
	ON_REROLL,
	ON_MERGE,
	ON_SELL,
	PERSISTENT,  ## 지속 효과 — 테마 시스템에서 매 프레임/이벤트 처리
}

# --- 테마 ---
enum CardTheme {
	NEUTRAL,
	STEAMPUNK,
	DRUID,
	PREDATOR,
	MILITARY,
}

# --- 카드 등급 ---
enum StarLevel {
	STAR_1 = 1,
	STAR_2 = 2,
	STAR_3 = 3,
}

# --- 업그레이드 등급 ---
enum UpgradeRarity {
	COMMON,
	RARE,
	EPIC,
}

# --- 상수 ---
const MAX_UPGRADE_SLOTS := 5
const UPGRADE_REROLL_COST := 1  # 테라진
const UPGRADE_SHOP_SLOTS := 2
const MAX_FIELD_SLOTS := 8
const MAX_BENCH_SLOTS := 8
const MAX_ROUNDS := 15
const REROLL_COST := 1
const SELL_REFUND_RATE := 1.0  # 전액 환급
const INTEREST_PER_5G := 1
const MAX_INTEREST := 2
var BOSS_ROUNDS := [4, 8, 12, 15]
