# Episode 018: Steampunk branch discipline probe

## Context

H20 added Steampunk loss buckets. H21-A showed that raw tier access is the wrong
first fix: it reached Lv4/Lv5 but regressed survival by spending too much
deck-building economy.

## Branch-mix Diagnosis

Baseline H20 trace: `/private/tmp/warforge_h20_current_140_traces`

```text
soft_steampunk: 5/20 wins, avg HP 2.15
losses: 15/20
branch_mix bucket: 10/15 losses
final mixed starters: 14/20 runs
final active mixed starters: 10/20 runs
anti-branch buys after path detection: 44
```

Observed examples show many post-detection anti-branch buys still winning the
shop choice with `build_path: -36.0` because other terms often add:

```text
theme +23, chain ~+8, merge up to +30, tier +2, timing +3 to +8
```

This means the current Steampunk anti penalty acts as a mild nudge once merge
pressure appears, even though the design document describes branch mixing as a
real opportunity cost in limited board slots.

## Candidate H22 Probe

Increase the Steampunk-only `anti_penalty` in `AIBuildPath` from `36.0` to a
stronger soft lock. Candidate sizes under review: `60.0` or `72.0`.

Intended shape:

- No card YAML changes.
- No level/economy/genome changes.
- No path-detection changes.
- Keep it Steampunk-local through existing `anti_penalty` fields.

Gate:

- Focused AI/path tests.
- Same-seed 140-run observer against H20 baseline.
- New Steampunk buckets must show lower branch mixing and post-detection
  anti-branch buying without the H21 purchase/reroll collapse.

## Pending Multi-review

Three read-only critics are reviewing:

- Evidence critic: whether branch mix is the right causal target and what
  penalty size is appropriate.
- Design critic: whether a stronger branch lock improves player-facing
  archetype clarity without over-railroading.
- Systems critic: implementation risk, test shape, and adoption gate.

## Multi-review Result

The critics agreed this was a reasonable causality probe, not a guaranteed final
balance fix.

- Design critic preferred `60.0` first to preserve softer hybrid exploration.
- Evidence and systems critics preferred `72.0` for an additive probe because
  the observed positive score offsets can beat `60.0`.
- All critics warned not to accept a modifier-only or branch-mix-only green; the
  observer must show outcome/payoff improvement.

## H22-A: Anti Penalty 72

Patch:

```gdscript
"anti_penalty": 72.0
```

Applied only to the two Steampunk paths in `AIBuildPath`.

Focused tests:

```text
PASS test_ai_build_path.gd 36/36
PASS test_ai_agent.gd 39/39
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Same-seed observer:

```bash
godot --headless --log-file /private/tmp/warforge_h22_steampunk_branch72_140.log --path godot/ -s tools/self_play_observer.gd -- --runs=20 --strategies=all --difficulty=1 --commander=gambler --talisman=two_faced_coin --seed=2026072620 --out=/private/tmp/warforge_h22_steampunk_branch72_140.json --trace-dir=/private/tmp/warforge_h22_steampunk_branch72_140_traces --quiet-progress=true
```

Result:

```text
overall: 64/140 wins, avg HP 7.74 (baseline 64/140, avg HP 7.84)
soft_steampunk: 5/20 wins, avg HP 1.5 (baseline 5/20, avg HP 2.15)
post-detection anti-branch buys: 44 -> 0
final branch_mix runs: 14/20 -> 0/20
branch_mix loss bucket: 10/15 -> 0/15
payoff_acquisition_lag: 14/15 -> 15/15
loss payoff funnel: 1/1/1 -> 3/1/0
```

Decision:

- Reject and revert. H22-A cleanly removed branch pollution, but it did not
  improve outcomes and made payoff acquisition slightly worse. Branch mixing was
  therefore a symptom or secondary problem, not the next root fix.
- Post-revert focused checks:

```text
PASS test_ai_build_path.gd 36/36
PASS test_ai_agent.gd 37/37
PASS scripts.tests.test_analyze_ai_trace 10/10
```

Next:

- Target Steampunk payoff acquisition directly. The baseline and H22-A both
  show that payoffs are almost never bought before losses; changing branch
  discipline alone is insufficient.
