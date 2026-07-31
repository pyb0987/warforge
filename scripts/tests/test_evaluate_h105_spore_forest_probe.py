import importlib.util
import pathlib
import unittest


MODULE_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "evaluate_h105_spore_forest_probe.py"
)
SPEC = importlib.util.spec_from_file_location("evaluate_h105", MODULE_PATH)
evaluate_h105 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluate_h105)


class EvaluateH105SporeForestProbeTest(unittest.TestCase):
    def test_nominates_only_when_all_h105_gates_move_together(self):
        baseline = _runs(
            run_wins=9,
            combat_wins=20,
            final_hp=-4.5,
            debuff=0.15,
            ally_loss=0,
            enemy_loss=14,
            trees=20,
        )
        candidate = _runs(
            run_wins=14,
            combat_wins=30,
            final_hp=-3.0,
            debuff=0.25,
            ally_loss=1,
            enemy_loss=10,
            trees=20,
        )

        result = evaluate_h105.evaluate_h105(candidate, baseline)

        self.assertEqual(
            result["verdict"],
            evaluate_h105.VERDICT_NOMINATE,
        )
        self.assertFalse(result["failed_gates"])
        self.assertGreaterEqual(result["comparison"]["candidate"]["wins"], 14)
        self.assertLess(result["spore_cap_rate"]["cap_rate"], 0.5)

    def test_rejects_local_debuff_movement_without_run_outcome(self):
        baseline = _runs(
            run_wins=9,
            combat_wins=20,
            final_hp=-4.5,
            debuff=0.15,
            ally_loss=0,
            enemy_loss=14,
            trees=20,
        )
        candidate = _runs(
            run_wins=9,
            combat_wins=30,
            final_hp=-4.4,
            debuff=0.25,
            ally_loss=1,
            enemy_loss=10,
            trees=20,
        )

        result = evaluate_h105.evaluate_h105(candidate, baseline)

        self.assertEqual(result["verdict"], evaluate_h105.VERDICT_REJECT)
        self.assertIn("clears_materially_improve", result["failed_gates"])
        self.assertIn("avg_final_hp_improves", result["failed_gates"])
        self.assertNotIn("debuff_too_small_decreases", result["failed_gates"])

    def test_rejects_cap_heavy_candidate(self):
        baseline = _runs(
            run_wins=9,
            combat_wins=20,
            final_hp=-4.5,
            debuff=0.15,
            ally_loss=0,
            enemy_loss=14,
            trees=20,
        )
        candidate = _runs(
            run_wins=14,
            combat_wins=30,
            final_hp=-3.0,
            debuff=0.50,
            ally_loss=1,
            enemy_loss=10,
            trees=20,
        )

        result = evaluate_h105.evaluate_h105(candidate, baseline)

        self.assertEqual(result["verdict"], evaluate_h105.VERDICT_WEAK)
        self.assertIn("not_cap_heavy", result["failed_gates"])


def _runs(run_wins, combat_wins, final_hp, debuff, ally_loss, enemy_loss, trees):
    runs = []
    for idx in range(60):
        run_won = idx < run_wins
        combat_won = idx < combat_wins
        enemy_survived = 0 if combat_won else enemy_loss
        ally_survived = 6 if combat_won else ally_loss
        run_final_hp = 12 if run_won else final_hp
        runs.append([
            {
                "t": "round_end",
                "round": 10,
                "board": [
                    "dr_spore_cloud",
                    "dr_cradle",
                    "dr_lifebeat",
                ],
                "active_board": [
                    "dr_spore_cloud",
                    "dr_cradle",
                    "dr_lifebeat",
                ],
                "detected_path": "druid_garden",
                "states": {
                    "dr_spore_cloud": {"star": 1, "trees": 0},
                    "dr_cradle": {"star": 1, "trees": trees},
                    "dr_lifebeat": {"star": 1, "trees": 0},
                },
            },
            {
                "t": "battle",
                "round": 10,
                "won": combat_won,
                "ally_survived": ally_survived,
                "enemy_survived": enemy_survived,
                "enemy_debuffs": {"atk_pct": 0.0, "as_pct": debuff},
            },
            {
                "t": "run_end",
                "rounds_played": 15 if run_won else 10,
                "final_hp": run_final_hp,
                "won": run_won,
            },
        ])
    return runs


if __name__ == "__main__":
    unittest.main()
