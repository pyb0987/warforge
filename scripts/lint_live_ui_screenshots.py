#!/usr/bin/env python3
"""Lint live UI smoke screenshot artifacts.

Run this after a non-headless `live_ui_smoke_report` run with
`--screenshot-dir`. The lint validates that the JSON report and PNG artifacts
are bound to the same ordered smoke path, and uses structured UI rects for the
target-overlay overlap guard instead of guessing from pixels.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCHEMA = "warforge-live-ui-smoke/v1"
EXPECTED_SCREENSHOT_LABELS = [
    "initial",
    "after_run_start",
    "after_commander",
    "build_entry",
    "chain_feedback_open",
    "battle_status_live",
    "battle_result_open",
    "chain_feedback_last_history",
    "merge_shop_seeded",
    "merge_reward_open",
    "merge_reward_closed",
    "boss_reward_open",
    "boss_reward_closed",
    "targeted_boss_reward_open",
    "targeted_boss_reward_target_open",
    "targeted_boss_reward_closed",
    "unlock_game_over_open",
    "post_unlock_run_start",
    "post_unlock_progress_details",
    "post_unlock_commander_select",
    "post_unlock_talisman_select",
    "post_unlock_build_entry",
    "final",
]
TARGET_FRAME_LABEL = "targeted_boss_reward_target_open"
CHAIN_FRAME_LABEL = "chain_feedback_open"
BOSS_REWARD_FRAME_LABEL = "boss_reward_open"
TARGETED_BOSS_REWARD_FRAME_LABEL = "targeted_boss_reward_open"
BATTLE_RESULT_FRAME_LABEL = "battle_result_open"
LAST_CHAIN_FRAME_LABEL = "chain_feedback_last_history"
DEFAULT_EXPECTED_WIDTH = 1280
DEFAULT_EXPECTED_HEIGHT = 720
DEFAULT_MIN_FILE_SIZE = 1000
DEFAULT_MIN_CHANNEL_RANGE = 4
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNELS_BY_COLOR_TYPE = {
    0: 1,  # grayscale
    2: 3,  # RGB
    4: 2,  # grayscale + alpha
    6: 4,  # RGBA
}
COLOR_CHANNELS_BY_COLOR_TYPE = {
    0: 1,
    2: 3,
    4: 1,
    6: 3,
}


@dataclass(frozen=True)
class PngStats:
    width: int
    height: int
    bit_depth: int
    color_type: int
    channel_range: int


def validate_report(
    report_path: Path,
    expected_width: int = DEFAULT_EXPECTED_WIDTH,
    expected_height: int = DEFAULT_EXPECTED_HEIGHT,
    min_file_size: int = DEFAULT_MIN_FILE_SIZE,
    min_channel_range: int = DEFAULT_MIN_CHANNEL_RANGE,
) -> list[str]:
    errors: list[str] = []
    report = _load_report(report_path, errors)
    if not isinstance(report, dict):
        return errors

    if report.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA!r}, got {report.get('schema')!r}")
    if report.get("ok") is not True:
        errors.append("report ok must be true")

    metadata = _as_dict(report.get("metadata"))
    if metadata.get("screenshot_status") != "enabled":
        errors.append(
            "metadata.screenshot_status must be 'enabled' for screenshot lint, "
            f"got {metadata.get('screenshot_status')!r}"
        )
    screenshot_dir = Path(str(metadata.get("screenshot_dir", "")))

    steps = _as_list(report.get("steps"))
    final_snapshot = _as_dict(report.get("final"))
    screenshots = _as_list(report.get("screenshots"))
    _validate_label_order(steps, screenshots, errors)
    _validate_snapshot_bindings(steps, final_snapshot, screenshots, errors)
    _validate_screenshot_files(
        screenshots,
        screenshot_dir,
        expected_width,
        expected_height,
        min_file_size,
        min_channel_range,
        errors,
    )
    _validate_chain_frames(steps, errors)
    _validate_battle_result_frame(steps, errors)
    _validate_boss_reward_frame(steps, BOSS_REWARD_FRAME_LABEL, False, errors)
    _validate_boss_reward_frame(
        steps, TARGETED_BOSS_REWARD_FRAME_LABEL, True, errors
    )
    _validate_target_frame(steps, errors)
    return errors


def read_png_stats(path: Path) -> PngStats:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("not a PNG file")

    pos = len(PNG_SIGNATURE)
    ihdr: tuple[int, int, int, int, int, int, int] | None = None
    idat = bytearray()
    saw_iend = False
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        chunk_type = data[pos + 4 : pos + 8]
        chunk_start = pos + 8
        chunk_end = chunk_start + length
        if chunk_end + 4 > len(data):
            raise ValueError("truncated PNG chunk")
        chunk = data[chunk_start:chunk_end]
        if chunk_type == b"IHDR":
            if length != 13:
                raise ValueError("invalid IHDR length")
            ihdr = struct.unpack(">IIBBBBB", chunk)
        elif chunk_type == b"IDAT":
            idat.extend(chunk)
        elif chunk_type == b"IEND":
            saw_iend = True
            break
        pos = chunk_end + 4

    if ihdr is None:
        raise ValueError("missing IHDR")
    if not saw_iend:
        raise ValueError("missing IEND")
    if not idat:
        raise ValueError("missing IDAT")

    width, height, bit_depth, color_type, compression, filter_method, interlace = ihdr
    if bit_depth != 8:
        raise ValueError(f"unsupported PNG bit depth {bit_depth}")
    if color_type not in CHANNELS_BY_COLOR_TYPE:
        raise ValueError(f"unsupported PNG color type {color_type}")
    if compression != 0 or filter_method != 0 or interlace != 0:
        raise ValueError("unsupported PNG compression/filter/interlace mode")

    channels = CHANNELS_BY_COLOR_TYPE[color_type]
    color_channels = COLOR_CHANNELS_BY_COLOR_TYPE[color_type]
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    expected_raw_len = height * (stride + 1)
    if len(raw) < expected_raw_len:
        raise ValueError("truncated PNG image data")

    min_value = 255
    max_value = 0
    previous = bytearray(stride)
    offset = 0
    for _y in range(height):
        filter_type = raw[offset]
        offset += 1
        filtered = raw[offset : offset + stride]
        offset += stride
        row = _unfilter_row(filter_type, filtered, previous, channels)
        for px in range(0, stride, channels):
            for c in range(color_channels):
                value = row[px + c]
                if value < min_value:
                    min_value = value
                if value > max_value:
                    max_value = value
        previous = row

    return PngStats(
        width=width,
        height=height,
        bit_depth=bit_depth,
        color_type=color_type,
        channel_range=max_value - min_value,
    )


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


def _validate_label_order(
    steps: list[Any],
    screenshots: list[Any],
    errors: list[str],
) -> None:
    step_labels = [
        str(step.get("label", "")) for step in steps if isinstance(step, dict)
    ]
    snapshot_labels = step_labels + ["final"]
    if snapshot_labels != EXPECTED_SCREENSHOT_LABELS:
        errors.append(
            "step labels must match expected live smoke order: "
            f"got {snapshot_labels!r}"
        )

    screenshot_labels = [
        str(record.get("label", "")) for record in screenshots if isinstance(record, dict)
    ]
    if screenshot_labels != EXPECTED_SCREENSHOT_LABELS:
        errors.append(
            "screenshot labels must match expected live smoke order: "
            f"got {screenshot_labels!r}"
        )
    duplicate_labels = sorted(
        {label for label in screenshot_labels if screenshot_labels.count(label) > 1}
    )
    if duplicate_labels:
        errors.append(f"duplicate screenshot labels: {duplicate_labels}")


def _validate_snapshot_bindings(
    steps: list[Any],
    final_snapshot: dict[str, Any],
    screenshots: list[Any],
    errors: list[str],
) -> None:
    snapshots = [step for step in steps if isinstance(step, dict)] + [final_snapshot]
    if len(screenshots) != len(EXPECTED_SCREENSHOT_LABELS):
        errors.append(
            f"expected {len(EXPECTED_SCREENSHOT_LABELS)} screenshots, "
            f"got {len(screenshots)}"
        )
    for idx, expected_label in enumerate(EXPECTED_SCREENSHOT_LABELS):
        if idx >= len(snapshots):
            errors.append(f"missing snapshot for {expected_label}")
            continue
        snapshot = _as_dict(snapshots[idx])
        if idx >= len(screenshots) or not isinstance(screenshots[idx], dict):
            errors.append(f"missing top-level screenshot record for {expected_label}")
            continue
        nested = _as_dict(snapshot.get("screenshot"))
        top = _as_dict(screenshots[idx])
        for key in ("label", "path", "width", "height"):
            if nested.get(key) != top.get(key):
                errors.append(
                    f"{expected_label} nested screenshot {key!r} does not "
                    f"match top-level record"
                )


def _validate_screenshot_files(
    screenshots: list[Any],
    screenshot_dir: Path,
    expected_width: int,
    expected_height: int,
    min_file_size: int,
    min_channel_range: int,
    errors: list[str],
) -> None:
    seen_paths: set[str] = set()
    for idx, expected_label in enumerate(EXPECTED_SCREENSHOT_LABELS):
        if idx >= len(screenshots) or not isinstance(screenshots[idx], dict):
            continue
        record = screenshots[idx]
        path_text = str(record.get("path", ""))
        path = Path(path_text)
        if not path.is_absolute():
            errors.append(f"{expected_label} screenshot path is not absolute: {path_text}")
        if path_text in seen_paths:
            errors.append(f"{expected_label} reuses screenshot path: {path_text}")
        seen_paths.add(path_text)

        expected_name = f"{idx + 1:03d}-{_safe_filename(expected_label)}.png"
        if path.name != expected_name:
            errors.append(
                f"{expected_label} screenshot filename must be {expected_name}, "
                f"got {path.name}"
            )
        if str(screenshot_dir) and not _is_relative_to(path, screenshot_dir):
            errors.append(
                f"{expected_label} screenshot path is outside screenshot_dir: {path_text}"
            )
        if not path.exists():
            errors.append(f"{expected_label} screenshot file is missing: {path_text}")
            continue

        file_size = path.stat().st_size
        if file_size < min_file_size:
            errors.append(
                f"{expected_label} screenshot file is too small: "
                f"{file_size} bytes < {min_file_size}"
            )

        try:
            stats = read_png_stats(path)
        except (OSError, ValueError, zlib.error) as exc:
            errors.append(f"{expected_label} screenshot is unreadable: {exc}")
            continue

        recorded_width = _to_int(record.get("width"), -1)
        recorded_height = _to_int(record.get("height"), -1)
        if (recorded_width, recorded_height) != (expected_width, expected_height):
            errors.append(
                f"{expected_label} recorded dimensions must be "
                f"{expected_width}x{expected_height}, got "
                f"{recorded_width}x{recorded_height}"
            )
        if (stats.width, stats.height) != (recorded_width, recorded_height):
            errors.append(
                f"{expected_label} PNG dimensions disagree with report: "
                f"{stats.width}x{stats.height} vs "
                f"{recorded_width}x{recorded_height}"
            )
        if stats.channel_range < min_channel_range:
            errors.append(
                f"{expected_label} screenshot appears blank: color range "
                f"{stats.channel_range} < {min_channel_range}"
            )


def _validate_target_frame(steps: list[Any], errors: list[str]) -> None:
    target_step = None
    for step in steps:
        if isinstance(step, dict) and step.get("label") == TARGET_FRAME_LABEL:
            target_step = step
            break
    if target_step is None:
        errors.append(f"missing target frame {TARGET_FRAME_LABEL}")
        return

    if target_step.get("active_modals") != ["target_select"]:
        errors.append(
            f"{TARGET_FRAME_LABEL} must be owned by target_select modal, "
            f"got {target_step.get('active_modals')!r}"
        )
    actionable = _as_dict(target_step.get("actionable"))
    if actionable.get("target_select") is not True:
        errors.append(f"{TARGET_FRAME_LABEL} target_select must be actionable")
    choices = _as_dict(target_step.get("choices"))
    if choices.get("target_select") != [0]:
        errors.append(
            f"{TARGET_FRAME_LABEL} expected target choices [0], "
            f"got {choices.get('target_select')!r}"
        )

    details = _as_dict(target_step.get("target_select"))
    if not str(details.get("instruction", "")).strip():
        errors.append(f"{TARGET_FRAME_LABEL} missing target instruction text")
    if not str(details.get("detail", "")).strip():
        errors.append(f"{TARGET_FRAME_LABEL} missing target detail text")
    preview_text = "\n".join(str(item) for item in _as_list(details.get("preview_texts")))
    if "\u26051 -> \u26052" not in preview_text:
        errors.append(f"{TARGET_FRAME_LABEL} missing eligible star preview")
    if "MAX \u26053" not in preview_text:
        errors.append(f"{TARGET_FRAME_LABEL} missing ineligible star preview")

    rects = _as_dict(target_step.get("layout_rects"))
    instruction = _rect(rects.get("target_instruction"))
    detail = _rect(rects.get("target_detail"))
    confirm = _rect(rects.get("confirm_button"))
    tutorial = _rect(rects.get("tutorial_panel"))
    for name, rect in (
        ("target_instruction", instruction),
        ("target_detail", detail),
        ("confirm_button", confirm),
    ):
        if rect is None:
            errors.append(f"{TARGET_FRAME_LABEL} missing valid layout rect: {name}")

    for label_name, label_rect in (
        ("target_instruction", instruction),
        ("target_detail", detail),
    ):
        if label_rect is None:
            continue
        if confirm is not None and _visible(label_rect) and _visible(confirm):
            if _intersects(label_rect, confirm):
                errors.append(
                    f"{TARGET_FRAME_LABEL} {label_name} overlaps confirm_button"
                )
        if tutorial is not None and _visible(label_rect) and _visible(tutorial):
            if _intersects(label_rect, tutorial):
                errors.append(
                    f"{TARGET_FRAME_LABEL} {label_name} overlaps tutorial_panel"
                )


def _validate_chain_frames(steps: list[Any], errors: list[str]) -> None:
    chain_step = _find_step(steps, CHAIN_FRAME_LABEL)
    last_step = _find_step(steps, LAST_CHAIN_FRAME_LABEL)
    if chain_step is None:
        errors.append(f"missing chain frame {CHAIN_FRAME_LABEL}")
        return
    if last_step is None:
        errors.append(f"missing last-chain frame {LAST_CHAIN_FRAME_LABEL}")
        return

    if chain_step.get("phase") != "CHAIN":
        errors.append(
            f"{CHAIN_FRAME_LABEL} must be in CHAIN phase, "
            f"got {chain_step.get('phase')!r}"
        )
    if chain_step.get("active_modals") not in ([], None):
        errors.append(
            f"{CHAIN_FRAME_LABEL} must not be modal-owned, "
            f"got {chain_step.get('active_modals')!r}"
        )
    if chain_step.get("chain_visible") is not True:
        errors.append(f"{CHAIN_FRAME_LABEL} chain_visible must be true")
    chain_feedback = _as_dict(chain_step.get("chain_feedback"))
    if chain_feedback.get("event_panel_visible") is not True:
        errors.append(f"{CHAIN_FRAME_LABEL} event panel must be visible")
    event_log = str(chain_feedback.get("event_log_text", ""))
    if "Complete:" not in event_log:
        errors.append(f"{CHAIN_FRAME_LABEL} missing Complete line")
    if "+Unit" not in event_log:
        errors.append(f"{CHAIN_FRAME_LABEL} missing unit event text")
    counter_text = str(chain_feedback.get("counter_text", ""))
    if "Triggers:" not in counter_text:
        errors.append(f"{CHAIN_FRAME_LABEL} missing trigger counter text")

    rects = _as_dict(chain_step.get("layout_rects"))
    counter = _rect(rects.get("chain_counter"))
    if counter is None:
        errors.append(f"{CHAIN_FRAME_LABEL} missing chain_counter rect")
    elif not _visible(counter):
        errors.append(f"{CHAIN_FRAME_LABEL} chain_counter rect is hidden")
    elif _overlaps_any_visible(
        counter,
        rects,
        ("hp_label", "gold_label", "terazin_label"),
    ):
        errors.append(f"{CHAIN_FRAME_LABEL} chain_counter overlaps HUD labels")

    if last_step.get("phase") != "BUILD":
        errors.append(
            f"{LAST_CHAIN_FRAME_LABEL} must be in BUILD phase, "
            f"got {last_step.get('phase')!r}"
        )
    if last_step.get("chain_visible") is not False:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} chain_visible must be false")
    last_history = _as_dict(last_step.get("last_chain_history"))
    if last_history.get("visible") is not True:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} last-chain panel must be visible")
    last_text = str(last_history.get("text", ""))
    if "Complete:" not in last_text:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} missing Complete history")
    display_text = str(last_history.get("display_text", ""))
    if "#1 " not in display_text or "#2 " not in display_text:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} missing compact event rows")
    if "Complete:" in display_text:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} display text repeats Complete line")
    if " / " in display_text or "(Unit Added" in display_text:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} display text keeps raw layer detail")
    settlement = _as_dict(last_step.get("last_settlement_recap"))
    if settlement.get("visible") is not True:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} settlement recap must be visible")
    settlement_text = str(settlement.get("text", ""))
    for expected in ("LAST SETTLEMENT", "Gold:", "income", "interest", "Terazin:", "Next:"):
        if expected not in settlement_text:
            errors.append(
                f"{LAST_CHAIN_FRAME_LABEL} settlement recap missing {expected!r}"
            )
    settlement_data = _as_dict(settlement.get("data"))
    for key in (
        "round",
        "next_round",
        "gold_before",
        "gold_after",
        "gold_delta",
        "base_income",
        "interest",
        "interest_basis_gold",
        "terazin_before",
        "terazin_after",
        "terazin_delta",
        "terazin_gain",
    ):
        if key not in settlement_data:
            errors.append(
                f"{LAST_CHAIN_FRAME_LABEL} settlement data missing {key!r}"
            )

    rects = _as_dict(last_step.get("layout_rects"))
    last_panel = _rect(rects.get("last_chain_panel"))
    settlement_panel = _rect(rects.get("settlement_recap_panel"))
    tutorial_panel = _rect(rects.get("tutorial_panel"))
    confirm = _rect(rects.get("confirm_button"))
    battle_status = _rect(rects.get("battle_status"))
    field_container = _rect(rects.get("field_container"))
    if last_panel is None:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} missing last_chain_panel rect")
    elif not _visible(last_panel):
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} last_chain_panel rect is hidden")
    elif float(last_panel["h"]) < 90:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} last_chain_panel is too short")
    if battle_status is not None and _visible(battle_status):
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} battle_status must be hidden")
    if settlement_panel is None:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} missing settlement_recap_panel rect")
    elif not _visible(settlement_panel):
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} settlement_recap_panel rect is hidden")
    elif float(settlement_panel["h"]) < 90:
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} settlement_recap_panel is too short")
    if (
        settlement_panel is not None
        and tutorial_panel is not None
        and _visible(settlement_panel)
        and _visible(tutorial_panel)
        and _intersects(settlement_panel, tutorial_panel)
    ):
        errors.append(
            f"{LAST_CHAIN_FRAME_LABEL} settlement_recap_panel overlaps tutorial_panel"
        )
    if (
        last_panel is not None
        and confirm is not None
        and _visible(last_panel)
        and _visible(confirm)
        and _intersects(last_panel, confirm)
    ):
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} last_chain_panel overlaps confirm_button")
    if (
        last_panel is not None
        and field_container is not None
        and _visible(last_panel)
        and _visible(field_container)
        and _intersects(last_panel, field_container)
    ):
        errors.append(f"{LAST_CHAIN_FRAME_LABEL} last_chain_panel overlaps field_container")
    for target_name, target_rect in (
        ("confirm_button", confirm),
        ("field_container", field_container),
        ("last_chain_panel", last_panel),
    ):
        if (
            settlement_panel is not None
            and target_rect is not None
            and _visible(settlement_panel)
            and _visible(target_rect)
            and _intersects(settlement_panel, target_rect)
        ):
            errors.append(
                f"{LAST_CHAIN_FRAME_LABEL} settlement_recap_panel overlaps {target_name}"
            )


def _validate_battle_result_frame(steps: list[Any], errors: list[str]) -> None:
    battle_step = _find_step(steps, BATTLE_RESULT_FRAME_LABEL)
    if battle_step is None:
        errors.append(f"missing battle result frame {BATTLE_RESULT_FRAME_LABEL}")
        return
    if battle_step.get("active_modals") != ["battle_result"]:
        errors.append(
            f"{BATTLE_RESULT_FRAME_LABEL} must be owned by battle_result modal, "
            f"got {battle_step.get('active_modals')!r}"
        )
    if battle_step.get("battle_result_visible") is not True:
        errors.append(f"{BATTLE_RESULT_FRAME_LABEL} battle result must be visible")

    details = _as_dict(battle_step.get("battle_result"))
    result_text = str(details.get("result_text", ""))
    detail_text = str(details.get("detail_text", ""))
    summary_text = str(details.get("summary_text", ""))
    if result_text not in ("VICTORY", "DEFEAT"):
        errors.append(
            f"{BATTLE_RESULT_FRAME_LABEL} result text must be VICTORY or DEFEAT"
        )
    for expected in ("Round", "HP:", "Gold:"):
        if expected not in detail_text:
            errors.append(
                f"{BATTLE_RESULT_FRAME_LABEL} detail text missing {expected!r}"
            )
    if "Next:" not in summary_text or "Next:" not in detail_text:
        errors.append(f"{BATTLE_RESULT_FRAME_LABEL} missing next-step hint")

    rects = _as_dict(battle_step.get("layout_rects"))
    popup_rect = _rect(rects.get("battle_result_popup"))
    if popup_rect is None:
        errors.append(f"{BATTLE_RESULT_FRAME_LABEL} missing battle_result_popup rect")
    elif not _visible(popup_rect):
        errors.append(f"{BATTLE_RESULT_FRAME_LABEL} battle_result_popup rect is hidden")


def _validate_boss_reward_frame(
    steps: list[Any],
    label: str,
    expect_targeted_only: bool,
    errors: list[str],
) -> None:
    step = _find_step(steps, label)
    if step is None:
        errors.append(f"missing boss reward frame {label}")
        return
    if step.get("active_modals") != ["boss_reward"]:
        errors.append(
            f"{label} must be owned by boss_reward modal, "
            f"got {step.get('active_modals')!r}"
        )
    actionable = _as_dict(step.get("actionable"))
    if actionable.get("boss_reward") is not True:
        errors.append(f"{label} boss_reward must be actionable")
    choices = _as_list(_as_dict(step.get("choices")).get("boss_reward"))
    if not choices:
        errors.append(f"{label} must expose boss reward choice ids")

    details = _as_dict(step.get("boss_reward"))
    if not str(details.get("title", "")).strip():
        errors.append(f"{label} missing boss reward title")
    summaries = _as_list(details.get("choice_summaries"))
    if len(summaries) != len(choices):
        errors.append(
            f"{label} choice_summaries length {len(summaries)} "
            f"does not match choice ids {len(choices)}"
        )

    saw_targeted = False
    saw_immediate = False
    for idx, choice_id in enumerate(choices):
        if idx >= len(summaries):
            continue
        summary = _as_dict(summaries[idx])
        if summary.get("id") != choice_id:
            errors.append(
                f"{label} summary {idx} id {summary.get('id')!r} "
                f"does not match choice id {choice_id!r}"
            )
        for key in ("name", "type", "desc", "text"):
            if not str(summary.get(key, "")).strip():
                errors.append(f"{label} summary {idx} missing rendered {key}")
        text = str(summary.get("text", ""))
        if str(summary.get("name", "")) not in text:
            errors.append(f"{label} summary {idx} text omits rendered name")
        if str(summary.get("desc", "")) not in text:
            errors.append(f"{label} summary {idx} text omits rendered desc")
        if "needs_target" not in summary:
            errors.append(f"{label} summary {idx} missing needs_target")
        elif bool(summary.get("needs_target")):
            saw_targeted = True
        else:
            saw_immediate = True
        rect = _rect(summary.get("rect"))
        if rect is None:
            errors.append(f"{label} summary {idx} missing valid rect")
        elif not _visible(rect):
            errors.append(f"{label} summary {idx} rect is hidden")

    rects = _as_dict(step.get("layout_rects"))
    popup_rect = _rect(rects.get("boss_reward_popup"))
    if popup_rect is None:
        errors.append(f"{label} missing boss_reward_popup rect")
    elif not _visible(popup_rect):
        errors.append(f"{label} boss_reward_popup rect is hidden")

    if expect_targeted_only:
        if len(choices) != 1:
            errors.append(f"{label} expected exactly one forced targeted reward")
        if not saw_targeted:
            errors.append(f"{label} expected a targeted reward summary")
        if saw_immediate:
            errors.append(f"{label} should not include immediate reward summaries")
    elif not saw_immediate:
        errors.append(f"{label} expected at least one immediate reward summary")


def _find_step(steps: list[Any], label: str) -> dict[str, Any] | None:
    for step in steps:
        if isinstance(step, dict) and step.get("label") == label:
            return step
    return None


def _overlaps_any_visible(
    rect: Rect,
    rects: dict[str, Any],
    keys: tuple[str, ...],
) -> bool:
    for key in keys:
        other = _rect(rects.get(key))
        if other is not None and _visible(other) and _intersects(rect, other):
            return True
    return False


def _unfilter_row(
    filter_type: int,
    filtered: bytes | bytearray,
    previous: bytearray,
    bytes_per_pixel: int,
) -> bytearray:
    row = bytearray(len(filtered))
    for i, byte in enumerate(filtered):
        left = row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
        up = previous[i] if previous else 0
        up_left = previous[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
        if filter_type == 0:
            value = byte
        elif filter_type == 1:
            value = byte + left
        elif filter_type == 2:
            value = byte + up
        elif filter_type == 3:
            value = byte + ((left + up) // 2)
        elif filter_type == 4:
            value = byte + _paeth(left, up, up_left)
        else:
            raise ValueError(f"unsupported PNG filter {filter_type}")
        row[i] = value & 0xFF
    return row


def _paeth(left: int, up: int, up_left: int) -> int:
    predictor = left + up - up_left
    pa = abs(predictor - left)
    pb = abs(predictor - up)
    pc = abs(predictor - up_left)
    if pa <= pb and pa <= pc:
        return left
    if pb <= pc:
        return up
    return up_left


def _rect(value: Any) -> dict[str, float | bool] | None:
    data = _as_dict(value)
    if not data:
        return None
    try:
        x = float(data["x"])
        y = float(data["y"])
        w = float(data["w"])
        h = float(data["h"])
    except (KeyError, TypeError, ValueError):
        return None
    if w <= 0 or h <= 0:
        return None
    return {
        "x": x,
        "y": y,
        "w": w,
        "h": h,
        "visible": bool(data.get("visible", False)),
    }


def _intersects(a: dict[str, float | bool], b: dict[str, float | bool]) -> bool:
    return not (
        float(a["x"]) + float(a["w"]) <= float(b["x"])
        or float(b["x"]) + float(b["w"]) <= float(a["x"])
        or float(a["y"]) + float(a["h"]) <= float(b["y"])
        or float(b["y"]) + float(b["h"]) <= float(a["y"])
    )


def _visible(rect: dict[str, float | bool]) -> bool:
    return bool(rect.get("visible", False))


def _safe_filename(value: str) -> str:
    text = value.strip().lower()
    result = ""
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789-_"
    for ch in text:
        if ch in allowed:
            result += ch
        elif not result.endswith("-"):
            result += "-"
    return result.rstrip("-") or "snapshot"


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _to_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except (OSError, ValueError):
        return False


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Warforge live UI screenshot report artifacts."
    )
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-width", type=int, default=DEFAULT_EXPECTED_WIDTH)
    parser.add_argument("--expected-height", type=int, default=DEFAULT_EXPECTED_HEIGHT)
    parser.add_argument("--min-file-size", type=int, default=DEFAULT_MIN_FILE_SIZE)
    parser.add_argument(
        "--min-channel-range",
        type=int,
        default=DEFAULT_MIN_CHANNEL_RANGE,
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    errors = validate_report(
        args.report,
        expected_width=args.expected_width,
        expected_height=args.expected_height,
        min_file_size=args.min_file_size,
        min_channel_range=args.min_channel_range,
    )
    if errors:
        print("[lint_live_ui_screenshots] violations:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(
        "PASS live UI screenshot lint: "
        f"{len(EXPECTED_SCREENSHOT_LABELS)} screenshots, "
        f"{args.expected_width}x{args.expected_height}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
