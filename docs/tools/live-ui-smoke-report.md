# Live UI Smoke Report

The live UI smoke report runs a short scripted live scene and writes a JSON
artifact describing modal ownership, visible choices, and actionability.

Use it when you want a repeatable answer to "what does the live UI show?" without
running a broad autoplay harness.

## Command

```bash
godot --headless --log-file /private/tmp/warforge_live_ui_smoke.log \
  --path godot/ \
  res://tools/live_ui_smoke_report.tscn -- \
  --out=/private/tmp/warforge_live_ui_smoke.json \
  --commander=gambler \
  --talisman=flint \
  --unlock-selected=true
```

The console still includes normal game logs. Use `--out` for parseable JSON.

## Screenshot Artifacts

Screenshots are optional visual evidence. They require a rendering display, so
run without `--headless` when using `--screenshot-dir`:

```bash
godot --log-file /private/tmp/warforge_live_ui_smoke_gui.log \
  --path godot/ \
  res://tools/live_ui_smoke_report.tscn -- \
  --out=/private/tmp/warforge_live_ui_smoke_gui.json \
  --screenshot-dir=/private/tmp/warforge_live_ui_smoke_shots \
  --commander=gambler \
  --talisman=flint
```

When `--screenshot-dir` is used under `--headless`, the report records
`screenshot_status: "unsupported"` and exits nonzero. The semantic JSON smoke
path remains valid without screenshots.

After a GUI screenshot run, validate the report-bound PNG artifacts:

```bash
python3 scripts/lint_live_ui_screenshots.py \
  --report=/private/tmp/warforge_live_ui_smoke_gui.json
```

The lint expects the current fixed smoke viewport of `1280x720`. It validates
the ordered report labels, nested screenshot bindings, PNG dimensions, nonblank
image data, the growth-chain pause, compact last-chain BUILD panel contract,
post-settlement BUILD recap, live battle-start status, boss reward rendered-choice
summaries, and the known target-selection overlay rect constraints exported in
the JSON report.
Keep it out of default headless GUT unless CI provides a display.

## Playtest Summary

Generate a compact human-readable summary from any live UI smoke report:

```bash
python3 scripts/summarize_live_ui_report.py \
  --report=/private/tmp/warforge_live_ui_smoke.json \
  --out=/private/tmp/warforge_live_ui_smoke_summary.md
```

For GUI screenshot reports, bind the summary to fresh screenshot lint by adding
`--lint-screenshots`:

```bash
python3 scripts/summarize_live_ui_report.py \
  --report=/private/tmp/warforge_live_ui_smoke_gui.json \
  --lint-screenshots \
  --out=/private/tmp/warforge_live_ui_smoke_gui_summary.md
```

The summary recomputes its claims from the JSON report. It exits nonzero when
the source report is incomplete, the ordered smoke labels are missing, the final
state is not clean BUILD, required reward/chain event fields are absent, or
requested screenshot lint fails.

## Identity Matrix

Run the curated identity matrix when you want one command to prove that the
same live UI smoke contract works across important commander/talisman profiles:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --output-dir=/private/tmp/warforge_live_ui_identity_matrix
```

The default matrix covers:

- `baseline=gambler:flint`
- `coin=gambler:two_faced_coin`
- `golden_die=gambler:golden_die`
- `locked_economy=alchemist:soul_jar`

Use the expanded special-commander preset when you want the reusable H83/H84
coverage set:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --preset=expanded \
  --output-dir=/private/tmp/warforge_live_ui_identity_matrix_expanded
```

The expanded preset covers:

- `breeder=breeder:cracked_egg`
- `collector=collector:glass_eye`
- `strategist=strategist:war_drum`
- `smith=smith:rusty_wrench`
- `raider=raider:mercury_drop`

Each row writes its own `report.json`, `summary.md`, Godot log, and isolated
Godot `HOME` profile under the output directory. The matrix fails when any live
UI report exits nonzero, does not write a JSON report, or fails the
`summarize_live_ui_report.py` contract.

Replace the preset with explicit custom rows by using repeated `--identity`
options:

```bash
python3 scripts/run_live_ui_identity_matrix.py \
  --identity=baseline=gambler:flint \
  --identity=reward=gambler:golden_die \
  --output-dir=/private/tmp/warforge_live_ui_identity_matrix_custom
```

## Covered Flow

The report currently covers:

- run-start screen ownership and actionable start button;
- commander selection ownership, selected commander visibility, and rendered
  commander choice-card summaries from the modal UI;
- talisman selection ownership, selected talisman visibility, and rendered
  talisman choice-card summaries from the modal UI;
- modal-free R1 BUILD entry;
- visible run milestone text in the BUILD HUD, showing the next boss reward or
  final boss target;
