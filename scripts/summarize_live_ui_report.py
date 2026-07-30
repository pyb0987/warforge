#!/usr/bin/env python3
"""Summarize a Warforge live UI smoke report for human playtest review."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import lint_live_ui_screenshots as screenshot_lint

SCHEMA = screenshot_lint.SCHEMA
EXPECTED_STEP_LABELS = screenshot_lint.EXPECTED_SCREENSHOT_LABELS[:-1]
EXPECTED_SCREENSHOT_LABELS = screenshot_lint.EXPECTED_SCREENSHOT_LABELS


@dataclass(frozen=True)
class SummaryResult:
    ok: bool
    markdown: str
    errors: list[str]
    warnings: list[str]


def summarize_report(
    report_path: Path,
    *,
    lint_screenshots: bool = False,
    require_screenshots: bool = False,
    expected_width: int = screenshot_lint.DEFAULT_EXPECTED_WIDTH,
    expected_height: int = screenshot_lint.DEFAULT_EXPECTED_HEIGHT,
    min_file_size: int = screenshot_lint.DEFAULT_MIN_FILE_SIZE,
    min_channel_range: int = screenshot_lint.DEFAULT_MIN_CHANNEL_RANGE,
) -> SummaryResult:
    errors: list[str] = []
    warnings: list[str] = []
    report = _load_report(report_path, errors)
    if not isinstance(report, dict):
        return SummaryResult(False, _render_failure(report_path, errors), errors, warnings)

    steps = _as_list(report.get("steps"))
    events = _as_dict(report.get("events"))
    final_snapshot = _as_dict(report.get("final"))
    metadata = _as_dict(report.get("metadata"))
    screenshots = _as_list(report.get("screenshots"))

    _validate_source_report(
        report,
        steps,
        events,
        final_snapshot,
        metadata,
        screenshots,
        require_screenshots,
        errors,
        warnings,
    )

    lint_status = _screenshot_lint_status(
        report_path,
        metadata,
        lint_screenshots,
        expected_width,
        expected_height,
        min_file_size,
        min_channel_range,
        errors,
        warnings,
    )

    ok = not errors
    markdown = _render_summary(
        report_path,
        report,
        steps,
        events,
        final_snapshot,
        metadata,
        screenshots,
        lint_status,
        ok,
        errors,
        warnings,
    )
    return SummaryResult(ok, markdown, errors, warnings)


def _load_report(path: Path, errors: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        errors.append(f"report not found: {path}")
    except json.JSONDecodeError as exc:
        errors.append(f"report is not valid JSON: {exc}")
    except OSError as exc:
        errors.append(f"failed to read report {path}: {exc}")
    return None


def _validate_source_report(
    report: dict[str, Any],
    steps: list[Any],
    events: dict[str, Any],
    final_snapshot: dict[str, Any],
    metadata: dict[str, Any],
    screenshots: list[Any],
    require_screenshots: bool,
    errors: list[str],
    warnings: list[str],
) -> None:
    if report.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA!r}, got {report.get('schema')!r}")
    if report.get("ok") is not True:
        errors.append("report ok must be true")

    step_labels = [str(step.get("label", "")) for step in steps if isinstance(step, dict)]
    if step_labels != EXPECTED_STEP_LABELS:
        errors.append(
            "step labels must match expected live smoke order: "
            f"got {step_labels!r}"
        )

    screenshot_status = str(metadata.get("screenshot_status", ""))
    screenshot_labels = [
        str(record.get("label", "")) for record in screenshots if isinstance(record, dict)
    ]
    if require_screenshots and screenshot_status != "enabled":
        errors.append(
            "screenshots are required but metadata.screenshot_status is "
            f"{screenshot_status!r}"
        )
    if screenshot_status == "enabled" or require_screenshots:
        if screenshot_labels != EXPECTED_SCREENSHOT_LABELS:
            errors.append(
                "screenshot labels must match expected live smoke order: "
                f"got {screenshot_labels!r}"
            )
    elif screenshots:
        warnings.append(
            f"screenshots are present while screenshot_status is {screenshot_status!r}"
        )

    if str(final_snapshot.get("phase", "")) != "BUILD":
        errors.append(f"final phase must be BUILD, got {final_snapshot.get('phase')!r}")
    if final_snapshot.get("has_modal") is True:
        errors.append("final snapshot must be modal-free")
    if final_snapshot.get("chain_visible") is True:
        errors.append("final snapshot must not show stale chain feedback")

    identity_event = _as_dict(events.get("run_identity"))
    commander_name = str(metadata.get("commander_name", "")).strip()
    talisman_name = str(metadata.get("talisman_name", "")).strip()
    identity_texts: dict[str, str] = {}
    for label in ("build_entry", "during_chain_feedback", "after_chain_feedback"):
        identity = _as_dict(identity_event.get(label))
        text = str(identity.get("text", ""))
        identity_texts[label] = text
        rect = _as_dict(identity.get("rect"))
        if identity.get("visible") is not True:
            errors.append(f"events.run_identity.{label}.visible must be true")
        if not text.strip():
            errors.append(f"events.run_identity.{label}.text is required")
        if commander_name and commander_name not in text:
            errors.append(
                f"events.run_identity.{label}.text must include commander name"
            )
        if talisman_name and talisman_name not in text:
            errors.append(
                f"events.run_identity.{label}.text must include talisman name"
            )
        if "C:" in text or "T:" in text:
            errors.append(
                f"events.run_identity.{label}.text must not use C:/T: shorthand"
            )
        if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
            rect.get("h"), 0.0
        ) <= 0.0:
            errors.append(f"events.run_identity.{label}.rect must be nonzero")
    is_flint = (
        _to_int(metadata.get("talisman_type"), -1) == 8
        or talisman_name.lower() == "flint"
        or "부싯돌" in talisman_name
    )
    if is_flint:
        if not any(
            marker in identity_texts.get("build_entry", "")
            for marker in ("준비", "ready")
        ):
            errors.append("events.run_identity.build_entry.text must show Flint ready")
        if not any(
            marker in identity_texts.get("during_chain_feedback", "")
            for marker in ("사용됨", "used")
        ):
            errors.append(
                "events.run_identity.during_chain_feedback.text must show Flint used"
            )
        if not any(
            marker in identity_texts.get("after_chain_feedback", "")
            for marker in ("준비", "ready")
        ):
            errors.append(
                "events.run_identity.after_chain_feedback.text must show Flint ready"
            )

    _validate_commander_free_upgrade_events(
        _as_dict(events.get("commander_free_upgrade")), errors
    )
    _validate_raider_win_streak_reward(
        _as_dict(events.get("raider_win_streak_reward")),
        _to_int(metadata.get("commander_type"), -1),
        commander_name,
        errors,
    )

    milestone_event = _as_dict(events.get("run_milestone"))
    for label in ("build_entry", "after_chain_feedback"):
        step_label = "chain_feedback_last_history" if label == "after_chain_feedback" else label
        _validate_run_milestone(
            label,
            _as_dict(_step_by_label(steps, step_label).get("run_milestone")),
            _as_dict(milestone_event.get(label)),
            errors,
        )

    selection_event = _as_dict(events.get("run_selection"))
    commander_step = _step_by_label(steps, "after_run_start")
    commander_choices = _as_list(
        _as_dict(commander_step.get("choices")).get("commander_select")
    )
    commander_step_details = _as_dict(commander_step.get("commander_select"))
    commander_step_summaries = _as_list(
        commander_step_details.get("choice_summaries")
    )
    _validate_choice_card_summaries(
        "after_run_start.commander_select",
        commander_step_summaries,
        commander_choices,
        errors,
    )
    _validate_choice_context(
        "after_run_start.commander_select",
        commander_step_details,
        ("커맨더", "런 전체"),
        errors,
    )
    commander_context_text = str(commander_step_details.get("context_text", ""))
    commander_event_summaries = _as_list(
        selection_event.get("commander_choice_summaries")
    )
    _validate_choice_card_summaries(
        "events.run_selection.commander_choice_summaries",
        commander_event_summaries,
        commander_choices,
        errors,
    )
    selected_commander_summary = _as_dict(
        selection_event.get("selected_commander_summary")
    )
    if selected_commander_summary.get("id") != str(metadata.get("commander_type", "")):
        errors.append("events.run_selection.selected_commander_summary id must match metadata")
    if commander_name and commander_name not in str(
        selected_commander_summary.get("name", "")
    ):
        errors.append("events.run_selection selected commander name must match metadata")
    if str(selected_commander_summary.get("name", "")) not in identity_texts.get(
        "build_entry", ""
    ):
        errors.append("build identity must include selected commander card name")
    if str(selection_event.get("commander_context_text", "")) != commander_context_text:
        errors.append("events.run_selection.commander_context_text must match rendered step")

    talisman_step = _step_by_label(steps, "after_commander")
    talisman_choices = _as_list(
        _as_dict(talisman_step.get("choices")).get("talisman_select")
    )
    talisman_step_details = _as_dict(talisman_step.get("talisman_select"))
    talisman_step_summaries = _as_list(
        talisman_step_details.get("choice_summaries")
    )
    _validate_choice_card_summaries(
        "after_commander.talisman_select",
        talisman_step_summaries,
        talisman_choices,
        errors,
    )
    _validate_choice_context(
        "after_commander.talisman_select",
        talisman_step_details,
        ("부적", "선택한 커맨더", commander_name),
        errors,
    )
    talisman_context_text = str(talisman_step_details.get("context_text", ""))
    talisman_event_summaries = _as_list(
        selection_event.get("talisman_choice_summaries")
    )
    _validate_choice_card_summaries(
        "events.run_selection.talisman_choice_summaries",
        talisman_event_summaries,
        talisman_choices,
        errors,
    )
    selected_talisman_summary = _as_dict(
        selection_event.get("selected_talisman_summary")
    )
    if selected_talisman_summary.get("id") != str(metadata.get("talisman_type", "")):
        errors.append("events.run_selection.selected_talisman_summary id must match metadata")
    if talisman_name and talisman_name not in str(
        selected_talisman_summary.get("name", "")
    ):
        errors.append("events.run_selection selected talisman name must match metadata")
    if str(selected_talisman_summary.get("name", "")) not in identity_texts.get(
        "build_entry", ""
    ):
        errors.append("build identity must include selected talisman card name")
    if str(selection_event.get("talisman_context_text", "")) != talisman_context_text:
        errors.append("events.run_selection.talisman_context_text must match rendered step")

    readiness_event = _as_dict(events.get("build_readiness"))
    build_entry_step = _step_by_label(steps, "build_entry")
    _validate_build_readiness(
        "build_entry",
        _as_dict(build_entry_step.get("build_readiness")),
        _as_dict(build_entry_step.get("layout_rects")),
        errors,
    )
    build_entry_readiness = _as_dict(readiness_event.get("build_entry"))
    if str(build_entry_readiness.get("text", "")) != str(
        _as_dict(build_entry_step.get("build_readiness")).get("text", "")
    ):
        errors.append("events.build_readiness.build_entry.text must match rendered step")
    if build_entry_readiness.get("visible") is not True:
        errors.append("events.build_readiness.build_entry.visible must be true")

    enemy_preview_event = _as_dict(events.get("enemy_pressure_preview"))
    _validate_enemy_pressure_preview(
        "build_entry",
        _as_dict(build_entry_step.get("enemy_pressure_preview")),
        _as_dict(enemy_preview_event.get("build_entry")),
        errors,
    )

    shop_role_event = _as_dict(events.get("shop_role_cues"))
    _validate_shop_role_cues(
        "build_entry",
        build_entry_step,
        shop_role_event,
        errors,
    )

    shop_event = _as_dict(events.get("shop_reroll_scope"))
    labels = _as_dict(shop_event.get("labels"))
    if "CARD SHOP" not in str(labels.get("shop_label_text", "")):
        errors.append("events.shop_reroll_scope labels must name CARD SHOP")
    if "R:cards" not in str(labels.get("shop_label_text", "")):
        errors.append("events.shop_reroll_scope shop label must identify R:cards")
    if "T:upgrades only" not in str(labels.get("upgrade_shop_label_text", "")):
        errors.append(
            "events.shop_reroll_scope upgrade label must identify T:upgrades only"
        )
    if "UPG REROLL" not in str(labels.get("upgrade_reroll_button_text", "")):
        errors.append(
            "events.shop_reroll_scope upgrade button must identify upgrade reroll"
        )

    card_reroll = _as_dict(shop_event.get("card_reroll"))
    if card_reroll.get("cards_changed") is not True:
        errors.append("events.shop_reroll_scope.card_reroll.cards_changed must be true")
    if card_reroll.get("upgrades_preserved") is not True:
        errors.append(
            "events.shop_reroll_scope.card_reroll.upgrades_preserved must be true"
        )
    if _as_list(card_reroll.get("before_card_offer_ids")) == _as_list(
        card_reroll.get("after_card_offer_ids")
    ):
        errors.append("card reroll before/after card offers must differ")
    if _as_list(card_reroll.get("before_upgrade_offer_ids")) != _as_list(
        card_reroll.get("after_upgrade_offer_ids")
    ):
        errors.append("card reroll before/after upgrade offers must match")
    if _to_int(card_reroll.get("attempts"), 0) <= 0:
        errors.append("events.shop_reroll_scope.card_reroll.attempts must be positive")

    upgrade_reroll = _as_dict(shop_event.get("upgrade_reroll"))
    if upgrade_reroll.get("upgrades_changed") is not True:
        errors.append(
            "events.shop_reroll_scope.upgrade_reroll.upgrades_changed must be true"
        )
    if upgrade_reroll.get("cards_preserved") is not True:
        errors.append(
            "events.shop_reroll_scope.upgrade_reroll.cards_preserved must be true"
        )
    if _as_list(upgrade_reroll.get("before_upgrade_offer_ids")) == _as_list(
        upgrade_reroll.get("after_upgrade_offer_ids")
    ):
        errors.append("upgrade reroll before/after upgrade offers must differ")
    if _as_list(upgrade_reroll.get("before_card_offer_ids")) != _as_list(
        upgrade_reroll.get("after_card_offer_ids")
    ):
        errors.append("upgrade reroll before/after card offers must match")
    if _to_int(upgrade_reroll.get("attempts"), 0) <= 0:
        errors.append(
            "events.shop_reroll_scope.upgrade_reroll.attempts must be positive"
        )

    chain_event = _as_dict(events.get("chain_feedback"))
    battle_status_step = _step_by_label(steps, "battle_status_live")
    battle_status_event = _as_dict(events.get("battle_status"))
    _validate_battle_status(
        "battle_status_live",
        _as_dict(battle_status_step.get("battle_status")),
        _as_dict(battle_status_event.get("battle_status_live")),
        errors,
    )
    battle_step = _step_by_label(steps, "battle_result_open")
    battle_details = _as_dict(battle_step.get("battle_result"))
    battle_detail_text = str(battle_details.get("detail_text", ""))
    if "HP:" not in battle_detail_text:
        errors.append("battle_result_open detail_text must include HP change")
    if "Gold:" not in battle_detail_text:
        errors.append("battle_result_open detail_text must include Gold change")
    if "Next:" not in battle_detail_text:
        errors.append("battle_result_open detail_text must include next-step hint")

    if not str(chain_event.get("event_log_text", "")).strip():
        errors.append("events.chain_feedback.event_log_text is required")
    if not str(chain_event.get("last_history_display_text", "")).strip():
        errors.append("events.chain_feedback.last_history_display_text is required")
    settlement_event = _as_dict(events.get("settlement_recap"))
    settlement_text = str(settlement_event.get("text", ""))
    if settlement_event.get("visible") is not True:
        errors.append("events.settlement_recap.visible must be true")
    for expected in ("Gold:", "income", "interest", "Terazin:", "Next:", "boss reward"):
        if expected not in settlement_text:
            errors.append(f"events.settlement_recap.text must include {expected!r}")
    settlement_data = _as_dict(settlement_event.get("data"))
    for key in ("base_income", "interest", "gold_before", "gold_after", "terazin_gain"):
        if key not in settlement_data:
            errors.append(f"events.settlement_recap.data missing {key!r}")

    merge_event = _as_dict(events.get("merge_reward"))
    if merge_event.get("attached") is not True:
        errors.append("events.merge_reward.attached must be true")
    if not str(merge_event.get("selected_upgrade", "")).strip():
        errors.append("events.merge_reward.selected_upgrade is required")
    merge_history_text = str(merge_event.get("merge_history_text", ""))
    merge_history_entries = _as_list(merge_event.get("merge_history_entries"))
    if merge_event.get("merge_history_visible") is not True:
        errors.append("events.merge_reward.merge_history_visible must be true")
    if not merge_history_entries:
        errors.append("events.merge_reward.merge_history_entries is required")
    if "MERGE:" not in merge_history_text or "★1 -> ★2" not in merge_history_text:
        errors.append("events.merge_reward.merge_history_text must include star1-to-star2 merge")
    if merge_event.get("expected_merge_refund") != 0:
        errors.append("events.merge_reward.expected_merge_refund must be 0 for ★1->★2")
    if merge_event.get("gold_after_merge") != merge_event.get("expected_gold_after_merge"):
        errors.append("events.merge_reward.gold_after_merge must match expected_gold_after_merge")

    boss_event = _as_dict(events.get("boss_reward"))
    boss_step = _step_by_label(steps, "boss_reward_open")
    boss_step_choices = _as_list(_as_dict(boss_step.get("choices")).get("boss_reward"))
    boss_step_summaries = _as_list(
        _as_dict(boss_step.get("boss_reward")).get("choice_summaries")
    )
    _validate_boss_reward_summaries(
        "boss_reward_open",
        boss_step_summaries,
        boss_step_choices,
        require_immediate=True,
        require_targeted_only=False,
        errors=errors,
    )
    boss_event_summaries = _as_list(boss_event.get("open_choice_summaries"))
    _validate_boss_reward_summaries(
        "events.boss_reward.open_choice_summaries",
        boss_event_summaries,
        [str(item.get("id", "")) for item in boss_event_summaries if isinstance(item, dict)],
        require_immediate=True,
        require_targeted_only=False,
        errors=errors,
    )
    if not str(boss_event.get("selected_reward", "")).strip():
        errors.append("events.boss_reward.selected_reward is required")
    if boss_event.get("open_choice_count") != len(boss_event_summaries):
        errors.append("events.boss_reward.open_choice_count must match rendered summaries")
    if not str(boss_event.get("open_title", "")).strip():
        errors.append("events.boss_reward.open_title is required")
    if boss_event.get("phase_after") != "BUILD":
        errors.append("events.boss_reward.phase_after must be BUILD")
    selected_summary = _as_dict(boss_event.get("selected_choice_summary"))
    if selected_summary.get("id") != boss_event.get("selected_reward"):
        errors.append("events.boss_reward.selected_choice_summary must match selected_reward")

    targeted_event = _as_dict(events.get("targeted_boss_reward"))
    targeted_step = _step_by_label(steps, "targeted_boss_reward_open")
    targeted_step_choices = _as_list(
        _as_dict(targeted_step.get("choices")).get("boss_reward")
    )
    targeted_step_summaries = _as_list(
        _as_dict(targeted_step.get("boss_reward")).get("choice_summaries")
    )
    _validate_boss_reward_summaries(
        "targeted_boss_reward_open",
        targeted_step_summaries,
        targeted_step_choices,
        require_immediate=False,
        require_targeted_only=True,
        errors=errors,
    )
    targeted_event_summaries = _as_list(targeted_event.get("open_choice_summaries"))
    _validate_boss_reward_summaries(
        "events.targeted_boss_reward.open_choice_summaries",
        targeted_event_summaries,
        [
            str(item.get("id", ""))
            for item in targeted_event_summaries
            if isinstance(item, dict)
        ],
        require_immediate=False,
        require_targeted_only=True,
        errors=errors,
    )
    if not str(targeted_event.get("selected_reward", "")).strip():
        errors.append("events.targeted_boss_reward.selected_reward is required")
    before = _to_int(targeted_event.get("target_star_before"), -1)
    after = _to_int(targeted_event.get("target_star_after"), -1)
    if before < 0 or after <= before:
        errors.append("targeted boss reward must increase the selected target star")
    if _to_int(targeted_event.get("terazin_delta_after_settlement"), 0) <= 0:
        errors.append("targeted boss reward must record positive Terazin gain")

    unlock_event = _as_dict(events.get("unlock_recap"))
    unlock_step = _step_by_label(steps, "unlock_game_over_open")
    unlock_step_game_over = _as_dict(unlock_step.get("game_over"))
    unlock_summary = str(unlock_event.get("summary_text", ""))
    raw_unlocks = [
        str(value)
        for value in _as_list(unlock_event.get("raw_unlocks"))
        if str(value).strip()
    ]
    if unlock_event.get("title_text") != "VICTORY!":
        errors.append("events.unlock_recap.title_text must be VICTORY!")
    if unlock_step.get("active_modals") != ["game_over"]:
        errors.append("unlock_game_over_open must be owned by game_over modal")
    if str(unlock_step_game_over.get("summary_text", "")) != unlock_summary:
        errors.append("unlock_game_over_open summary_text must match events.unlock_recap")
    shown_count = _to_int(unlock_event.get("shown_count"), -1)
    overflow_count = _to_int(unlock_event.get("overflow_count"), -1)
    raw_unlock_count = _to_int(unlock_event.get("raw_unlock_count"), -1)
    if "New unlocks available" not in unlock_summary:
        errors.append("events.unlock_recap.summary_text missing 'New unlocks available'")
    if raw_unlocks:
        expected_shown_unlocks = raw_unlocks[: min(3, len(raw_unlocks))]
        expected_overflow_count = max(0, len(raw_unlocks) - len(expected_shown_unlocks))
        if raw_unlock_count != len(raw_unlocks):
            errors.append("events.unlock_recap.raw_unlock_count must match raw_unlocks")
        if shown_count != len(expected_shown_unlocks):
            errors.append("events.unlock_recap.shown_count must match capped raw_unlocks")
        if overflow_count != expected_overflow_count:
            errors.append("events.unlock_recap.overflow_count must match raw_unlocks")
        shown_unlocks = [str(value) for value in _as_list(unlock_event.get("shown_unlocks"))]
        if shown_unlocks != expected_shown_unlocks:
            errors.append("events.unlock_recap.shown_unlocks must match capped raw_unlocks")
        for expected in expected_shown_unlocks:
            if f"- {expected}" not in unlock_summary:
                errors.append(f"events.unlock_recap.summary_text missing {expected!r}")
        if expected_overflow_count > 0:
            if "more unlocked - all available in PROGRESS" not in unlock_summary:
                errors.append("events.unlock_recap.summary_text missing overflow copy")
            first_overflow = raw_unlocks[len(expected_shown_unlocks)]
            if f"- {first_overflow}" in unlock_summary:
                errors.append("events.unlock_recap must keep overflow rows hidden")
    else:
        if shown_count != 3:
            errors.append("events.unlock_recap.shown_count must be 3")
        if overflow_count <= 0:
            errors.append("events.unlock_recap.overflow_count must be positive")
        if raw_unlock_count != shown_count + overflow_count:
            errors.append("events.unlock_recap.raw_unlock_count must equal shown + overflow")

    progress_event = _as_dict(events.get("post_unlock_progress"))
    recent_text = str(progress_event.get("recent_unlocks_text", ""))
    unlocks_text = str(progress_event.get("unlocks_text", ""))
    details_text = str(progress_event.get("details_text", ""))
    if raw_unlocks:
        for expected in raw_unlocks[: min(3, len(raw_unlocks))]:
            if f"- {expected}" not in recent_text:
                errors.append(
                    f"events.post_unlock_progress.recent_unlocks_text missing {expected!r}"
                )
        if len(raw_unlocks) > 3:
            if "more unlocked - all available in PROGRESS" not in recent_text:
                errors.append(
                    "events.post_unlock_progress.recent_unlocks_text missing overflow copy"
                )
            if f"- {raw_unlocks[3]}" in recent_text:
                errors.append(
                    "events.post_unlock_progress.recent_unlocks_text must keep overflow rows hidden"
                )
    elif "more unlocked - all available in PROGRESS" not in recent_text:
        errors.append("events.post_unlock_progress.recent_unlocks_text missing overflow copy")
    for expected in ("연금술사", "영혼 항아리"):
        if expected not in unlocks_text:
            errors.append(f"events.post_unlock_progress.unlocks_text missing {expected!r}")
    if progress_event.get("difficulty_text") != "Difficulty 1 / 2":
        errors.append("events.post_unlock_progress.difficulty_text must be Difficulty 1 / 2")
    if progress_event.get("details_visible") is not True:
        errors.append("events.post_unlock_progress.details_visible must be true")
    for expected in ("난이도 2/8 해금", "- 연금술사: 해금", "- 영혼 항아리: 해금"):
        if expected not in details_text:
            errors.append(f"events.post_unlock_progress.details_text missing {expected!r}")

    availability_event = _as_dict(events.get("post_unlock_availability"))
    commander_choices = [
        str(value) for value in _as_list(availability_event.get("commander_choices"))
    ]
    talisman_choices = [
        str(value) for value in _as_list(availability_event.get("talisman_choices"))
    ]
    if "7" not in commander_choices:
        errors.append("events.post_unlock_availability.commander_choices missing Alchemist")
    if "11" not in talisman_choices:
        errors.append("events.post_unlock_availability.talisman_choices missing Soul Jar")
    if _to_int(availability_event.get("selected_commander"), -1) != 7:
        errors.append("events.post_unlock_availability.selected_commander must be Alchemist")
    if _to_int(availability_event.get("selected_talisman"), -1) != 11:
        errors.append("events.post_unlock_availability.selected_talisman must be Soul Jar")
    if availability_event.get("phase_after") != "BUILD":
        errors.append("events.post_unlock_availability.phase_after must be BUILD")
    if availability_event.get("has_modal_after") is not False:
        errors.append("events.post_unlock_availability.has_modal_after must be false")
    post_commander_summaries = _as_list(
        availability_event.get("commander_choice_summaries")
    )
    post_talisman_summaries = _as_list(
        availability_event.get("talisman_choice_summaries")
    )
    _validate_choice_card_summaries(
        "events.post_unlock_availability.commander_choice_summaries",
        post_commander_summaries,
        commander_choices,
        errors,
    )
    _validate_choice_card_summaries(
        "events.post_unlock_availability.talisman_choice_summaries",
        post_talisman_summaries,
        talisman_choices,
        errors,
    )
    post_selected_commander_summary = _as_dict(
        availability_event.get("selected_commander_summary")
    )
    post_selected_talisman_summary = _as_dict(
        availability_event.get("selected_talisman_summary")
    )
    if post_selected_commander_summary.get("id") != "7":
        errors.append("post-unlock selected commander summary must be Alchemist")
    if post_selected_talisman_summary.get("id") != "11":
        errors.append("post-unlock selected talisman summary must be Soul Jar")
    post_commander_step = _step_by_label(steps, "post_unlock_commander_select")
    post_commander_details = _as_dict(post_commander_step.get("commander_select"))
    _validate_choice_context(
        "post_unlock_commander_select.commander_select",
        post_commander_details,
        ("커맨더", "런 전체"),
        errors,
    )
    if (
        str(availability_event.get("commander_context_text", ""))
        != str(post_commander_details.get("context_text", ""))
    ):
        errors.append(
            "events.post_unlock_availability.commander_context_text must match rendered step"
        )
    post_talisman_step = _step_by_label(steps, "post_unlock_talisman_select")
    post_talisman_details = _as_dict(post_talisman_step.get("talisman_select"))
    _validate_choice_context(
        "post_unlock_talisman_select.talisman_select",
        post_talisman_details,
        (
            "부적",
            "선택한 커맨더",
            str(post_selected_commander_summary.get("name", "")),
        ),
        errors,
    )
    if (
        str(availability_event.get("talisman_context_text", ""))
        != str(post_talisman_details.get("context_text", ""))
    ):
        errors.append(
            "events.post_unlock_availability.talisman_context_text must match rendered step"
        )
    post_identity_text = str(
        availability_event.get("identity_text_after")
        or _as_dict(final_snapshot.get("identity")).get("text", "")
    )
    if str(post_selected_commander_summary.get("name", "")) not in post_identity_text:
        errors.append("post-unlock build identity must include selected commander name")
    if str(post_selected_talisman_summary.get("name", "")) not in post_identity_text:
        errors.append("post-unlock build identity must include selected talisman name")
    post_build_step = _step_by_label(steps, "post_unlock_build_entry")
    _validate_build_readiness(
        "post_unlock_build_entry",
        _as_dict(post_build_step.get("build_readiness")),
        _as_dict(post_build_step.get("layout_rects")),
        errors,
    )
    post_readiness = _as_dict(readiness_event.get("post_unlock_build_entry"))
    if str(post_readiness.get("text", "")) != str(
        _as_dict(post_build_step.get("build_readiness")).get("text", "")
    ):
        errors.append(
            "events.build_readiness.post_unlock_build_entry.text must match rendered step"
        )
    if post_readiness.get("visible") is not True:
        errors.append("events.build_readiness.post_unlock_build_entry.visible must be true")
    _validate_run_milestone(
        "post_unlock_build_entry",
        _as_dict(post_build_step.get("run_milestone")),
        _as_dict(milestone_event.get("post_unlock_build_entry")),
        errors,
    )
    _validate_enemy_pressure_preview(
        "post_unlock_build_entry",
        _as_dict(post_build_step.get("enemy_pressure_preview")),
        _as_dict(enemy_preview_event.get("post_unlock_build_entry")),
        errors,
    )
    _validate_shop_role_cues(
        "post_unlock_build_entry",
        post_build_step,
        shop_role_event,
        errors,
    )


def _validate_choice_card_summaries(
    label: str,
    summaries: list[Any],
    choice_ids: list[Any],
    errors: list[str],
) -> None:
    if not choice_ids:
        errors.append(f"{label} must include choice ids")
    if len(summaries) != len(choice_ids):
        errors.append(
            f"{label} summary count {len(summaries)} does not match "
            f"choice ids {len(choice_ids)}"
        )
    for idx, choice_id in enumerate(choice_ids):
        if idx >= len(summaries):
            continue
        summary = _as_dict(summaries[idx])
        if summary.get("id") != str(choice_id):
            errors.append(f"{label} summary {idx} id must match choice id")
        if _to_int(summary.get("idx"), -1) != idx:
            errors.append(f"{label} summary {idx} idx must match visible order")
        for key in ("name", "desc", "text"):
            if not str(summary.get(key, "")).strip():
                errors.append(f"{label} summary {idx} missing rendered {key}")
        text = str(summary.get("text", ""))
        if str(summary.get("name", "")) not in text:
            errors.append(f"{label} summary {idx} text must include name")
        if str(summary.get("desc", "")) not in text:
            errors.append(f"{label} summary {idx} text must include desc")
        rect = _as_dict(summary.get("rect"))
        if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
            rect.get("h"), 0.0
        ) <= 0.0:
            errors.append(f"{label} summary {idx} rect must be nonzero")
        if rect.get("visible") is not True:
            errors.append(f"{label} summary {idx} rect.visible must be true")


def _validate_choice_context(
    label: str,
    details: dict[str, Any],
    required_terms: tuple[str, ...],
    errors: list[str],
) -> None:
    text = str(details.get("context_text", "")).strip()
    if not text:
        errors.append(f"{label} context_text is required")
    for term in required_terms:
        if term and term not in text:
            errors.append(f"{label} context_text must include {term!r}")
    rect = _as_dict(details.get("context_rect"))
    if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
        rect.get("h"), 0.0
    ) <= 0.0:
        errors.append(f"{label} context_rect must be nonzero")
    if rect.get("visible") is not True:
        errors.append(f"{label} context_rect.visible must be true")


def _validate_run_milestone(
    label: str,
    step_details: dict[str, Any],
    event_details: dict[str, Any],
    errors: list[str],
) -> None:
    step_text = str(step_details.get("text", "")).strip()
    event_text = str(event_details.get("text", "")).strip()
    round_label_text = str(step_details.get("round_label_text", "")).strip()
    progress_rail_text = str(step_details.get("progress_rail_text", "")).strip()
    if event_text != step_text:
        errors.append(f"events.run_milestone.{label}.text must match rendered step")
    if str(event_details.get("round_label_text", "")).strip() != round_label_text:
        errors.append(
            f"events.run_milestone.{label}.round_label_text must match rendered step"
        )
    if str(event_details.get("progress_rail_text", "")).strip() != progress_rail_text:
        errors.append(
            f"events.run_milestone.{label}.progress_rail_text must match rendered step"
        )
    if step_details.get("visible") is not True:
        errors.append(f"{label} run_milestone.visible must be true")
    for expected in ("Goal:", "boss"):
        if expected not in step_text:
            errors.append(f"{label} run_milestone.text missing {expected!r}")
    for expected in ("Round", "boss"):
        if expected not in round_label_text:
            errors.append(
                f"{label} run_milestone.round_label_text missing {expected!r}"
            )
    _validate_run_progress_rail(label, progress_rail_text, round_label_text, errors)
    rect = _as_dict(step_details.get("rect"))
    if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
        rect.get("h"), 0.0
    ) <= 0.0:
        errors.append(f"{label} run_milestone.rect must be nonzero")
    if rect.get("visible") is not True:
        errors.append(f"{label} run_milestone.rect.visible must be true")


def _validate_run_progress_rail(
    label: str,
    progress_rail_text: str,
    round_label_text: str,
    errors: list[str],
) -> None:
    for expected in ("NOW", "rewards", "R4", "R8", "R12", "R15 final"):
        if expected not in progress_rail_text:
            errors.append(
                f"{label} run_milestone.progress_rail_text missing {expected!r}"
            )
    if progress_rail_text and progress_rail_text not in round_label_text:
        errors.append(
            f"{label} run_milestone.round_label_text must include progress rail"
        )


def _validate_commander_free_upgrade_events(
    event: dict[str, Any], errors: list[str]
) -> None:
    for label, value in sorted(event.items()):
        row = _as_dict(value)
        if not row:
            errors.append(f"events.commander_free_upgrade.{label} must be an object")
            continue
        if not str(row.get("selected_upgrade", "")).strip():
            errors.append(
                f"events.commander_free_upgrade.{label}.selected_upgrade is required"
            )
        if _to_int(row.get("selected_field_idx"), -1) < 0:
            errors.append(
                f"events.commander_free_upgrade.{label}.selected_field_idx "
                "must be nonnegative"
            )
        if not str(row.get("instruction", "")).strip():
            errors.append(
                f"events.commander_free_upgrade.{label}.instruction is required"
            )
        phase_after = str(row.get("phase_after", "")).strip()
        if phase_after not in {"BUILD", "CHAIN", "BATTLE", "SETTLEMENT"}:
            errors.append(
                f"events.commander_free_upgrade.{label}.phase_after "
                "must be a live run phase"
            )
        if _to_int(row.get("round_after"), 0) <= 0:
            errors.append(
                f"events.commander_free_upgrade.{label}.round_after must be positive"
            )


def _validate_raider_win_streak_reward(
    event: dict[str, Any],
    commander_type: int,
    commander_name: str,
    errors: list[str],
) -> None:
    is_raider = commander_type == 6 or "약탈자" in commander_name or "Raider" in commander_name
    if not event:
        if is_raider:
            errors.append("events.raider_win_streak_reward is required for Raider reports")
        return
    if not is_raider:
        errors.append("events.raider_win_streak_reward is only expected for Raider reports")
    if not str(event.get("selected_upgrade", "")).strip():
        errors.append("events.raider_win_streak_reward.selected_upgrade is required")
    if _to_int(event.get("selected_field_idx"), -1) < 0:
        errors.append(
            "events.raider_win_streak_reward.selected_field_idx must be nonnegative"
        )
    instruction = str(event.get("instruction", ""))
    if "Raider 3-win reward" not in instruction:
        errors.append(
            "events.raider_win_streak_reward.instruction must mention "
            "'Raider 3-win reward'"
        )
    before = _to_int(event.get("target_upgrade_count_before"), -1)
    after = _to_int(event.get("target_upgrade_count_after"), -1)
    if after != before + 1:
        errors.append(
            "events.raider_win_streak_reward target upgrade count must increase by 1"
        )
    if _to_int(event.get("win_count_after"), -1) != 0:
        errors.append("events.raider_win_streak_reward.win_count_after must reset to 0")
    if str(event.get("phase_after", "")) != "BUILD":
        errors.append("events.raider_win_streak_reward.phase_after must be BUILD")
    if _to_int(event.get("round_after"), 0) <= 0:
        errors.append("events.raider_win_streak_reward.round_after must be positive")
    if event.get("has_modal_after") is not False:
        errors.append("events.raider_win_streak_reward.has_modal_after must be false")


def _validate_build_readiness(
    label: str,
    details: dict[str, Any],
    layout_rects: dict[str, Any],
    errors: list[str],
) -> None:
    text = str(details.get("text", "")).strip()
    if details.get("visible") is not True:
        errors.append(f"{label} build_readiness.visible must be true")
    for expected in ("FIELD:", "체인/전투", "BENCH:", "ENEMY:", "Next:"):
        if expected not in text:
            errors.append(f"{label} build_readiness.text missing {expected!r}")
    rect = _as_dict(details.get("rect"))
    if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
        rect.get("h"), 0.0
    ) <= 0.0:
        errors.append(f"{label} build_readiness.rect must be nonzero")
    if rect.get("visible") is not True:
        errors.append(f"{label} build_readiness.rect.visible must be true")

    confirm = _as_dict(layout_rects.get("confirm_button"))
    field = _as_dict(layout_rects.get("field_container"))
    for target_name, target_rect in (
        ("confirm_button", confirm),
        ("field_container", field),
    ):
        if (
            _rect_visible(rect)
            and _rect_visible(target_rect)
            and _rects_intersect(rect, target_rect)
        ):
            errors.append(f"{label} build_readiness overlaps {target_name}")


def _validate_enemy_pressure_preview(
    label: str,
    step_details: dict[str, Any],
    event_details: dict[str, Any],
    errors: list[str],
) -> None:
    step_text = str(step_details.get("text", "")).strip()
    event_text = str(event_details.get("text", "")).strip()
    if event_text != step_text:
        errors.append(f"events.enemy_pressure_preview.{label}.text must match rendered step")
    if step_details.get("visible") is not True:
        errors.append(f"{label} enemy_pressure_preview.visible must be true")
    for expected in ("ENEMY:", "R", "ATK", "HP"):
        if expected not in step_text:
            errors.append(f"{label} enemy_pressure_preview.text missing {expected!r}")
    data = _as_dict(step_details.get("data"))
    event_data = _as_dict(event_details.get("data"))
    if event_data != data:
        errors.append(f"events.enemy_pressure_preview.{label}.data must match rendered step")
    if data.get("exact") is not False:
        errors.append(f"{label} enemy_pressure_preview.data.exact must be false")
    if _to_int(data.get("preset_count"), 0) <= 0:
        errors.append(f"{label} enemy_pressure_preview.data.preset_count must be positive")
    if _to_int(data.get("enemy_count_min"), 0) <= 0:
        errors.append(f"{label} enemy_pressure_preview.data.enemy_count_min must be positive")
    if _to_int(data.get("enemy_count_max"), 0) < _to_int(
        data.get("enemy_count_min"), 0
    ):
        errors.append(f"{label} enemy pressure count max must be >= min")
    for key in ("total_atk_min", "total_atk_max", "total_hp_min", "total_hp_max"):
        if _to_float(data.get(key), 0.0) <= 0.0:
            errors.append(f"{label} enemy_pressure_preview.data.{key} must be positive")
    rect = _as_dict(step_details.get("rect"))
    if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
        rect.get("h"), 0.0
    ) <= 0.0:
        errors.append(f"{label} enemy_pressure_preview.rect must be nonzero")
    if rect.get("visible") is not True:
        errors.append(f"{label} enemy_pressure_preview.rect.visible must be true")


def _validate_battle_status(
    label: str,
    step_details: dict[str, Any],
    event_details: dict[str, Any],
    errors: list[str],
) -> None:
    step_text = str(step_details.get("text", "")).strip()
    event_text = str(event_details.get("text", "")).strip()
    if event_text != step_text:
        errors.append(f"events.battle_status.{label}.text must match rendered step")
    if step_details.get("visible") is not True:
        errors.append(f"{label} battle_status.visible must be true")
    for expected in ("BATTLE R", "Start", "Now"):
        if expected not in step_text:
            errors.append(f"{label} battle_status.text missing {expected!r}")
    data = _as_dict(step_details.get("data"))
    event_data = _as_dict(event_details.get("data"))
    if event_data != data:
        errors.append(f"events.battle_status.{label}.data must match rendered step")
    round_num = _to_int(data.get("round"), 0)
    ally_start = _to_int(data.get("ally_start"), 0)
    enemy_start = _to_int(data.get("enemy_start"), 0)
    ally_remaining = _to_int(data.get("ally_remaining"), -1)
    enemy_remaining = _to_int(data.get("enemy_remaining"), -1)
    if round_num <= 0:
        errors.append(f"{label} battle_status.data.round must be positive")
    for name, value in (("ally_start", ally_start), ("enemy_start", enemy_start)):
        if value <= 0:
            errors.append(f"{label} battle_status.data.{name} must be positive")
    if ally_remaining < 0 or ally_remaining > ally_start:
        errors.append(
            f"{label} battle_status.data.ally_remaining must be between 0 and ally_start"
        )
    if enemy_remaining < 0 or enemy_remaining > enemy_start:
        errors.append(
            f"{label} battle_status.data.enemy_remaining must be between 0 and enemy_start"
        )
    if f"R{round_num}" not in step_text:
        errors.append(f"{label} battle_status.text must include data round")
    if f"{ally_start}A" not in step_text:
        errors.append(f"{label} battle_status.text must include ally_start")
    if f"{enemy_start}E" not in step_text:
        errors.append(f"{label} battle_status.text must include enemy_start")
    if f"{ally_remaining}A" not in step_text:
        errors.append(f"{label} battle_status.text must include ally_remaining")
    if f"{enemy_remaining}E" not in step_text:
        errors.append(f"{label} battle_status.text must include enemy_remaining")
    rect = _as_dict(step_details.get("rect"))
    if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
        rect.get("h"), 0.0
    ) <= 0.0:
        errors.append(f"{label} battle_status.rect must be nonzero")
    if rect.get("visible") is not True:
        errors.append(f"{label} battle_status.rect.visible must be true")


def _validate_shop_role_cues(
    label: str,
    step: dict[str, Any],
    event: dict[str, Any],
    errors: list[str],
) -> None:
    shop = _as_dict(step.get("shop"))
    offer_ids = _as_list(shop.get("card_offer_ids"))
    offer_roles = _as_list(shop.get("card_offer_roles"))
    event_entry = _as_dict(event.get(label))
    if _as_list(event_entry.get("card_offer_ids")) != offer_ids:
        errors.append(f"events.shop_role_cues.{label}.card_offer_ids must match rendered step")
    if _as_list(event_entry.get("card_offer_roles")) != offer_roles:
        errors.append(f"events.shop_role_cues.{label}.card_offer_roles must match rendered step")
    if len(offer_roles) != len(offer_ids):
        errors.append(f"{label} shop card_offer_roles length must match card_offer_ids")
        return
    if not offer_ids:
        errors.append(f"{label} shop must include card offers")
        return
    for idx, card_id in enumerate(offer_ids):
        if str(card_id) == "":
            continue
        summary = _as_dict(offer_roles[idx])
        if _to_int(summary.get("slot_idx"), -1) != idx:
            errors.append(f"{label} shop role {idx} slot_idx must match position")
        if str(summary.get("card_id", "")) != str(card_id):
            errors.append(f"{label} shop role {idx} card_id must match offer id")
        if not str(summary.get("role_text", "")).strip():
            errors.append(f"{label} shop role {idx} role_text is required")
        if summary.get("visible") is not True:
            errors.append(f"{label} shop role {idx} must come from a visible card")
        rect = _as_dict(summary.get("rect"))
        if _to_float(rect.get("w"), 0.0) <= 0.0 or _to_float(
            rect.get("h"), 0.0
        ) <= 0.0:
            errors.append(f"{label} shop role {idx} rect must be nonzero")


def _validate_boss_reward_summaries(
    label: str,
    summaries: list[Any],
    choice_ids: list[Any],
    *,
    require_immediate: bool,
    require_targeted_only: bool,
    errors: list[str],
) -> None:
    if not choice_ids:
        errors.append(f"{label} must include boss reward choice ids")
    if len(summaries) != len(choice_ids):
        errors.append(
            f"{label} summary count {len(summaries)} does not match "
            f"choice ids {len(choice_ids)}"
        )
    saw_immediate = False
    saw_targeted = False
    for idx, choice_id in enumerate(choice_ids):
        if idx >= len(summaries):
            continue
        summary = _as_dict(summaries[idx])
        if summary.get("id") != choice_id:
            errors.append(f"{label} summary {idx} id must match choice id")
        for key in ("name", "type", "desc", "text"):
            if not str(summary.get(key, "")).strip():
                errors.append(f"{label} summary {idx} missing rendered {key}")
        text = str(summary.get("text", ""))
        if str(summary.get("name", "")) not in text:
            errors.append(f"{label} summary {idx} text must include name")
        if str(summary.get("desc", "")) not in text:
            errors.append(f"{label} summary {idx} text must include desc")
        if "needs_target" not in summary:
            errors.append(f"{label} summary {idx} missing needs_target")
        elif bool(summary.get("needs_target")):
            saw_targeted = True
        else:
            saw_immediate = True
    if require_immediate and not saw_immediate:
        errors.append(f"{label} must include at least one immediate reward summary")
    if require_targeted_only:
        if len(choice_ids) != 1:
            errors.append(f"{label} must include exactly one targeted reward")
        if not saw_targeted:
            errors.append(f"{label} must identify a targeted reward summary")
        if saw_immediate:
            errors.append(f"{label} must not include immediate reward summaries")


def _screenshot_lint_status(
    report_path: Path,
    metadata: dict[str, Any],
    lint_screenshots: bool,
    expected_width: int,
    expected_height: int,
    min_file_size: int,
    min_channel_range: int,
    errors: list[str],
    warnings: list[str],
) -> str:
    screenshot_status = str(metadata.get("screenshot_status", ""))
    if not lint_screenshots:
        if screenshot_status == "enabled":
            warnings.append("screenshot lint was not run for enabled screenshots")
            return "NOT RUN"
        return f"SKIPPED ({screenshot_status or 'unknown'})"

    if screenshot_status != "enabled":
        errors.append(
            "screenshot lint requested but metadata.screenshot_status is "
            f"{screenshot_status!r}"
        )
        return "FAILED"

    lint_errors = screenshot_lint.validate_report(
        report_path,
        expected_width=expected_width,
        expected_height=expected_height,
        min_file_size=min_file_size,
        min_channel_range=min_channel_range,
    )
    if lint_errors:
        errors.extend(f"screenshot lint: {error}" for error in lint_errors)
        return "FAILED"
    return "PASS"


def _render_failure(report_path: Path, errors: list[str]) -> str:
    lines = [
        "# Warforge Live UI Playtest Summary",
        "",
        f"Source: `{report_path}`",
        "Verdict: INCOMPLETE",
        "",
        "## Issues",
    ]
    lines.extend(f"- {error}" for error in errors)
    return "\n".join(lines) + "\n"


def _render_summary(
    report_path: Path,
    report: dict[str, Any],
    steps: list[Any],
    events: dict[str, Any],
    final_snapshot: dict[str, Any],
    metadata: dict[str, Any],
    screenshots: list[Any],
    lint_status: str,
    ok: bool,
    errors: list[str],
    warnings: list[str],
) -> str:
    by_label = _steps_by_label(steps)
    shots_by_label = _screenshots_by_label(screenshots)
    chain_event = _as_dict(events.get("chain_feedback"))
    settlement_event = _as_dict(events.get("settlement_recap"))
    merge_event = _as_dict(events.get("merge_reward"))
    shop_event = _as_dict(events.get("shop_reroll_scope"))
    identity_event = _as_dict(events.get("run_identity"))
    milestone_event = _as_dict(events.get("run_milestone"))
    selection_event = _as_dict(events.get("run_selection"))
    boss_event = _as_dict(events.get("boss_reward"))
    targeted_event = _as_dict(events.get("targeted_boss_reward"))
    unlock_event = _as_dict(events.get("unlock_recap"))
    progress_event = _as_dict(events.get("post_unlock_progress"))
    availability_event = _as_dict(events.get("post_unlock_availability"))
    enemy_preview_event = _as_dict(events.get("enemy_pressure_preview"))
    battle_status_event = _as_dict(events.get("battle_status"))
    commander_free_upgrade_event = _as_dict(events.get("commander_free_upgrade"))
    raider_reward_event = _as_dict(events.get("raider_win_streak_reward"))

    lines = [
        "# Warforge Live UI Playtest Summary",
        "",
        f"Source: `{report_path}`",
        f"Verdict: {'PASS' if ok else 'INCOMPLETE'}",
        f"Schema: `{report.get('schema', '')}`",
        f"Report OK: {_yes_no(report.get('ok') is True)}",
        "",
        "## Run",
        f"- Commander: {_metadata_name(metadata, 'commander_name')}",
        f"- Talisman: {_metadata_name(metadata, 'talisman_name')}",
        f"- Selected identity setup: {_selected_identity_setup_line(metadata)}",
        f"- Final state: {final_snapshot.get('phase', '?')} R{final_snapshot.get('round', '?')}, modal-free {_yes_no(final_snapshot.get('has_modal') is not True)}",
        f"- Screenshots: {metadata.get('screenshot_status', 'unknown')} ({len(screenshots)} records)",
        f"- Screenshot lint: {lint_status}",
        "",
        "## What Codex Saw",
    ]
    lines.extend(_flow_lines(
        by_label,
        identity_event,
        milestone_event,
        selection_event,
        commander_free_upgrade_event,
        raider_reward_event,
        enemy_preview_event,
        battle_status_event,
        chain_event,
        settlement_event,
        merge_event,
        shop_event,
        boss_event,
        targeted_event,
        unlock_event,
        progress_event,
        availability_event,
    ))

    key_shots = _key_screenshot_lines(shots_by_label)
    if key_shots:
        lines.extend(["", "## Key Screenshots"])
        lines.extend(key_shots)

    lines.extend(["", "## Evidence"])
    lines.extend(_evidence_lines(by_label, events, final_snapshot))

    lines.extend(["", "## Issues"])
    if errors:
        lines.extend(f"- ERROR: {error}" for error in errors)
    if warnings:
        lines.extend(f"- WARNING: {warning}" for warning in warnings)
    if not errors and not warnings:
        lines.append("- None")
    return "\n".join(lines) + "\n"


def _flow_lines(
    by_label: dict[str, dict[str, Any]],
    identity_event: dict[str, Any],
    milestone_event: dict[str, Any],
    selection_event: dict[str, Any],
    commander_free_upgrade_event: dict[str, Any],
    raider_reward_event: dict[str, Any],
    enemy_preview_event: dict[str, Any],
    battle_status_event: dict[str, Any],
    chain_event: dict[str, Any],
    settlement_event: dict[str, Any],
    merge_event: dict[str, Any],
    shop_event: dict[str, Any],
    boss_event: dict[str, Any],
    targeted_event: dict[str, Any],
    unlock_event: dict[str, Any],
    progress_event: dict[str, Any],
    availability_event: dict[str, Any],
) -> list[str]:
    build_entry = by_label.get("build_entry", {})
    build_readiness = _as_dict(build_entry.get("build_readiness"))
    build_shop = _as_dict(build_entry.get("shop"))
    chain_step = by_label.get("chain_feedback_open", {})
    last_chain = _as_dict(by_label.get("chain_feedback_last_history", {}).get("last_chain_history"))
    target_step = by_label.get("targeted_boss_reward_target_open", {})
    target_select = _as_dict(target_step.get("target_select"))
    battle_step = by_label.get("battle_result_open", {})
    battle_details = _as_dict(battle_step.get("battle_result"))
    battle_detail = _single_line(battle_details.get("detail_text"))
    settlement_detail = _single_line(settlement_event.get("text"))
    boss_choices = _choice_summaries_line(boss_event.get("open_choice_summaries"))
    targeted_choices = _choice_summaries_line(
        targeted_event.get("open_choice_summaries")
    )
    shown_count = _to_int(unlock_event.get("shown_count"), 0)
    overflow_count = _to_int(unlock_event.get("overflow_count"), 0)
    raw_unlock_count = _to_int(unlock_event.get("raw_unlock_count"), 0)
    progress_recent = _single_line(progress_event.get("recent_unlocks_text"))
    card_reroll = _as_dict(shop_event.get("card_reroll"))
    upgrade_reroll = _as_dict(shop_event.get("upgrade_reroll"))
    identity_build = _single_line(_as_dict(identity_event.get("build_entry")).get("text"))
    identity_during = _single_line(
        _as_dict(identity_event.get("during_chain_feedback")).get("text")
    )
    identity_after = _single_line(
        _as_dict(identity_event.get("after_chain_feedback")).get("text")
    )
    milestone_build = _single_line(
        _as_dict(milestone_event.get("build_entry")).get("round_label_text")
    )
    progress_rail = _single_line(
        _as_dict(milestone_event.get("build_entry")).get("progress_rail_text")
    )
    milestone_after = _single_line(
        _as_dict(milestone_event.get("after_chain_feedback")).get("text")
    )
    selected_commander = _choice_summary_short(
        selection_event.get("selected_commander_summary")
    )
    selected_talisman = _choice_summary_short(
        selection_event.get("selected_talisman_summary")
    )
    commander_context = _single_line(selection_event.get("commander_context_text"))
    talisman_context = _single_line(selection_event.get("talisman_context_text"))
    post_commander = _choice_summary_short(
        availability_event.get("selected_commander_summary")
    )
    post_talisman = _choice_summary_short(
        availability_event.get("selected_talisman_summary")
    )
    readiness_text = _single_line(build_readiness.get("text"))
    enemy_preview_text = _single_line(
        _as_dict(enemy_preview_event.get("build_entry")).get("text")
    )
    battle_status_text = _single_line(
        _as_dict(battle_status_event.get("battle_status_live")).get("text")
    )
    shop_role_text = _shop_role_line(build_shop.get("card_offer_roles"))
    free_upgrade_text = _commander_free_upgrade_line(commander_free_upgrade_event)
    raider_reward_text = _raider_win_streak_reward_line(raider_reward_event)

    display_chain = _single_line(chain_event.get("last_history_display_text"))
    raw_chain = _single_line(chain_event.get("event_log_text"))
    if not display_chain:
        display_chain = _single_line(last_chain.get("display_text"))

    lines = [
        f"- Run start reached BUILD R{build_entry.get('round', '?')} with no modal: {_yes_no(build_entry.get('has_modal') is not True)}.",
        f"- BUILD readiness cue: {readiness_text or 'missing'}.",
        f"- Enemy pressure preview rendered before commit: {enemy_preview_text or 'missing'}.",
        f"- First-shop role cues rendered: {shop_role_text or 'missing'}.",
        f"- Choice context before BUILD: commander {commander_context or 'missing'}; talisman {talisman_context or 'missing'}.",
        f"- Selection cards rendered before BUILD: commander {selected_commander or 'missing'}; talisman {selected_talisman or 'missing'}.",
        f"- Run identity rendered: {identity_build or 'missing'}; during chain: {identity_during or 'missing'}; next BUILD: {identity_after or 'missing'}.",
        f"- Run milestone rendered: {milestone_build or 'missing'}; after first settlement: {milestone_after or 'missing'}.",
        f"- Run progression rail rendered: {progress_rail or 'missing'}.",
        f"- Chain feedback paused in {chain_step.get('phase', '?')} with {_single_line(chain_event.get('counter_text')) or 'unknown triggers'}; visible summary: {display_chain or raw_chain or 'missing'}.",
        f"- Battle start status rendered: {battle_status_text or 'missing'}.",
		f"- Battle aftermath popup explained: {battle_detail or 'missing'}.",
        f"- Last-chain BUILD panel displayed: {_yes_no(last_chain.get('visible') is True)}.",
        f"- Settlement recap displayed: {settlement_detail or 'missing'}.",
        f"- Shop reroll scope held: card reroll changed cards and preserved upgrades {_yes_no(card_reroll.get('upgrades_preserved') is True)}; upgrade reroll changed upgrades and preserved cards {_yes_no(upgrade_reroll.get('cards_preserved') is True)}.",
        f"- Boss reward choices rendered: {boss_choices or 'missing'}.",
        f"- Boss reward popup title: {_single_line(boss_event.get('open_title')) or 'missing'}.",
        f"- Merge reward attached {merge_event.get('selected_upgrade', '?')} to {merge_event.get('survivor_card_id', '?')} star {merge_event.get('survivor_star', '?')}; merge history visible {_yes_no(merge_event.get('merge_history_visible') is True)} and gold {merge_event.get('gold_before_purchase', '?')} -> {merge_event.get('gold_after_merge', '?')} after -{merge_event.get('purchase_cost', '?')}g purchase, +{merge_event.get('expected_merge_refund', '?')}g merge refund.",
        f"- Boss reward selected {boss_event.get('selected_reward', '?')} and returned to {boss_event.get('phase_after', '?')} R{boss_event.get('round_after', '?')}.",
        f"- Targeted boss reward choice rendered: {targeted_choices or 'missing'}.",
        f"- Targeted boss reward selected {targeted_event.get('selected_reward', '?')} on field index {targeted_event.get('selected_field_idx', '?')}: star {targeted_event.get('target_star_before', '?')} -> {targeted_event.get('target_star_after', '?')}, Terazin delta {targeted_event.get('terazin_delta_after_settlement', '?')}.",
        f"- Target overlay instruction was visible: {_yes_no(bool(str(target_select.get('instruction', '')).strip()))}.",
        f"- Run-end unlock recap showed {shown_count}/{raw_unlock_count} unlocks and overflowed {overflow_count}: {_single_line(unlock_event.get('summary_text')) or 'missing'}.",
        f"- Next run-start recent unlocks matched the recap: {progress_recent or 'missing'}.",
        f"- Post-unlock selection cards rendered: commander {post_commander or 'missing'}; talisman {post_talisman or 'missing'}.",
        f"- Overflow availability was actionable: commander {availability_event.get('selected_commander', '?')} and talisman {availability_event.get('selected_talisman', '?')} reached {availability_event.get('phase_after', '?')} modal-free {_yes_no(availability_event.get('has_modal_after') is False)}.",
    ]
    if free_upgrade_text:
        lines.insert(9, f"- Commander free upgrade flow resolved: {free_upgrade_text}.")
    if raider_reward_text:
        lines.insert(10, f"- Raider 3-win reward proved live: {raider_reward_text}.")
    return lines


def _key_screenshot_lines(shots_by_label: dict[str, dict[str, Any]]) -> list[str]:
    labels = [
		"build_entry",
		"chain_feedback_open",
		"battle_status_live",
		"battle_result_open",
        "chain_feedback_last_history",
        "merge_reward_open",
        "boss_reward_open",
        "targeted_boss_reward_target_open",
        "unlock_game_over_open",
        "post_unlock_run_start",
        "post_unlock_progress_details",
        "post_unlock_talisman_select",
        "final",
    ]
    lines: list[str] = []
    for label in labels:
        record = shots_by_label.get(label)
        if not record:
            continue
        lines.append(f"- `{label}`: `{record.get('path', '')}`")
    return lines


def _evidence_lines(
    by_label: dict[str, dict[str, Any]],
    events: dict[str, Any],
    final_snapshot: dict[str, Any],
) -> list[str]:
    lines = [
        f"- Step labels: {', '.join(by_label.keys())}",
        f"- Event keys: {', '.join(events.keys())}",
        f"- Final active modals: {_as_list(final_snapshot.get('active_modals'))}",
    ]
    last_step = by_label.get("chain_feedback_last_history", {})
    last_history = _as_dict(last_step.get("last_chain_history"))
    raw = str(last_history.get("text", ""))
    display = str(last_history.get("display_text", ""))
    if raw or display:
        lines.append(f"- Last-chain raw has Complete line: {_yes_no('Complete:' in raw)}")
        lines.append(f"- Last-chain display text: {_single_line(display)}")
    settlement_event = _as_dict(events.get("settlement_recap"))
    if settlement_event:
        settlement_data = _as_dict(settlement_event.get("data"))
        lines.append(
            "- Settlement recap source fields: "
            f"base_income={settlement_data.get('base_income', '?')}, "
            f"interest={settlement_data.get('interest', '?')}, "
            f"terazin_gain={settlement_data.get('terazin_gain', '?')}"
        )
    unlock_event = _as_dict(events.get("unlock_recap"))
    if unlock_event:
        lines.append(
            "- Unlock recap counts: "
            f"shown={unlock_event.get('shown_count', '?')}, "
            f"overflow={unlock_event.get('overflow_count', '?')}, "
            f"raw={unlock_event.get('raw_unlock_count', '?')}"
        )
    availability_event = _as_dict(events.get("post_unlock_availability"))
    if availability_event:
        lines.append(
            "- Post-unlock availability choices: "
            f"commanders={availability_event.get('commander_choices', [])}, "
            f"talismans={availability_event.get('talisman_choices', [])}"
        )
    shop_event = _as_dict(events.get("shop_reroll_scope"))
    if shop_event:
        card_reroll = _as_dict(shop_event.get("card_reroll"))
        upgrade_reroll = _as_dict(shop_event.get("upgrade_reroll"))
        lines.append(
            "- Shop reroll offers: "
            f"cards {card_reroll.get('before_card_offer_ids', [])} -> "
            f"{card_reroll.get('after_card_offer_ids', [])}; upgrades "
            f"{upgrade_reroll.get('before_upgrade_offer_ids', [])} -> "
            f"{upgrade_reroll.get('after_upgrade_offer_ids', [])}"
        )
    return lines


def _choice_summaries_line(value: Any) -> str:
    summaries = _as_list(value)
    parts: list[str] = []
    for item in summaries:
        summary = _as_dict(item)
        name = str(summary.get("name", "")).strip()
        type_text = str(summary.get("type", "")).strip()
        desc = str(summary.get("desc", "")).strip()
        if not name and not desc:
            continue
        label = name or str(summary.get("id", "?")).strip() or "?"
        if type_text:
            label = f"{label} [{type_text}]"
        if desc:
            label = f"{label}: {desc}"
        if bool(summary.get("needs_target", False)):
            label = f"{label} (targeted)"
        parts.append(label)
    return " | ".join(parts)


def _choice_summary_short(value: Any) -> str:
    summary = _as_dict(value)
    name = str(summary.get("name", "")).strip()
    desc = str(summary.get("desc", "")).strip()
    if not name:
        return ""
    if desc:
        return f"{name}: {desc}"
    return name


def _shop_role_line(value: Any) -> str:
    parts: list[str] = []
    for item in _as_list(value):
        summary = _as_dict(item)
        card_id = str(summary.get("card_id", "")).strip()
        role = _single_line(summary.get("role_text"))
        if not card_id or not role:
            continue
        name = _single_line(summary.get("name")) or card_id
        parts.append(f"{name}={role}")
    return "; ".join(parts)


def _commander_free_upgrade_line(event: dict[str, Any]) -> str:
    parts: list[str] = []
    for label, value in sorted(event.items()):
        row = _as_dict(value)
        upgrade = str(row.get("selected_upgrade", "")).strip()
        if not upgrade:
            continue
        field_idx = row.get("selected_field_idx", "?")
        instruction = _single_line(row.get("instruction"))
        text = f"{label}: {upgrade} -> field {field_idx}"
        if instruction:
            text += f" ({instruction})"
        parts.append(text)
    return "; ".join(parts)


def _raider_win_streak_reward_line(event: dict[str, Any]) -> str:
    if not event:
        return ""
    upgrade = str(event.get("selected_upgrade", "")).strip()
    field_idx = event.get("selected_field_idx", "?")
    before = event.get("target_upgrade_count_before", "?")
    after = event.get("target_upgrade_count_after", "?")
    phase = event.get("phase_after", "?")
    round_after = event.get("round_after", "?")
    return (
        f"{upgrade or '?'} -> field {field_idx}, upgrades {before}->{after}, "
        f"win count {event.get('win_count_after', '?')}, {phase} R{round_after}"
    )


def _steps_by_label(steps: list[Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for step in steps:
        if isinstance(step, dict):
            result[str(step.get("label", ""))] = step
    return result


def _step_by_label(steps: list[Any], label: str) -> dict[str, Any]:
    for step in steps:
        if isinstance(step, dict) and step.get("label") == label:
            return step
    return {}


def _screenshots_by_label(screenshots: list[Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for record in screenshots:
        if isinstance(record, dict):
            result[str(record.get("label", ""))] = record
    return result


def _metadata_name(metadata: dict[str, Any], key: str) -> str:
    value = str(metadata.get(key, "")).strip()
    return value or "unknown"


def _selected_identity_setup_line(metadata: dict[str, Any]) -> str:
    if metadata.get("unlock_selected") is not True:
        return "normal profile"
    commanders = ", ".join(
        str(value)
        for value in _as_list(metadata.get("preunlocked_selected_commanders"))
    )
    talismans = ", ".join(
        str(value)
        for value in _as_list(metadata.get("preunlocked_selected_talismans"))
    )
    parts: list[str] = []
    if commanders:
        parts.append(f"commanders {commanders}")
    if talismans:
        parts.append(f"talismans {talismans}")
    unlocked = "; ".join(parts) if parts else "requested identity was already unlocked"
    return f"unlock-selected profile ({unlocked})"


def _single_line(value: Any) -> str:
    text = str(value or "").strip()
    return " | ".join(line.strip() for line in text.splitlines() if line.strip())


def _yes_no(value: bool) -> str:
    return "yes" if value else "no"


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _to_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _to_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _rect_visible(rect: dict[str, Any]) -> bool:
    return (
        rect.get("visible") is True
        and _to_float(rect.get("w"), 0.0) > 0.0
        and _to_float(rect.get("h"), 0.0) > 0.0
    )


def _rects_intersect(a: dict[str, Any], b: dict[str, Any]) -> bool:
    ax = _to_float(a.get("x"), 0.0)
    ay = _to_float(a.get("y"), 0.0)
    aw = _to_float(a.get("w"), 0.0)
    ah = _to_float(a.get("h"), 0.0)
    bx = _to_float(b.get("x"), 0.0)
    by = _to_float(b.get("y"), 0.0)
    bw = _to_float(b.get("w"), 0.0)
    bh = _to_float(b.get("h"), 0.0)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize a Warforge live UI smoke JSON report."
    )
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--lint-screenshots",
        action="store_true",
        help="Rerun screenshot lint against the same report before summarizing.",
    )
    parser.add_argument(
        "--require-screenshots",
        action="store_true",
        help="Mark the summary incomplete unless screenshot capture was enabled.",
    )
    parser.add_argument(
        "--expected-width",
        type=int,
        default=screenshot_lint.DEFAULT_EXPECTED_WIDTH,
    )
    parser.add_argument(
        "--expected-height",
        type=int,
        default=screenshot_lint.DEFAULT_EXPECTED_HEIGHT,
    )
    parser.add_argument(
        "--min-file-size",
        type=int,
        default=screenshot_lint.DEFAULT_MIN_FILE_SIZE,
    )
    parser.add_argument(
        "--min-channel-range",
        type=int,
        default=screenshot_lint.DEFAULT_MIN_CHANNEL_RANGE,
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    result = summarize_report(
        args.report,
        lint_screenshots=args.lint_screenshots,
        require_screenshots=args.require_screenshots,
        expected_width=args.expected_width,
        expected_height=args.expected_height,
        min_file_size=args.min_file_size,
        min_channel_range=args.min_channel_range,
    )
    if args.out:
        args.out.write_text(result.markdown, encoding="utf-8")
    else:
        print(result.markdown, end="")
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
