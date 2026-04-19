extends Node
## Global enums and constants. Autoloaded as "Enums".

# --- Layer 1: 결과 범주 (테마 무관) ---
enum Layer1 {
	UNIT_ADDED,
	UNIT_REMOVED,
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
	ON_COMBAT_DEATH,  ## 전투 중 아군 사망 시 반응
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

# --- 커맨더 ---
enum CommanderType {
	NONE,
	GAMBLER,    # 🎲 도박꾼
	BREEDER,    # 🌱 양성가
	SMITH,      # ⚒️ 단조사
	STRATEGIST, # 📐 전략가
	COLLECTOR,  # 📚 수집가
	RAIDER,     # ⚔️ 약탈자
	ALCHEMIST,  # 💰 연금술사
}

# --- 부적 ---
enum TalismanType {
	NONE,
	BURST_SACK,       # 터진 자루 — 업그레이드 상점 +1
	WAR_DRUM,          # 전쟁 북 — 수적 우위 시 적 ATK -10%
	MERCURY_DROP,      # 수은 방울 — 강화 효과 +25%
	GLASS_EYE,         # 유리 눈 — 보유 카드 확률 ×1.15
	TWO_FACED_COIN,    # 양면 동전 — 할인 1장 / 할증 1장
	GOLDEN_DIE,        # 황금 주사위 — 보스 선택지 +2
	CRACKED_EGG,       # 깨진 알 — ★2+ 유닛추가 시 +1
	FLINT,             # 부싯돌 — 첫 성장 효과량 ×2
	CRACKED_SKULL,     # 금간 해골 — 첫 치사 HP1 생존
	RUSTY_WRENCH,      # 녹슨 렌치 — 업그레이드 분리 + 50% 환급
	SOUL_JAR,          # 영혼 항아리 — 첫 판매 유닛 절반 배분
	COPPER_WIRE,       # 구리 전선 — 풀슬롯 인접 30% 전파
}

# --- 상수 ---
const MAX_UPGRADE_SLOTS := 5
const UPGRADE_REROLL_COST := 1  # 테라진
const UPGRADE_SHOP_SLOTS := 2
const STARTING_FIELD_SLOTS := 6
const MAX_FIELD_SLOTS := 8
const MAX_BENCH_SLOTS := 8
## 보드 전체 유닛 합 상한. 2026-04-19 도입 (포식종 밸런스 200).
## 전투 시뮬 비용 제한 + card-level 60cap의 board-level 보강.
const MAX_BOARD_UNITS := 200
const MAX_ROUNDS := 15
const REROLL_COST := 1
const SELL_REFUND_RATE := 1.0  # 전액 환급
const INTEREST_PER_5G := 1
const MAX_INTEREST := 2
var BOSS_ROUNDS := [4, 8, 12, 15]
const BOSS_REWARD_CHOICES := 4

## 상점 레벨업 베이스 비용 (upgrade.md 확정)
## key = 목표 레벨, value = 베이스 골드 비용
const LEVELUP_BASE_COST := {2: 5, 3: 7, 4: 8, 5: 11, 6: 13}
const LEVELUP_MAX := 6


## 시스템 결과 빈 딕셔너리. 이벤트/보상 없음을 나타냄.
static func empty_result() -> Dictionary:
	return {"events": [], "gold": 0, "terazin": 0}
