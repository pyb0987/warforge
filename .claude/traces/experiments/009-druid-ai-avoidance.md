# Episode 009: Adaptive Druid avoidance diagnosis

date: 2026-06-02
verdict: positive

## Question

B-3 left one concrete follow-up: adaptive bought broad pools but never purchased
five Druid engine/payoff cards (`dr_deep`, `dr_origin`, `dr_resonance`,
`dr_spore_cloud`, `dr_world`). Is this a card-pool weakness or an AI scoring
blind spot?

## Diagnosis

Reproduced the previous coverage pattern with the existing 20x7 coverage dump:

```text
before evaluator card_coverage: 0.1896
before druid theme coverage:    0.1896
before adaptive Druid buys:     25
before adaptive Druid zeroes:   dr_origin, dr_deep, dr_spore_cloud, dr_world, dr_resonance
```

AI trace confirmed the root cause:

- `adaptive` committed to a dominant theme at R4 when only a small early lead existed.
- Once committed to Military, Druid engine/payoff offers received the full off-theme penalty.
- Representative skipped scores: `dr_origin -13`, `dr_deep -9`, `dr_spore_cloud -9`, while Military/Neutral alternatives stayed positive.

## Change

- `ai_helpers.detect_dominant_theme` now requires a clear lead before adaptive commits: at least 3 cards and a lead of 2 over the second theme.
- `ai_theme_scorer` now rewards Druid producer -> payoff follow-through and existing-Druid -> engine-producer follow-through.
- Existing `dr_world` unit-cap penalty remains dominant; if the cap penalty is active, Druid synergy bonuses are not added.

## Result

```text
after evaluator card_coverage: 0.2130
after druid theme coverage:    0.2468
after adaptive Druid buys:     60
after adaptive Druid zeroes:   dr_wt_root, dr_resonance
weighted_score delta:          +0.0155
weighted_score:                0.4614
```

The handoff completion target was met: adaptive Druid zero coverage dropped from
5 cards to 2 cards.

## Verification

```bash
godot --headless --path godot/ -s sim/dump_coverage.gd -- --out=/private/tmp/chain-army-coverage-before.json
python3 scripts/analyze_card_coverage.py /private/tmp/chain-army-coverage-before.json

godot --headless --path godot/ -s sim/dump_coverage.gd -- --out=/private/tmp/chain-army-coverage-after.json
python3 scripts/analyze_card_coverage.py /private/tmp/chain-army-coverage-after.json

godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_theme_scorer.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
python3 scripts/lint_card_spawn.py
```

PASS summary:

- `test_ai_theme_scorer.gd`: 11/11
- `test_ai_agent.gd`: 12/12
- Full GUT: 926/926 passing tests
- `scripts/lint_card_spawn.py`: PASS

Known unrelated warnings remain:

- Full GUT collection still ignores pre-existing parse-broken scripts:
  `test_combat_chain.gd`, `test_merge_system.gd`, `test_neutral_system.gd`.
- Batch sims emit pre-existing Military `r_conditional` target warnings for
  `self_all` / `self_and_adj_all`.
- Godot exits with the existing ObjectDB/resource leak warnings.

## Remaining Work

- `soft_druid` itself still went 0/20 in this measurement. This episode fixed
  adaptive's Druid recognition, not Druid strategy win-rate.
- Predator became the new min coverage theme (`0.2130`), so broad card coverage
  work should continue from S-1/S-2 rather than more Druid-only fixes.

## Follow-up: Druid Power Conversion

User manual-play memory matched the remaining sim evidence: Druid can collect
trees without converting them into enough early combat power.

Fresh 3-run trace (`/private/tmp/druid_trace_20260602`) showed:

```text
soft_druid WR:              0/3
avg rounds reached:         10.3
top buys:                   ne_earth_echo, ne_wild_pulse, dr_cradle, dr_lifebeat
run 1894552258 first Druid: R8
run 1894552259 R10 trees:   36, then R11/R12 losses
run 1894552260 first core:  dr_wt_root at R9, then R9/R10 losses
```

Cause split:

- AI side: `soft_druid` still has no preferred theme before R4, so early T1
  Druid offers can lose to stronger immediate-power Neutral/Military/Predator
  cards.
- Balance side: when Druid does assemble, early cards mostly bank trees. The
  strongest tree-to-power conversions (`dr_origin`, `dr_deep`, `dr_world`) are
  either low-rate, late, or delayed by forest-depth thresholds.

Next patch should preserve the "few units, elite growth" identity and move
power conversion earlier rather than adding generic unit spawns. Candidate axes:

- Give `soft_druid` R1 theme preference for cleaner Druid-strategy evaluation.
- Raise early `dr_origin`/`dr_deep` conversion or lower their tree thresholds.
- Revisit `dr_world` entry threshold only after isolating early-engine changes.

## Follow-up: Common Druid Tree Combat Bonus

Implemented the first shared tree-to-combat conversion as an explicit effect on
every Druid card level for UI visibility:

```text
BS: this card gets ATK/HP +(own trees x 2%), capped at +20%, this combat.
```

Implementation notes:

- `data/cards/druid.yaml` now carries `tree_combat_bonus` on all 33 Druid card
  level entries.