- a visible BUILD readiness cue with current FIELD/BENCH participation and a
  non-exact enemy pressure preview plus next action before `BUILD COMPLETE`;
- rendered commander/talisman identity and live effect status in the BUILD HUD,
  including Flint changing from ready at build entry, to used during the scripted
  growth chain, then back to ready on the next BUILD round;
- a compact R1-R15 run progression rail in the BUILD HUD, showing the current
  round plus R4/R8/R12 boss reward and R15 final boss status;
- card-shop and upgrade-shop reroll scope evidence: R changes card offers while
  preserving upgrade offers, and T changes upgrade offers while preserving card
  offers;
- optional commander free-upgrade ownership when a selected commander opens it
  during the scripted path, such as Smith's start bonus, through the visible
  upgrade-choice modal and target overlay before the smoke resumes;
- for Raider identities, a focused real 3-win reward proof that selects the
  visible common-upgrade choice, attaches it through the field target overlay,
  resets Raider's win counter, and returns to BUILD;
- a real growth-chain pause with visible trigger/event feedback;
- a real battle-start frame with rendered round, actual starting ally/enemy
  counts, and current remaining ally/enemy counts;
- a battle aftermath popup with survivor count, HP delta, gold delta, and next
  step;
- the following BUILD screen with visible last-chain history and `LAST
  SETTLEMENT` recap panels;
- forced third-copy shop purchase that opens the merge reward popup;
- merge reward choice visibility, selection, cleanup, exact upgrade attach,
  visible recent-merge history, and ★1→★2 gold math with no Gambler refund;
- R4 boss reward ownership, rendered reward-card names/types/descriptions,
  no-target reward selection, cleanup, and settlement into R5 BUILD;
- deterministic targeted R4 boss reward (`r4_1`) through rendered
  target-dependent reward-card text, visible field-target eligibility, target
  selection, effect application, cleanup, and settlement into R5 BUILD;
- a deterministic terminal victory through the real `GameManager` run-finish
  path with more than three live unlocks, proving the game-over popup shows the
  3-item unlock recap plus overflow copy;
- a fresh next-run load from the same saved meta profile, with recent unlocks,
  PROGRESS details, and visible commander/talisman choices proving overflow
  unlocks are immediately available.

## JSON Shape

Top-level fields:

- `schema`: currently `warforge-live-ui-smoke/v1`;
- `ok`: `true` only when the scripted path and assertions pass;
- `metadata`: selected commander, talisman, meta profile, and whether the
  selected locked identity was preunlocked for an isolated report profile;
- `steps`: ordered UI snapshots with phase, round, active modals, choices, and
  actionability, `layout_rects` for key live controls, plus a `screenshot`
  record when screenshot capture is enabled;
- `events`: compact shop-reroll, merge reward, and boss reward results,
  including rendered boss reward choice summaries and the selected summary;
- `events.run_selection`: rendered commander/talisman role-context text,
  choice-card summaries, and the selected summaries captured before the first
  BUILD entry;
- `events.run_identity`: rendered BUILD HUD text, visibility, and rect evidence
  for the selected commander/talisman pair at run entry and after chain
  feedback;
- `events.run_milestone`: rendered BUILD HUD round/milestone text, visibility,
  compact R1-R15 progression rail text, and rect evidence at run entry, after
  the first settlement, and post-unlock BUILD entry;
- `events.build_readiness`: rendered first-BUILD readiness text, visibility, and
  rect evidence for the initial and post-unlock BUILD entries;
- `events.enemy_pressure_preview`: rendered first-BUILD enemy pressure text,
  visibility, rect, and non-exact range data for the initial and post-unlock
  BUILD entries;
- `events.battle_status`: rendered battle-start HUD text, visibility, rect, and
  structured round/start/current ally/enemy count data from the real BATTLE
  screen before synthetic aftermath is injected;
- `events.shop_role_cues`: rendered first-shop card offer role text bound to
  visible card faces on the initial and post-unlock BUILD entries;
- `events.shop_reroll_scope`: card-reroll and upgrade-reroll before/after offer
  IDs plus the visible labels that distinguish `R:cards` from `T:upgrades only`;
- `events.commander_free_upgrade`: optional selected upgrade, target, and
  instruction evidence when a commander free-upgrade modal appears during the
  smoke path;
- `events.raider_win_streak_reward`: Raider-only proof that the real 3-win
  reward attached an upgrade through visible UI, reset the win counter, and
  returned to modal-free BUILD;
- `events.commander_scripted_adjustments`: explicit harness-only state
  adjustments, currently used to prevent Raider's artificial terminal victory
  from waiting on the 3-win reward cadence while preserving the terminal unlock
  smoke contract;
- `events.settlement_recap`: the post-battle BUILD recap text and raw settlement
  source fields such as base income, interest, gold totals, and Terazin totals;
