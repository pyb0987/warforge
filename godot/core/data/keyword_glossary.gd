extends Node
## Keyword glossary. Autoloaded as "KeywordGlossary".
## 카드 효과 텍스트의 도메인 키워드 정의.

var _keywords := {
	"부화": {
		"theme": "포식종",
		"definition": "칼날 유충 유닛을 카드에 추가",
	},
	"변태": {
		"theme": "포식종",
		"definition": "카드 내 최약 유닛을 소모하여 최강 유닛 1기 추가",
	},
	"제조": {
		"theme": "스팀펑크",
		"definition": "유닛 구성에서 유닛을 추가 생산",
	},
	"개량": {
		"theme": "스팀펑크",
		"definition": "카드의 ATK를 영구 증가 (% 기반)",
	},
	"강화": {
		"theme": "공통",
		"definition": "카드의 ATK(+HP)를 영구 증가 (% 기반)",
	},
	"성장": {
		"theme": "드루이드",
		"definition": "기본 스탯 대비 ATK/HP 영구 % 증가",
	},
	"번식": {
		"theme": "드루이드",
		"definition": "드루이드 카드에 유닛 추가 (성장 페널티 동반 가능)",
	},
	"계급": {
		"theme": "군대",
		"definition": "카드에 축적되는 카운터. 랭크 4/10 milestone에서 (강화) 변환 + 고유 효과 해금. 훈련으로 +1 증가",
	},
	"랭크": {
		"theme": "군대",
		"definition": "계급 수치. '랭크 N 이상' 조건은 카드의 계급이 N에 도달하면 활성. 상위 milestone 도달 시 하위 milestone 효과도 그대로 유효 (누적).",
	},
	"비(강화)": {
		"theme": "군대",
		"definition": "(강화) 상태가 아닌 일반 유닛. 랭크 milestone에서 (강화)로 변환 가능",
	},
	"훈련": {
		"theme": "군대",
		"definition": "카드의 계급을 +1 증가",
	},
	"징집": {
		"theme": "군대",
		"definition": "징집 풀(6종) 에서 동등 확률로 1 종 뽑기 → 유닛별 기수 차등만큼 유닛 추가 (신병 3기, 바이커/드론 2기, 기타 1기). 이 카드 계급 4+: 각 유닛 50% 확률로 (강화) 변환. 계급 10+: 모든 유닛 (강화) 변환 + 엘리트 유닛 1기 추가.",
	},
	"(강화)": {
		"theme": "군대",
		"definition": "강화된 군대 유닛. 기존 유닛의 상위 스탯 버전",
	},
	"방어막": {
		"theme": "공통",
		"definition": "전투 시작 시 부여되는 추가 HP (전투 종료 시 소멸)",
	},
	"🌳": {
		"theme": "드루이드",
		"definition": "나무 카운터. 드루이드 효과의 배율/조건에 사용. 전체 나무 수 = 필드 위 모든 드루이드 카드의 🌳 합계",
	},
}


func get_definition(keyword: String) -> String:
	if _keywords.has(keyword):
		return _keywords[keyword]["definition"]
	return ""


func get_theme(keyword: String) -> String:
	if _keywords.has(keyword):
		return _keywords[keyword]["theme"]
	return ""


func get_all_keywords() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(_keywords.keys())
	return keys


func has_keyword(keyword: String) -> bool:
	return _keywords.has(keyword)
