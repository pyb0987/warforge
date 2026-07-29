extends GutTest

const TooltipScene = preload("res://scenes/ui/card_tooltip.tscn")

var _tooltip = null


func before_each() -> void:
	_tooltip = TooltipScene.instantiate()
	add_child_autofree(_tooltip)


func test_sp_arsenal_tooltip_uses_steampunk_upgrade_not_druid_growth() -> void:
	var card := CardInstance.create("sp_arsenal")

	_tooltip.show_card(card, Vector2.ZERO)

	var glossary_text: String = _tooltip.get_keyword_panel_text()
	assert_true(_tooltip.is_keyword_panel_visible())
	assert_string_contains(glossary_text, "[스팀펑크] 개량")
	assert_false(glossary_text.contains("[드루이드] 성장"),
		"제국 병기창 tooltip must not attach Druid growth glossary")
	assert_false(glossary_text.contains("나무 성장"),
		"제국 병기창 tooltip must not show Druid tree-growth keyword")
	assert_false(glossary_text.contains("🌳"),
		"제국 병기창 tooltip must not show Druid tree icon/definition")


func test_non_druid_bare_growth_tooltip_is_common_not_druid() -> void:
	var card := CardInstance.create("sp_interest")

	_tooltip.show_card(card, Vector2.ZERO)

	var glossary_text: String = _tooltip.get_keyword_panel_text()
	assert_string_contains(glossary_text, "[공통] 성장")
	assert_false(glossary_text.contains("[드루이드] 성장"))


func test_explicit_tree_growth_tooltip_uses_druid_keyword_without_nested_common_growth() -> void:
	var card := CardInstance.create("pr_parasitic_swarm")

	_tooltip.show_card(card, Vector2.ZERO)

	var glossary_text: String = _tooltip.get_keyword_panel_text()
	assert_string_contains(glossary_text, "[드루이드] 나무 성장")
	assert_false(glossary_text.contains("[공통] 성장"))
