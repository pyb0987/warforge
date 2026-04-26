"""Unit tests for lint_card_spawn.py.

회귀 시나리오:
  - CardInstance.create 외부 호출 → 차단
  - bench/board 직접 대입 → 차단
  - 화이트리스트(game_state.gd, tests/) → 통과
  - 라인 단위 opt-out 주석 → 통과
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import lint_card_spawn  # noqa: E402


def _make_file(tmpdir: Path, rel_path: str, content: str) -> Path:
    full = tmpdir / rel_path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")
    return full


class LintCardSpawnTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmpdir = Path(self._tmp.name)
        self._orig_root = lint_card_spawn.REPO_ROOT
        lint_card_spawn.REPO_ROOT = self.tmpdir

    def tearDown(self) -> None:
        lint_card_spawn.REPO_ROOT = self._orig_root
        self._tmp.cleanup()

    def test_card_create_outside_whitelist_flagged(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "func bad():\n\tvar c = CardInstance.create('sp_assembly')\n",
        )
        self.assertTrue(lint_card_spawn.scan_file(f), "외부 create는 위반")

    def test_zone_assign_outside_whitelist_flagged(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "func bad():\n\tstate.bench[0] = some_card\n",
        )
        self.assertTrue(lint_card_spawn.scan_file(f), "외부 bench 대입은 위반")

    def test_board_assign_outside_whitelist_flagged(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/sim/foo.gd",
            "func bad():\n\tstate.board[idx] = some_card\n",
        )
        self.assertTrue(lint_card_spawn.scan_file(f), "외부 board 대입은 위반")

    def test_game_state_whitelisted(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/core/game_state.gd",
            "func spawn():\n\tvar c = CardInstance.create('x')\n\tbench[0] = c\n",
        )
        self.assertEqual(lint_card_spawn.scan_file(f), [], "game_state.gd는 화이트리스트")

    def test_tests_dir_whitelisted(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/tests/test_foo.gd",
            "func test():\n\tvar c = CardInstance.create('x')\n\t_state.board[0] = c\n",
        )
        self.assertEqual(lint_card_spawn.scan_file(f), [], "tests/는 화이트리스트")

    def test_card_create_with_opt_out_passes(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "func preview():\n\tvar c = CardInstance.create('x')  # lint:allow card-create\n",
        )
        self.assertEqual(
            lint_card_spawn.scan_file(f), [],
            "opt-out 주석 있으면 통과 (시각 미리보기)",
        )

    def test_zone_assign_with_opt_out_passes(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/sim/foo.gd",
            "func swap():\n\tstate.board[0] = state.board[1]  # lint:allow zone-assign\n",
        )
        self.assertEqual(
            lint_card_spawn.scan_file(f), [],
            "opt-out 주석 있으면 통과 (스왑)",
        )

    def test_zone_comparison_not_flagged(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "func check():\n\tif bench[0] == null:\n\t\tpass\n",
        )
        self.assertEqual(
            lint_card_spawn.scan_file(f), [],
            "비교 (==)는 대입이 아님",
        )

    def test_comment_lines_not_flagged(self) -> None:
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "# CardInstance.create 예시\n## bench[0] = something 설명\n",
        )
        self.assertEqual(
            lint_card_spawn.scan_file(f), [],
            "주석 라인은 검사 제외",
        )

    def test_create_pattern_with_spaces(self) -> None:
        """`CardInstance . create (` 같은 변형도 잡아야 함."""
        f = _make_file(
            self.tmpdir,
            "godot/scripts/foo.gd",
            "func bad():\n\tvar c = CardInstance.create ('x')\n",
        )
        self.assertTrue(lint_card_spawn.scan_file(f), "공백 포함 패턴도 위반")


if __name__ == "__main__":
    unittest.main()