- `events.unlock_recap`: the rendered game-over title/summary, shown unlock
  rows, overflow count, and raw unlock count computed from the visible recap;
- `events.post_unlock_progress`: the next-run recent unlock text, unlocked-list
  text, difficulty label, and visible PROGRESS details from a freshly loaded
  profile;
- `events.post_unlock_availability`: the visible commander/talisman choice ids
  after the unlock burst and the overflow commander/talisman selected into the
  next BUILD;
- `screenshots`: ordered PNG artifacts with label, absolute path, width, and
  height;
- `errors`: failure messages when `ok` is false;
- `final`: final UI snapshot.

Key invariant examples:

- only one expected modal owns the UI before a selection;
- commander/talisman selection modals expose rendered role/context text plus
  choice-card name, description, joined text, visible order, and nonzero visible
  rects before selection;
- visible choice lists are non-empty before reward selection;
- reward selection returns to modal-free BUILD;
- the BUILD readiness cue is visible on clean BUILD entry, includes FIELD,
  BENCH, chain/combat participation, ENEMY pressure, and a next action, and
  does not overlap the BUILD complete button or field cards;
- enemy pressure preview is visible before `BUILD COMPLETE`, includes round,
  enemy count, ATK and HP pressure ranges, and is marked non-exact so it cannot
  imply a locked battle roll;
- every non-empty first-shop card offer exposes a compact visible role cue
  derived from rendered card-face text, bound to the same slot and card id as the
  offer;
- card-shop reroll preserves upgrade offers, and upgrade-shop reroll preserves
  card offers;
- the selected commander and talisman names are visible in the BUILD HUD, the
  effect text avoids `C:`/`T:` shorthand, and Flint reports ready before its
  first growth, used during the chain pause, and ready again next round;
- the BUILD HUD names the next boss reward/final boss milestone, and the
  post-settlement recap carries the same next milestone so the next BUILD has a
  visible reason to continue;
- the run progression rail includes the current round and all major run
  milestones: R4 reward, R8 reward, R12 reward, and R15 final;
- battle-start status is visible on the real BATTLE screen, includes the current
  round, actual generated starting ally/enemy counts, current remaining counts,
  and nonzero visible rect evidence;
- battle result aftermath text includes HP change, Gold change, and a next-step
  hint;
- stale chain feedback is not visible after returning to BUILD;
- chain feedback trigger text does not overlap the top HP/Gold/Terazin HUD;
- last-chain history is visible after the scripted growth chain, uses compact
  display text for recent trigger rows, and keeps the full raw history in JSON;
- last-chain history has enough vertical room for the compact rows and does not
  overlap the BUILD complete button or field card area;
- settlement recap is visible after the scripted battle settlement, includes
  Gold income/interest and Terazin deltas, hides the tutorial panel in the same
  lane, and does not overlap last-chain, field, or BUILD complete controls;
- boss reward choice cards expose rendered name, type, description, target flag,
  and nonzero visible rects before selection;
- targeted boss reward choice cards expose exactly one target-dependent summary
  before opening target selection;
- stale battle status text is hidden after returning from the scripted battle;
- the selected merge reward upgrade is attached to the merged survivor, and the
  recent-merge panel exposes the merge instead of relying on a transient label;
- targeted reward eligibility exposes only valid field targets before selection;
- the selected targeted reward evolves the chosen card and grants its Terazin;
- game-over unlock recap is owned by the `game_over` modal and includes `New
  unlocks available`, three shown unlock rows, and `+N more unlocked - all
  available in PROGRESS`;
- next-run PROGRESS details are visible and mark overflow rewards such as
  Alchemist and Soul Jar as unlocked;
- overflow commander/talisman choices are selectable and reach a modal-free next
  BUILD, with rendered selection context/summaries matching the final BUILD
  identity.

## Useful Options

- `--out=/path/report.json`: write the parseable JSON artifact.
- `--screenshot-dir=/path/screenshots`: write PNGs for the ordered semantic
  snapshots. Requires a non-headless rendering display.
- `--commander=gambler|breeder|smith|strategist|collector|raider|alchemist`
- `--talisman=flint|two_faced_coin|cracked_skull|...`
- `--unlock-selected=true`: with the default reset profile, preunlock only the
  requested commander/talisman when they are otherwise locked, then exercise the
  normal visible selection UI. Use this for locked identity checks such as
  `--talisman=golden_die`.
- `--meta-path=user://some_profile.cfg`: use an isolated meta profile.
- `--reset-meta=false`: preserve the chosen meta profile instead of resetting.
  The default smoke now requires `reset-meta=true`; disabling reset intentionally
  marks the report incomplete because the unlock-recap evidence must not pass
  from stale saved progress.
