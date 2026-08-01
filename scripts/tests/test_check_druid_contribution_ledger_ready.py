import importlib.util
import json
import pathlib
import tempfile
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "check_druid_contribution_ledger_ready.py"
)
SPEC = importlib.util.spec_from_file_location("check_druid_ready", MODULE_PATH)
check_druid_ready = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_druid_ready)


class CheckDruidContributionLedgerReadyTest(unittest.TestCase):
    def test_passes_with_valid_focus_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_trace(tmp, [_round_end(["dr_spore_cloud"]), _battle(_snapshot())])

            result = check_druid_ready.check_trace_dir(tmp, "soft_druid")

        self.assertTrue(result["ok"])
        self.assertEqual(result["errors"], [])
        self.assertEqual(result["summary"]["focus_frames"], 1)

    def test_fails_missing_focus_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_trace(tmp, [_round_end(["dr_spore_cloud"]), _battle()])

            result = check_druid_ready.check_trace_dir(tmp, "soft_druid")

        self.assertFalse(result["ok"])
        self.assertIn("missing focus snapshots: 1", result["errors"])

    def test_fails_invalid_scalar_snapshot(self):
        snapshot = _snapshot()
        snapshot["cards"][0]["stacks"][0]["final_attack_interval"] = "1.5"
        with tempfile.TemporaryDirectory() as tmp:
            _write_trace(tmp, [_round_end(["dr_spore_cloud"]), _battle(snapshot)])

            result = check_druid_ready.check_trace_dir(tmp, "soft_druid")

        self.assertFalse(result["ok"])
        self.assertIn("invalid focus snapshots: 1", result["errors"])

    def test_fails_without_matching_traces(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = check_druid_ready.check_trace_dir(tmp, "soft_druid")

        self.assertFalse(result["ok"])
        self.assertIn("no traces found", result["errors"][0])


def _write_trace(trace_dir, events):
    path = pathlib.Path(trace_dir) / "soft_druid_1.jsonl"
    with path.open("w", encoding="utf-8") as f:
        for event in events:
            f.write(json.dumps(event) + "\n")


def _round_end(active_board):
    return {
        "t": "round_end",
        "round": 9,
        "active_board": active_board,
        "detected_path": "druid_garden",
    }


def _battle(snapshot=None):
    event = {
        "t": "battle",
        "round": 9,
        "won": False,
        "ally_survived": 0,
        "enemy_survived": 12,
    }
    if snapshot is not None:
        event["druid_combat_snapshot"] = snapshot
    return event


def _snapshot():
    stack = {
        "unit_id": "dr_spore",
        "count": 2,
        "eff_atk": 10.0,
        "eff_hp": 50.0,
        "base_attack_interval": 2.0,
        "upgrade_as_mult": 1.0,
        "unique_as_mult": 1.0,
        "temp_as_mult": 1.0,
        "final_attack_interval": 1.5,
        "total_atk": 20.0,
        "total_hp": 100.0,
        "total_dps": 13.33,
        "range": 1,
        "move_speed": 1,
        "def": 0,
    }
    card = {
        "idx": 0,
        "id": "dr_spore_cloud",
        "star": 2,
        "trees": 4,
        "units": 2,
        "total_atk": 20.0,
        "total_hp": 100.0,
        "total_dps": 13.33,
        "growth_atk_pct": 0.0,
        "growth_hp_pct": 0.0,
        "unique_buff_pct": 0.0,
        "upgrade_as_mult": 1.0,
        "unique_as_mult": 1.0,
        "temp_as_mult": 1.0,
        "shield_hp_pct": 0.0,
        "enemy_atk_debuff": 0.28,
        "enemy_as_debuff": 0.28,
        "kill_hp_recover_pct": 0.0,
        "mechanics": [],
        "stacks": [stack],
    }
    return {
        "forest_depth": 4,
        "druid_count": 1,
        "druid_units": 2,
        "druid_total_atk": 20.0,
        "druid_total_hp": 100.0,
        "druid_total_dps": 13.33,
        "enemy_debuffs": {"atk_pct": 0.28, "as_pct": 0.28},
        "cards": [card],
    }


if __name__ == "__main__":
    unittest.main()
