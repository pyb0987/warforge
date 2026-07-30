from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import run_live_ui_identity_matrix as matrix  # noqa: E402


class LiveUiIdentityMatrixTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_parse_identity_accepts_labelled_pair(self) -> None:
        case = matrix.parse_identity("Coin Path=gambler:two_faced_coin")

        self.assertEqual(case.label, "coin_path")
        self.assertEqual(case.commander, "gambler")
        self.assertEqual(case.talisman, "two_faced_coin")

    def test_parse_identity_generates_label(self) -> None:
        case = matrix.parse_identity("alchemist:soul_jar")

        self.assertEqual(case.label, "alchemist_soul_jar")
        self.assertEqual(case.commander, "alchemist")
        self.assertEqual(case.talisman, "soul_jar")

    def test_preset_identities_returns_default_rows(self) -> None:
        cases = matrix.preset_identities("default")

        self.assertEqual(
            [case.label for case in cases],
            ["baseline", "coin", "golden_die", "locked_economy"],
        )

    def test_preset_identities_returns_expanded_rows(self) -> None:
        cases = matrix.preset_identities("expanded")

        self.assertEqual(
            [case.label for case in cases],
            ["breeder", "collector", "strategist", "smith", "raider"],
        )
        self.assertEqual(cases[-1].commander, "raider")
        self.assertEqual(cases[-1].talisman, "mercury_drop")

    def test_preset_identities_rejects_unknown_preset(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown preset"):
            matrix.preset_identities("missing")

    def test_duplicate_labels_fail_before_running_godot(self) -> None:
        calls = []

        result = matrix.run_matrix(
            [
                matrix.IdentityCase("same", "gambler", "flint"),
                matrix.IdentityCase("same", "gambler", "golden_die"),
            ],
            self.tmpdir,
            run_command=lambda *args, **kwargs: calls.append((args, kwargs)),
        )

        self.assertFalse(result["ok"])
        self.assertEqual(calls, [])
        self.assertIn("duplicate identity label: same", result["errors"])

    def test_run_matrix_writes_per_identity_paths_and_uses_unlock_selected(self) -> None:
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append((cmd, kwargs))
            report_path = _arg_value(cmd, "--out")
            Path(report_path).write_text(
                json.dumps(
                    {
                        "metadata": {
                            "commander_name": "Gambler",
                            "talisman_name": "Golden Die",
                            "unlock_selected": True,
                            "preunlocked_selected_commanders": [],
                            "preunlocked_selected_talismans": [6],
                        }
                    }
                ),
                encoding="utf-8",
            )
            return subprocess.CompletedProcess(cmd, 0, stdout="ok", stderr="")

        def fake_summary(path):
            return SimpleNamespace(ok=True, markdown=f"summary {path}", errors=[], warnings=[])

        result = matrix.run_matrix(
            [matrix.IdentityCase("golden", "gambler", "golden_die")],
            self.tmpdir,
            godot_bin="fake-godot",
            preset="expanded",
            run_command=fake_run,
            summarize_func=fake_summary,
        )

        self.assertTrue(result["ok"])
        self.assertEqual(result["metadata"]["preset"], "expanded")
        self.assertEqual(len(calls), 1)
        cmd, kwargs = calls[0]
        self.assertEqual(cmd[0], "fake-godot")
        self.assertIn("--headless", cmd)
        self.assertIn("--unlock-selected=true", cmd)
        self.assertIn("--reset-meta=true", cmd)
        self.assertEqual(kwargs["env"]["HOME"], str(self.tmpdir / "golden" / "godot_home"))
        row = result["identities"][0]
        self.assertEqual(row["commander_name"], "Gambler")
        self.assertEqual(row["talisman_name"], "Golden Die")
        self.assertEqual(row["selected_identity_setup"], "unlock-selected profile (talismans 6)")
        self.assertTrue(Path(row["summary_path"]).exists())

    def test_nonzero_report_exit_fails_matrix_even_if_summary_can_read_report(self) -> None:
        def fake_run(cmd, **_kwargs):
            report_path = _arg_value(cmd, "--out")
            Path(report_path).write_text(
                json.dumps({"metadata": {"commander_name": "Gambler"}}),
                encoding="utf-8",
            )
            return subprocess.CompletedProcess(cmd, 2, stdout="", stderr="bad\nnews")

        result = matrix.run_matrix(
            [matrix.IdentityCase("bad", "gambler", "flint")],
            self.tmpdir,
            run_command=fake_run,
            summarize_func=lambda _path: SimpleNamespace(
                ok=True, markdown="summary", errors=[], warnings=[]
            ),
        )

        self.assertFalse(result["ok"])
        row = result["identities"][0]
        self.assertIn("live UI report exited 2", row["errors"])
        self.assertEqual(row["stderr_tail"], "bad\nnews")

    def test_render_matrix_summary_lists_passing_rows(self) -> None:
        rendered = matrix.render_matrix_summary(
            {
                "schema": matrix.SCHEMA,
                "ok": True,
                "identities": [
                    {
                        "ok": True,
                        "label": "baseline",
                        "commander_name": "Gambler",
                        "talisman_name": "Flint",
                        "selected_identity_setup": "normal profile",
                        "report_path": "/tmp/report.json",
                    }
                ],
                "errors": [],
            }
        )

        self.assertIn("Verdict: PASS", rendered)
        self.assertIn("Preset: `unknown`", rendered)
        self.assertIn("Passing identities: 1/1", rendered)
        self.assertIn("Gambler + Flint", rendered)

    def test_render_matrix_summary_lists_preset_metadata(self) -> None:
        rendered = matrix.render_matrix_summary(
            {
                "schema": matrix.SCHEMA,
                "ok": True,
                "metadata": {"preset": "expanded"},
                "identities": [],
                "errors": [],
            }
        )

        self.assertIn("Preset: `expanded`", rendered)


def _arg_value(cmd: list[str], prefix: str) -> str:
    for item in cmd:
        if item.startswith(prefix + "="):
            return item.split("=", 1)[1]
    raise AssertionError(f"{prefix}=... not found in {cmd!r}")