- `DruidSystem.apply_battle_start` applies existing BS Druid actions first, then
  the common temporary multiplier. This means `dr_lifebeat`'s BS tree gain counts
  immediately for its combat bonus.
- The bonus is temporary via `temp_mult_buff`; it clears after combat and does
  not permanently inflate tree engines.
- `card_desc_gen.py` emits the UI text as an ordinary BS line so every affected
  card shows the effect directly.
- Adding a BS effect to every Druid card exposed a transform-routing bug:
  transformed theme identities could send Druid cards to the wrong theme system.
  `ChainEngine` now routes theme-system implementations by the base card theme.

Verification:

```text
test_druid_system.gd: 50/50 passing
test_chain_engine.gd: 18/18 passing
Full GUT: 931/931 passing
Batch sim: weighted_score 0.4668, delta +0.0209
```

Result:

```text
soft_druid: 0/20 wins, avg_hp -11.7
adaptive:   11/20 wins, avg_hp 8.75
coverage:   0.2169, delta +0.0273
```

The implementation is mechanically healthy and improves the aggregate evaluator,
but `2% / 20%` is still too conservative to make `soft_druid` viable by itself.
Next Druid balance iteration should treat the common bonus rate/cap as tunables
and compare stronger variants against this baseline.

### Variant Check: 5% Per Tree, 20% Cap

Temporarily raised only `per_tree_pct` from `0.02` to `0.05`; cap stayed at
`0.20`.

```text
Batch sim: weighted_score 0.4655, delta +0.0196
soft_druid: 0/20 wins, avg_hp -10.55
adaptive:   11/20 wins, avg_hp 8.75
coverage:   0.2169, delta +0.0273
```

Compared with the 2% baseline above, 5% improved `soft_druid` average HP by
about +1.15 but did not produce wins, and aggregate weighted score dropped by
about -0.00135. Do not adopt this as-is; the next variant should likely change
both rate and cap, or combine a moderate rate bump with earlier Druid theme
commitment.

### Variant Check: 5% Per Tree, 50% Cap

Raised `per_tree_pct` to `0.05` and `cap_pct` to `0.50`.

```text
Batch sim: weighted_score 0.4780, delta +0.0321
soft_druid: 1/20 wins, avg_hp -11.8
adaptive:   11/20 wins, avg_hp 8.65
coverage:   0.2188, delta +0.0292
```

Compared with 2%/20%, this is the first tested common-bonus variant that gives
`soft_druid` a win and it improves aggregate weighted score by about +0.0112.
The average `soft_druid` HP did not improve, so the win may be seed-sensitive,
but the global evaluator signal is strong enough to keep 5%/50% as the current
candidate pending broader playtest or a larger sim.

### Nearby Variant Sweep and AI Awareness

Compared nearby common-bonus candidates with the same evaluator
(`runs=20`, `seed=42`, `best_genome.json`):

```text
2% / 20%: weighted 0.4668, soft_druid 0/20, avg_hp -11.7
4% / 50%: weighted 0.4772, soft_druid 1/20, avg_hp -9.6
5% / 50%: weighted 0.4780, soft_druid 1/20, avg_hp -11.8
5% / 60%: weighted 0.4836, soft_druid 2/20, avg_hp -10.8
6% / 50%: weighted 0.4792, soft_druid 1/20, avg_hp -11.0
```

The local winner was `5% / 60%`: raising the cap helped more than raising the
per-tree rate past 5%.

User hypothesis: the AI may not be aware of the new tree combat conversion.
Code inspection confirmed a partial blind spot:

- AI valued trees via `tree_value_per`, but did not read `tree_combat_bonus`
  rate/cap.
- Board promotion used raw build-phase ATK/HP, not the expected Druid BS tree
  combat multiplier.

Added AI awareness as a separate candidate: Druid card value now reads
`tree_combat_bonus`, and board promotion applies the expected Druid tree combat
multiplier to its heuristic size.

```text
5% / 60% + awareness:
weighted 0.4846, soft_druid 2/20, avg_hp -10.35
coverage 0.2195
```

Adopt `5% / 60% + awareness` as the current candidate. It improved weighted
score over pure `5% / 60%` and made `soft_druid` average HP less negative,
though Druid still remains below target viability and needs broader samples or
additional early-game support.

### Larger Sample and R1 Commit Check

Ran a larger sample for the current candidate (`5% / 60% + awareness`) using
`runs=40`, `seed=42`:

```text
weighted 0.4710
soft_druid 5/40 wins, avg_hp -6.075
coverage 0.2195
```

The larger sample kept the `soft_druid` win-rate signal roughly aligned with the
20-run result (2/20 -> 5/40) and made average HP look less fragile.

Then tested a `soft_druid` R1 theme-commit policy while leaving other soft
themes unchanged:

```text
weighted 0.4561
soft_druid 4/40 wins, avg_hp -3.4
coverage 0.2107
```

Verdict: reject R1 commit for now. It improved `soft_druid` average HP but
reduced wins, card coverage, per-round WR match, and aggregate weighted score.
The likely issue is that early forced Druid buying narrows the opening too much;
the current R1-R3 open buying policy remains the better baseline for playtest.
