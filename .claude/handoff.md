# Handoff — 재착수 상태 (2026-05-30)

## 2026-07-30 Codex H96 update

- H96 completed as an unprotected live-scout/tooling clarity slice.
- Purpose: resume from H95 with a bounded manual/live playability scout without
  touching protected simulator files.
- Initial scout:
  - PASS default live UI identity matrix 4/4 at
    `/private/tmp/warforge_h96_live_matrix_default`.
  - PASS expanded live UI identity matrix 5/5 at
    `/private/tmp/warforge_h96_live_matrix_expanded`.
- Scout read:
  - identity, Two-Faced Coin pricing, merge economy/history, card-reroll vs
    upgrade-reroll scope, boss rewards, target overlays, and post-unlock
    availability all remained green in the summaries.
  - unlock recap overflow looked large (10-12 raw unlocks, 3 shown), but code
    inspection proved this is the live report's synthetic
    `_overflow_unlock_run_stats()` fixture, not natural progression evidence.
- Change:
  - `godot/tools/live_ui_smoke_report.gd` now records
    `events.unlock_recap.run_stats_source =
    "synthetic_overflow_fixture"` plus a note and stats payload.
  - `scripts/summarize_live_ui_report.py` now requires that marker and prints it
    in the summary line.
  - `scripts/tests/test_summarize_live_ui_report.py` covers the rendered marker
    and missing-marker failure.
  - `docs/tools/live-ui-smoke-report.md` warns not to use the overflow fixture
    for natural meta-progression pacing conclusions.
- Verification:
  - PASS Python summary/matrix tests 46/46.
  - PASS fresh live UI report and summary marker:
    `/private/tmp/warforge_h96_marker_live_summary.md`.
  - PASS fresh default matrix 4/4:
    `/private/tmp/warforge_h96_marker_matrix_default`.
  - PASS fresh expanded matrix 5/5:
    `/private/tmp/warforge_h96_marker_matrix_expanded`.
  - PASS `test_game_manager_live_smoke.gd` 18/18, 1324 asserts.
  - PASS full GUT 1282/1282, 9274 asserts.
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, economy values, or progression thresholds
  changed for H96.
- Latest trace:
  `.claude/traces/experiments/092-live-ui-unlock-fixture-marker.md`.
- Resume recommendation: H78 remains the direct M1 strategy-viability blocker
  and still needs explicit protected simulator approval. If staying unprotected,
  use natural run/self-play artifacts for unlock pacing, not the live report's
  synthetic overflow fixture.

## 2026-07-30 Codex H95 update

- H95 completed as an unprotected completion-readiness contract.
- Purpose: pause the current autonomous run with a concrete resume target
  rather than starting another gameplay slice.
- Updated `Plans.md` with a working M1-M4 milestone ladder and M1 evidence
  gates:
  - core live run flow;
  - replay/meta clarity;
  - reward/economy integrity;
  - strategy viability floor;
  - verification hygiene.
- Important non-claim: H95 does not mark Warforge complete. It defines the
  evidence needed before M1 "completion-ready prototype" can be called done.
- Advisory review note:
  - verification/scope critic supported H95 only as a contract/readiness
    artifact;
  - false-green risk was medium-high if H94 were converted into "gameplay
    fixed" or "prototype complete";
  - frame-challenge critic warned that the next slice should not be another
    planning artifact; the honest next step is explicit H78 protected-edit
    approval, or a bounded unprotected live/manual scout if approval is not
    available;
  - product-completion critic flagged the false-green risk of marking H95 DONE
    if the referenced trace were missing; the durable H95 trace now exists at
    `.claude/traces/experiments/091-completion-readiness-gates.md`;
  - the resulting plan now says prose is only a routing aid, and acceptance must
    come from recomputable artifacts such as self-play JSON, observer summaries,
    trace analyzers, focused/live GUT output, card-spawn guards, whitespace
    guards, and protected-boundary checks.
- Current M1 blocker remains H78:
  - soft-Druid refreshed at 9/60 clears in H94;
  - completion readiness still `needs_attention`;
  - path-lag audit still reports `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`;
  - editing `godot/sim/ai_agent.gd` still requires explicit approval.
- Verification:
  - PASS doc sanity query for H95/gates/H78 blocker language.
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, economy values, or UI code changed for H95.
- Latest trace:
  `.claude/traces/experiments/091-completion-readiness-gates.md`.
- Resume recommendation: start from H95's gates. If continuing the highest
  impact known blocker, ask explicit approval before H78 protected simulator
  work; otherwise choose another unprotected M1 gate gap and keep it scoped.

## 2026-07-30 Codex H94 update

- H94 completed as a no-edit H78 readiness/baseline refresh.
- Purpose: advance the highest-impact known gameplay-completion target
  (Druid strategy-floor viability) without crossing the protected
  `godot/sim/**` edit boundary before explicit approval.
- Current worktree was clean at start, and H93 is pushed at `7cd9d46`.
- Re-read H78 packet:
  `.claude/traces/experiments/074-druid-protected-ai-probe-approval-packet.md`.
- Confirmed the old H71/H75 comparison trace directories still exist under
  `/private/tmp`.
- Verification/evidence:
  - PASS `test_ai_agent.gd` (39/39, 94 asserts).
  - PASS H78 packet pre-probe analyzer on existing H75 vs H71 traces:
    H75 showed `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`, 265 R8-R12
    holds, 260 no-focus holds, and only 1 affordable-focus hold.
  - PASS fresh no-edit current soft-Druid baseline:
    `/private/tmp/warforge_h94_druid60.json`.
  - PASS fresh summary:
    `/private/tmp/warforge_h94_druid60_summary.md` reports 9/60 clears,
    15.0% clear rate, avg final HP -4.23, avg rounds 11.07, and completion
    readiness `needs_attention`.
  - PASS fresh Druid analyzer on
    `/private/tmp/warforge_h94_druid60_traces`:
    255 R8-R12 path-lag holds, 251 no-focus holds (98.4%), 1 affordable-focus
    hold, 37 actionable no-focus loss runs, and
    `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.
  - The fresh baseline exactly matches H71 on the same-seed comparison screen:
    9/60 clears, avg final HP -4.23, 81 R9-R11 focus-active frames, 34.6% WR,
    and no path-lag deltas. The analyzer labels this `REJECT_FLAT_OR_NOISY`
    only because the current no-edit baseline is intentionally unchanged.
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, economy values, or UI code changed for H94.
- Latest trace:
  `.claude/traces/experiments/090-h78-no-edit-druid-preflight.md`.
- Resume recommendation: H78 remains the strongest next gameplay-completion
  candidate. Ask explicit approval to edit protected `godot/sim/ai_agent.gd`
  and focused `godot/tests/test_ai_agent.gd` before implementing the narrow
  no-focus stabilizer policy probe.

## 2026-07-30 Codex H93 update

- H93 completed as an unprotected distinctive-commander live-control coverage
  slice.
- Advisory multi-review summary:
  - player-completion and frame-challenge critics preferred H78 Druid
    path-lag work as the higher-impact gameplay-completion target;
  - scope/verification critic vetoed protected `godot/sim/**` edits without
    explicit approval and recommended a narrow unprotected Strategist live
    control slice if continuing autonomously;
  - decision: keep H78 gated on explicit protected simulator approval, and
    complete H93 as the best unprotected progress slice.
- Added Strategist/War Drum visible-control terminal acceptance coverage.
- The smoke profile explicitly unlocks Strategist and War Drum, selects both
  through the normal run-start popups, then proves Strategist's SWAP through
  live controls:
  - the visible SWAP button enters pick-first mode;
  - two visible field-card clicks select the swap targets;
  - the two board card references exchange slots;
  - `hero_used` becomes true;
  - the button and identity HUD show SWAP used;
  - the run continues through real chains, battles, boss rewards, and reaches
    the real terminal overlay.
- Scope note: War Drum is selected and visible in the identity HUD. The run log
  naturally showed War Drum activations, but H93 does not claim dedicated War
  Drum damage/debuff proof because that remains covered by `test_talisman.gd`.
- Verification:
  - PASS `test_game_manager_live_smoke.gd` (18/18, 1327 asserts).
  - PASS `test_build_phase_strategist_swap.gd` (6/6, 23 asserts).
  - PASS `test_talisman.gd` (38/38, 108 asserts).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS full GUT in isolated Godot profile (57 scripts, 1282/1282 tests,
    9271 asserts).
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed the same macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, or economy values changed for H93.
- Latest trace:
  `.claude/traces/experiments/089-strategist-visible-swap-coverage.md`.
- Resume recommendation: checkpoint H91-H93 soon. After that, ask explicit
  approval before attempting H78 protected Druid simulator work.

## 2026-07-30 Codex H92 update

- H92 completed as an unprotected Raider reward-flow coverage slice.
- Added Raider/Flint visible-control terminal acceptance coverage for the real
  3-win reward flow after carrying Raider's local `win_count` at 2.
- The smoke profile explicitly unlocks Raider, selects Raider through the
  normal commander popup, selects Flint through the normal talisman popup, then
  plays through real build and battle surfaces.
- The playthrough proves the Raider reward is resolved through visible controls:
  - the test carries only Raider's existing local win counter;
  - the next real win opens the free common-upgrade flow;
  - the test resolves the visible target overlay;
  - the attached-upgrade count increases while pending source is
    `raider_win_streak`;
  - the run continues through real battles and reaches the real terminal
    overlay.
- Scope note: this does not prove the automated visible-control player can
  naturally generate three Raider wins from zero. Earlier H92 attempts with
  Raider/Flint and Raider/War Drum reached terminal states without producing
  that full natural 3-win cadence. This slice deliberately covers the reward
  plumbing without changing balance or forcing battle outcomes.
- Verification:
  - PASS `test_game_manager_live_smoke.gd` (17/17, 1219 asserts).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS full GUT in isolated Godot profile (57 scripts, 1281/1281 tests,
    9169 asserts).
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed the same macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, or economy values changed for H92.
- Latest trace:
  `.claude/traces/experiments/088-raider-carried-win-count-coverage.md`.
- Resume recommendation: pause here per user request. When work resumes, use
  H92 as a boundary: the next slice should either improve fully natural
  Raider-from-zero coverage, continue another distinctive commander/talisman
  live path, or ask explicit approval before returning to protected H78
  simulator work.

## 2026-07-30 Codex H91 update

- H91 completed as an unprotected special-identity natural-run coverage slice.
- Added Smith/Flint natural visible-control terminal acceptance coverage.
- The smoke profile explicitly unlocks Smith for the test, then selects Smith
  through the normal commander popup and Flint through the normal talisman
  popup.
- The playthrough now proves Smith's start free-upgrade flow is resolved through
  visible controls:
  - first BUILD COMPLETE opens the common-upgrade flow;
  - the test resolves the visible target overlay;
  - the attached-upgrade count increases while pending source is `smith_start`;
  - the run continues through real battles and reaches the real terminal
    overlay.
- Verification:
  - PASS `test_game_manager_live_smoke.gd` (16/16, 1131 asserts).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS full GUT in isolated Godot profile (57 scripts, 1280/1280 tests,
    9081 asserts).
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed the same macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, or economy values changed for H91.
- Latest trace:
  `.claude/traces/experiments/087-smith-natural-run-start-upgrade-coverage.md`.
- Resume recommendation: this is a good small follow-up on the H90 coverage
  path. Next unprotected candidates are natural coverage for Raider's 3-win
  reward in a terminal playthrough, or another locked commander with distinctive
  setup rules. H78 remains gated on explicit protected simulator approval.

## 2026-07-30 Codex H90 update

- H90 completed as an unprotected natural-run coverage slice.
- The visible-control terminal playthrough helper is now parameterized by
  commander/talisman identity while keeping the existing Gambler/Flint default.
- Added Breeder/Flint as the second natural visible-control terminal acceptance
  case. This covers both initially unlocked commanders without scripted wins,
  forced battle outcomes, seeded run stats, or generated unlock injection.
- Both Gambler/Flint and Breeder/Flint naturally reached defeat at R8 through
  visible shop buys, bench-to-field moves, upgrade targeting, BUILD COMPLETE,
  chain skip, real battles, boss reward resolution, and terminal overlay.
- Verification:
  - PASS `test_game_manager_live_smoke.gd` (15/15, 1043 asserts).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS full GUT in isolated Godot profile (57 scripts, 1279/1279 tests,
    8990 asserts).
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed the same macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, or economy values changed for H90.
- Latest trace:
  `.claude/traces/experiments/086-initial-commander-natural-run-coverage.md`.
- Resume recommendation: checkpoint/commit the current H79-H90 stack soon.
  The next completion slice should either continue natural-run identity coverage
  after explicit unlock setup or ask explicit approval for H78 protected Druid
  simulator work.

## 2026-07-30 Codex H89 update

- H89 completed as an unprotected post-defeat orientation slice.
- Multi-review decision:
  - player-completion, scope-boundary, and verification critics favored
    player-facing work from the current visible-control R8 defeat evidence;
  - the review-quality critic scored the initial frame 6/10 and required the
    decision to be tied to the actual completion blocker, not green tests;
  - revised frame: the next slice reduces the current player learning gap after
    natural defeat, while H78 remains protected and deferred.
- `GameOverPopup` now adds a defeat-only `Next run:` cue after the run-bests
  line. The cue uses final-battle survivor context when available, falling back
  to upgrade/milestone context when not.
- Victory terminal screens intentionally omit the next-run hint.
- The visible-control live playthrough still naturally reaches defeat at R8,
  and now asserts the terminal overlay contains a next-run cue.
- Verification:
  - PASS `test_game_over_popup.gd` (4/4, 24 asserts).
  - PASS `test_game_manager_live_smoke.gd` (14/14, 957 asserts).
  - PASS headless live UI report + summary:
    `/private/tmp/warforge_h89_live_ui_report_summary.md` reports
    `Verdict: PASS` and `Report OK: yes`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q`
    (45 tests).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS full GUT in isolated Godot profile (57 scripts, 1278/1278 tests,
    8904 asserts).
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed the same macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
  - The command-line live UI report still prints the known ObjectDB/resource
    warning after writing a passing report.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, combat logic, or economy values changed for H89.
- Latest trace:
  `.claude/traces/experiments/085-post-defeat-next-run-orientation.md`.
- Resume recommendation: checkpoint/commit the current H79-H89 stack soon.
  The next completion slice can either deepen natural-run coverage for more
  identities or ask explicit approval for H78 if the user wants to tackle the
  protected Druid strategy-floor blocker.

## 2026-07-30 Codex H88 update

- H88 completed as an unprotected checkpoint-readiness verification slice.
- This did not change gameplay code, balance data, card YAML, generated card
  DB, difficulty values, or protected simulator files.
- Verification:
  - PASS full GUT in an isolated Godot profile:
    `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit`
    (57 scripts, 1277/1277 tests, 8898 asserts).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `python3 -m unittest discover scripts/tests -q` (134 tests).
  - PASS `python3 -m py_compile scripts/run_live_ui_identity_matrix.py scripts/summarize_live_ui_report.py scripts/tests/test_run_live_ui_identity_matrix.py scripts/tests/test_summarize_live_ui_report.py`.
  - PASS `git diff --check`.
  - PASS `git status --short -- godot/sim` produced no output.
- Log notes:
  - Full GUT printed one macOS certificate probe line at startup.
  - Full GUT printed expected negative-path diagnostics for invalid card and
    revive-scope tests.
  - No ObjectDB/resource exit block was present in the full GUT log.
- Latest trace:
  `.claude/traces/experiments/084-checkpoint-readiness-verification.md`.
- Resume recommendation: the current unprotected stack is checkpoint-ready.
  The next completion slice should be selected from fresh play evidence rather
  than adding more observability for its own sake. H78 remains gated on
  explicit protected simulator approval.

## 2026-07-30 Codex H87 update

- H87 completed as an unprotected terminal-result clarity slice.
- `GameOverPopup.show_result()` now accepts optional terminal context and renders:
  - defeat final HP;
  - final-fight ally/enemy survivors;
  - final damage and HP transition;
  - run bests: max field units, attached upgrades, best win streak, and boss
    reward count.
- `GameManager` now passes final battle context and current run stats into the
  terminal overlay on defeat/victory paths.
- The visible-control live playthrough now asserts that the terminal overlay
  exposes the richer run-result summary. The current natural run still reaches
  defeat at R8.
- Verification:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_over_popup.gd -glog=1 -gexit`
    (3/3, 20 asserts).
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
    (14/14, 955 asserts).
  - PASS headless live UI report + summary:
    `/private/tmp/warforge_h87_live_ui_report_summary.md` reports
    `Verdict: PASS`, `Report OK: yes`, and run-end text containing
    `Run bests: 120 field units, 16 upgrades, 8-win streak, 1 boss reward`.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed for H87.
- Latest trace:
  `.claude/traces/experiments/083-terminal-result-clarity.md`.
- Resume recommendation: checkpoint H79-H87 soon. The next completion slice can
  use the visible-control terminal summary as evidence to choose a player-facing
  next-run orientation or a concrete late-run playability blocker.

## 2026-07-30 Codex H86 update

- H86 completed as an unprotected observability/workflow hardening slice.
- `scripts/run_live_ui_identity_matrix.py` now supports named presets:
  - `--preset=default` keeps the existing baseline/coin/Golden Die/locked
    economy matrix;
  - `--preset=expanded` runs the reusable special-commander set:
    Breeder/Cracked Egg, Collector/Glass Eye, Strategist/War Drum,
    Smith/Rusty Wrench, Raider/Mercury Drop.
- The matrix metadata and Markdown summary now record the selected preset.
  Repeated `--identity` rows still replace the preset and are labeled
  `custom` in metadata.
- Docs now show the expanded preset command instead of the long repeated
  identity command.
- Verification:
  - PASS `python3 -m py_compile scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py`.
  - PASS `python3 -m unittest scripts.tests.test_run_live_ui_identity_matrix -q`
    (10 tests).
  - PASS `python3 scripts/run_live_ui_identity_matrix.py --help` shows
    `--preset {default,expanded}`.
  - PASS default identity matrix:
    `/private/tmp/warforge_h86_default_identity_matrix/matrix.md` reports
    `Preset: default` and `Passing identities: 4/4`.
  - PASS expanded identity matrix:
    `/private/tmp/warforge_h86_expanded_identity_matrix/matrix.md` reports
    `Preset: expanded` and `Passing identities: 5/5`.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed for H86.
- Latest trace:
  `.claude/traces/experiments/082-expanded-identity-matrix-preset.md`.
- Resume recommendation: the H79-H86 stack is a coherent checkpoint candidate.
  For more completion movement, either checkpoint this stack first, or proceed
  to the next real playability gap found by visible-control/live identity
  evidence. H78 remains gated on explicit protected simulator approval.

## 2026-07-29 Codex H85 update

- H85 completed as an unprotected live acceptance guard.
- Added `test_live_visible_control_playthrough_reaches_terminal_overlay` to
  `test_game_manager_live_smoke.gd`.
- The test starts from a fresh profile, selects Gambler/Flint through the real
  run-start UI, then uses visible-control paths for:
  - shop slot clicks;
  - bench-to-field drag/drop;
  - optional upgrade shop click and target selection;
  - merge reward popup selection;
  - BUILD COMPLETE;
  - chain skip via Space;
  - boss reward popup selection;
  - real battle/settlement transitions;
  - final game-over ownership and meta-save verification.
- It does not seed cards, rounds, HP, gold, or battle outcomes during the
  acceptance run. In the passing run, the game naturally reached defeat at R8.
- Verification:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
    (14/14, 947 asserts).
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed for H85.
- Latest trace:
  `.claude/traces/experiments/081-visible-control-playthrough-acceptance.md`.
- Resume recommendation: the dirty H79-H85 stack is now a coherent
  observability/playability checkpoint. Next best step is either checkpointing
  this stack, then packaging the expanded identity matrix preset, or returning
  to H78 if protected simulator edits are explicitly approved.

## 2026-07-29 Codex pause after H84 multi-review

- User requested stopping after the currently-running review/run and resuming
  later with the same completion goal.
- Multi-review was completed and all advisory agents were closed.
- Review outcome:
  - Player-completion critic recommends H85 as a non-scripted live playability
    acceptance pass through normal player controls, fixing the first
    unprotected player-facing blocker if one appears.
  - Observability critic recommends packaging the already-useful expanded
    identity matrix as a named runner preset.
  - Scope-safety critic recommends no new feature slice before checkpointing or
    explicitly triaging the current dirty H79-H84 stack.
- Effective pause decision: do not start H85 yet. On resume, first choose
  whether to checkpoint the H79-H84 stack, then proceed with either the
  no-script live playability acceptance pass or the smaller identity-matrix
  preset packaging.
- Protected boundary remains intact at pause time: `git status --short --
  godot/sim` was empty.

## 2026-07-29 Codex H84 update

- H84 completed as an unprotected live-report evidence slice.
- Raider identity live UI reports now prove the real 3-win reward flow before
  later terminal unlock scripting:
  - the report seeds Raider at 2 wins on a non-boss battle;
  - the third win opens the visible common-upgrade `upgrade_choice`;
  - the report selects a visible upgrade and valid field target;
  - the target gains exactly one upgrade;
  - Raider `win_count` resets to 0;
  - the run returns to modal-free BUILD R3.
- `summarize_live_ui_report.py` now requires
  `events.raider_win_streak_reward` for Raider reports and summarizes it as
  `Raider 3-win reward proved live`.
- Direct Raider report:
  `/private/tmp/warforge_h84_raider_summary.md` reports `Verdict: PASS`,
  `Report OK: yes`,
  `Commander free upgrade flow resolved: raider_win_streak_upgrade: C4 -> field 0`,
  and `Raider 3-win reward proved live: C4 -> field 0, upgrades 0->1, win count 0, BUILD R3`.
- Expanded matrix after H84:
  `/private/tmp/warforge_h84_expanded_identity_matrix/matrix.md` reports
  `Verdict: PASS` and `Passing identities: 5/5`.
- Verification:
  - PASS direct Raider report:
    `/usr/bin/env HOME=/private/tmp/warforge_h84_raider_home godot --headless --log-file /private/tmp/warforge_h84_raider_report.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h84_raider_report.json --commander=raider --talisman=mercury_drop --unlock-selected=true`.
  - PASS `python3 scripts/summarize_live_ui_report.py --report /private/tmp/warforge_h84_raider_report.json --out /private/tmp/warforge_h84_raider_summary.md`.
  - PASS expanded identity matrix:
    `python3 scripts/run_live_ui_identity_matrix.py --output-dir=/private/tmp/warforge_h84_expanded_identity_matrix --out=/private/tmp/warforge_h84_expanded_identity_matrix/matrix.json --summary-out=/private/tmp/warforge_h84_expanded_identity_matrix/matrix.md --timeout-sec=90 --identity=breeder=breeder:cracked_egg --identity=collector=collector:glass_eye --identity=strategist=strategist:war_drum --identity=smith=smith:rusty_wrench --identity=raider=raider:mercury_drop`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q`
    (41 tests).
  - PASS `test_game_manager_live_smoke.gd` (13/13).
  - PASS `test_build_phase_upgrade_shop.gd` (17/17).
  - PASS `test_commander.gd` (37/37).
  - PASS `test_game_manager_logic.gd` (37/37).
  - PASS `git diff --check`.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, or player-facing runtime scenes changed for H84.
- Latest trace:
  `.claude/traces/experiments/080-raider-real-3win-live-evidence.md`.
- Resume recommendation: next unprotected slice can make the expanded identity
  matrix a named preset, or move to the next player-facing completion gap.
  H78 remains the direct Druid completion blocker, still gated by explicit
  protected simulator edit approval.

## 2026-07-29 Codex H83 update

- H83 completed as an unprotected live-report/observability follow-up after
  the H82 runner found special-commander gaps.
- Expanded identity probe before H83:
  - PASS `breeder=breeder:cracked_egg`
  - PASS `collector=collector:glass_eye`
  - PASS `strategist=strategist:war_drum`
  - FAIL `smith=smith:rusty_wrench`: Smith opened a legitimate start
    `upgrade_choice` modal before the generic chain step.
  - FAIL `raider=raider:mercury_drop`: the scripted terminal victory waited on
    Raider's 3-win free-upgrade flow.
- `live_ui_smoke_report.gd` now resolves optional commander free-upgrade modals
  through visible upgrade choice and field target selection, recording
  `events.commander_free_upgrade`.
- The scripted terminal unlock smoke resets Raider's local `win_count` just for
  that artificial final battle and records
  `events.commander_scripted_adjustments.raider_terminal_win_count_reset`.
  This keeps the terminal unlock recap smoke focused while Raider reward
  attachment remains covered by focused commander/build tests.
- `summarize_live_ui_report.py` now validates/summarizes optional
  `commander_free_upgrade` events when present.
- Actual expanded matrix after H83:
  `/private/tmp/warforge_h83_expanded_identity_matrix_final/matrix.md` reports
  `Verdict: PASS` and `Passing identities: 5/5`.
- Verification:
  - PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report scripts.tests.test_run_live_ui_identity_matrix -q`
    (38 tests).
  - PASS `test_game_manager_live_smoke.gd` (13/13).
  - PASS expanded identity matrix:
    `python3 scripts/run_live_ui_identity_matrix.py --output-dir=/private/tmp/warforge_h83_expanded_identity_matrix_final --out=/private/tmp/warforge_h83_expanded_identity_matrix_final/matrix.json --summary-out=/private/tmp/warforge_h83_expanded_identity_matrix_final/matrix.md --timeout-sec=90 --identity=breeder=breeder:cracked_egg --identity=collector=collector:glass_eye --identity=strategist=strategist:war_drum --identity=smith=smith:rusty_wrench --identity=raider=raider:mercury_drop`.
  - PASS `git diff --check`.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, or Godot runtime/player-facing scene files changed for
  H83.
- Latest trace:
  `.claude/traces/experiments/079-special-commander-identity-matrix.md`.
- Resume recommendation: next unprotected slice can either add a named
  expanded preset to the matrix CLI, add focused live evidence for Raider's real
  3-win upgrade timing, or move to the next live completion gap. H78 remains
  the direct Druid completion blocker, still gated by explicit protected
  simulator edit approval.

## 2026-07-29 Codex H82 update

- H82 completed as an unprotected observability/tooling slice.
- Added `scripts/run_live_ui_identity_matrix.py`, a small command-line matrix
  runner that calls the existing live UI smoke report for curated
  commander/talisman identities, then validates each generated `report.json`
  through `summarize_live_ui_report.py`.
- Default matrix identities:
  - `baseline=gambler:flint`
  - `coin=gambler:two_faced_coin`
  - `golden_die=gambler:golden_die`
  - `locked_economy=alchemist:soul_jar`
- Each matrix row gets its own report, summary, Godot log, and isolated Godot
  `HOME` profile under the output directory. The matrix fails if any row exits
  nonzero, misses its report, or fails the summary contract.
- Actual run:
  `/private/tmp/warforge_h82_live_ui_identity_matrix/matrix.md` reports
  `Verdict: PASS` and `Passing identities: 4/4`.
- Verification:
  - PASS `python3 -m py_compile scripts/run_live_ui_identity_matrix.py scripts/tests/test_run_live_ui_identity_matrix.py`.
  - PASS `python3 -m unittest scripts.tests.test_run_live_ui_identity_matrix -q`
    (6 tests).
  - PASS curated matrix command:
    `python3 scripts/run_live_ui_identity_matrix.py --output-dir=/private/tmp/warforge_h82_live_ui_identity_matrix --out=/private/tmp/warforge_h82_live_ui_identity_matrix/matrix.json --summary-out=/private/tmp/warforge_h82_live_ui_identity_matrix/matrix.md`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
    (30 tests).
  - PASS `git diff --check`.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  difficulty values, or Godot runtime files changed for H82.
- Latest trace:
  `.claude/traces/experiments/078-live-ui-identity-matrix-runner.md`.
- Resume recommendation: the next unprotected slice can either broaden the
  matrix with a custom identity preset if a specific commander/talisman remains
  suspicious, or move to another live completion gap. H78 remains the direct
  Druid completion blocker, still gated by explicit protected simulator edit
  approval.

## 2026-07-29 Codex H81 update

- H81 completed as an unprotected player-facing completion/orientation slice.
- Advisory multi-review was split:
  - player-completion critic recommended a real BUILD HUD R1-R15 progression
    rail over more report-only evidence;
  - observability critic recommended an identity matrix runner as a useful
    follow-up;
  - scope-safety critic recommended minimizing sprawl and keeping H78 gated.
  Adopted the player-facing rail and left the matrix as a future follow-up.
- The BUILD HUD round label now has a compact second-line rail:
  `R1 NOW | rewards R4 next, R8, R12 | R15 final`.
  It updates by round using the existing boss-round constants, so after reward
  milestones it marks them as `done`, and the next upcoming milestone as `next`.
- `LiveUiProbe` and `live_ui_smoke_report.gd` now expose/validate
  `progress_rail_text` under `run_milestone`.
- `summarize_live_ui_report.py` now reports the selected identity setup
  (`normal profile` vs `unlock-selected profile`) and the rendered progression
  rail, and fails if the rail is missing or not bound to the rendered round
  label.
- `docs/tools/live-ui-smoke-report.md` now documents `--unlock-selected=true`
  and the progression rail evidence.
- Verification:
  - PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
    (30 tests).
  - PASS `test_build_phase_upgrade_shop.gd` (17/17).
  - PASS `test_game_manager_live_smoke.gd` (13/13).
  - PASS Golden Die headless live UI report with
    `--commander=gambler --talisman=golden_die --unlock-selected=true`.
  - PASS Golden Die summary; summary says `Verdict: PASS`, `Report OK: yes`,
    `Selected identity setup: unlock-selected profile (talismans 6)`,
    `Run progression rail rendered: R1 NOW | rewards R4 next, R8, R12 | R15 final`,
    and `Boss reward popup title: 보스 보상 선택 (1개 선택 / 6개 후보).`
  - PASS full GUT in isolated Godot profile: 57 scripts, 1275/1275 tests,
    8807 asserts.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed.
- Latest trace:
  `.claude/traces/experiments/077-run-progression-rail.md`.
- Resume recommendation: next unprotected follow-up can be the H80/H81 live UI
  identity matrix runner. H78 remains the direct Druid completion blocker, but
  it still requires explicit approval to edit protected `godot/sim/**`.

## 2026-07-29 Codex H80 update

- H80 completed as the current observability/run slice, then work paused per
  user request. Do not start the next feature until the user resumes the same
  completion goal.
- The command-line live UI report now supports an opt-in
  `--unlock-selected=true` setup hook. In an isolated reset profile, it unlocks
  only the requested locked commander/talisman needed for the requested run
  identity before the normal selection UI is exercised.
- Unlock recap validation is now dynamic: the report records the raw unlock
  list, validates the shown top-three rows and overflow count from that raw
  list, and keeps the later progress-screen check aligned with the same data.
- Verified Golden Die through the command-line report without hand-preparing
  meta progress. The report selected Golden Die, reached the R4 boss reward,
  and the summary passed with six rendered reward choices and
  `보스 보상 선택 (1개 선택 / 6개 후보)`.
- Verification:
  - PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
    (29 tests).
  - PASS `test_game_manager_live_smoke.gd` (13/13).
  - PASS Golden Die headless live UI report with
    `--commander=gambler --talisman=golden_die --unlock-selected=true`.
  - PASS Golden Die summary; summary says `Verdict: PASS`, `Report OK: yes`,
    and `Boss reward popup title: 보스 보상 선택 (1개 선택 / 6개 후보).`
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed.
- Latest trace:
  `.claude/traces/experiments/076-live-ui-report-selected-unlock-profile.md`.
- Resume recommendation: H78 remains the most direct gameplay-completion
  blocker, but it still requires explicit approval to edit protected
  `godot/sim/**`.

## 2026-07-29 Codex H79 update

- H79 completed as an unprotected player-facing visibility/smoke slice while
  H78 remains gated by explicit protected simulator approval.
- Boss reward popup titles now include the visible candidate count:
  `보스 보상 선택 (1개 선택 / N개 후보)`.
- Added live smoke coverage for Golden Die: the test unlocks Golden Die in an
  isolated profile, selects it through the real talisman popup, wins R4, and
  verifies six visible boss reward choices, six rendered summaries, and a title
  containing `6개 후보`.
- The command-line live UI report now records boss reward `open_title` and
  `open_choice_count`; the Markdown summary validates count-vs-rendered-summary
  parity and reports the title.
- Verification:
  - PASS `python3 -m py_compile scripts/summarize_live_ui_report.py scripts/tests/test_summarize_live_ui_report.py`.
  - PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report -q`
    (28 tests).
  - PASS `test_boss_reward_popup.gd` (3/3).
  - PASS `test_game_manager_live_smoke.gd` (13/13).
  - PASS headless live UI report + summary; summary says `Verdict: PASS`,
    `Report OK: yes`, and
    `Boss reward popup title: 보스 보상 선택 (1개 선택 / 4개 후보).`
  - PASS full GUT in isolated Godot profile: 57 scripts, 1274/1274 tests,
    8709 asserts.
- No protected `godot/sim/**`, gameplay balance, card YAML, generated card DB,
  or difficulty values changed.
- Latest trace:
  `.claude/traces/experiments/075-golden-die-reward-choice-visibility.md`.
- Resume recommendation: H78 is still the most direct gameplay-completion
  blocker, but it still requires explicit approval to edit protected
  `godot/sim/**`.

## 2026-07-29 Codex H78 approval preflight

- H78 is ready but waiting for explicit approval to edit protected
  `godot/sim/**`.
- No protected simulator AI files were edited in this preflight.
- Prepared approval packet:
  `.claude/traces/experiments/074-druid-protected-ai-probe-approval-packet.md`.
- Exact intended protected write scope after approval:
  - `godot/sim/ai_agent.gd`
  - focused tests in `godot/tests/test_ai_agent.gd`
- Exact policy seam: `_should_hold_for_path_lag_purchase(...)` and its call
  from `_try_buy_best(...)`.
- Narrow probe: when soft-Druid is in payoff/capstone path lag and no
  current/next focus card is visible in offers, allow conservative high-value
  Druid body or neutral stabilizer purchases instead of always hard-holding.
  Preserve hard focus priority whenever focus is visible or affordable.
- The packet defines focused tests, same-seed 60-run command, H76/H77 analyzer
  checks, adoption gates, and rollback.
- Next step: ask the user to approve protected `godot/sim/**` edits for H78.

## 2026-07-29 Codex H77 update

- H77 completed as a behavior-neutral Druid path-lag decision audit; no
  protected `godot/sim/**`, Druid card YAML, generated card DB, combat/runtime,
  or AI behavior files were changed.
- Multi-review synthesis: design critic favored a protected AI policy probe,
  while measurement/safety critics required a joined decision-regret report
  first. Implemented the safe analyzer gate and used it to decide the next
  approval point.
- Added `--druid-path-lag-audit` to `scripts/analyze_ai_trace.py`. It joins
  `path_lag_hold` skips to visible offers, affordable focus cards, held best
  card/score, HP/gold/shop level, same-round rerolls, battle outcome, and H76
  conversion bucket.
- Real-trace command:
  `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-path-lag-audit --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces`.
- H75 audit: R8-R12 `path_lag_hold` fired `265` times from `51/60` runs.
  Focus cards were offered only `5` times and affordable only `1` time during
  those holds; `260/265` holds (`98.1%`) happened with no focus card visible.
- H75 categories: `no_focus_offer_druid_body_held 104`,
  `no_focus_offer_neutral_held 77`,
  `no_focus_offer_high_value_neutral_held 76`,
  `focus_offered_unaffordable 4`, `no_focus_offer_low_value_held 3`,
  `affordable_focus_available 1`.
- H75 by round: R9 `132`, R10 `76`, R11 `37`, R12 `20`. Average holds/loss
  `4.1`; max same-round holds `8`; loss enemy survivors after held rounds
  `13.9`.
- Path split: Garden `113` holds with `18` actionable no-focus loss runs;
  World Tree `151` holds with `17` actionable no-focus loss runs. Both gate to
  `GO_PROTECTED_PROBE_NO_FOCUS_STABILIZER_HOLD`.
- H75 vs H71 path-lag comparison shows stable baseline behavior, not an H75-only
  regression: holds `255 -> 265`, no-focus rate `98.4% -> 98.1%`, actionable
  no-focus loss runs `37 -> 36`.
- Decision: analyzer-only H77 adopted. The evidence now justifies requesting a
  narrow protected AI policy probe, but gameplay is not fixed yet.
- Verification:
  - PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (19 tests).
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (22 tests).
  - PASS `python3 scripts/analyze_ai_trace.py --help`.
  - PASS real-trace H75-vs-H71 path-lag audit command.
  - PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py docs/tools/self-play-observer.md`.
- Latest trace: `.claude/traces/experiments/073-druid-path-lag-decision-audit.md`.
- Resume recommendation: H78 should ask explicit approval to edit protected
  `godot/sim/**`, then test a temporary soft-Druid path-lag stabilizer-buy
  fallback: when no focus card is visible, allow high-value Druid bodies or
  high-value neutral stabilizers instead of always hard-holding.

## 2026-07-29 Codex H76 update

- H76 completed as a behavior-neutral Druid run-phase survival diagnostic; no
  gameplay/card values, generated card DB, AI scoring, combat/runtime, or
  protected `godot/sim/**` files were changed.
- Multi-review consensus: stop local Spore/Wrath base-number tuning and bind
  payoff ownership/activation to HP-at-activation plus immediate
  post-activation combat outcome.
- Added `--druid-run-phase` to `scripts/analyze_ai_trace.py`.
  It reports first payoff offer/affordable/buy/active/focus timing, HP at
  payoff buy and focus activation, R8-R12 survival curves, owned-but-inactive
  payoff rates, path-lag skip counts, false-green examples, and conversion
  buckets.
- New exclusive buckets: `no_payoff_seen`, `offered_not_bought`,
  `bought_not_active`, `active_too_late`, `active_no_combat_swing`,
  `active_no_survival_swing`, and `converted`.
- The diagnostic also prints a run-phase comparison when combined with
  `--druid-compare-baseline`, but its signal is subordinate to the H74 strict
  probe screen.
- Real-trace command:
  `python3 scripts/analyze_ai_trace.py /private/tmp/warforge_h75_coupled60_traces --strategy=soft_druid --druid-run-phase --druid-compare-baseline=/private/tmp/warforge_h71_ledger60_druid_traces`.
- H75 run-phase read: `10/60` wins, buckets `active_too_late 15`,
  `no_payoff_seen 10`, `converted 10`, `active_no_survival_swing 8`,
  `offered_not_bought 8`, `active_no_combat_swing 6`, `bought_not_active 3`.
- Losses: offer/buy/active `80.0%/64.0%/62.0%`, both-active `10.0%`,
  focus `R9.5`, HP at focus `20.1`, post-active WR `25.8%`, dead within one
  round after activation `17/31`.
- Path split: Garden is mostly timing/acquisition (`active_too_late 10`,
  `no_payoff_seen 7`, `active_no_combat_swing 5`), while World Tree has more
  non-stabilizing active wins (`active_no_survival_swing 7`).
- R9-R12 `path_lag_hold` counts remain high: `132`, `76`, `37`, `20`.
- H75 vs H71 run-phase comparison found only nomination-level movement
  (`converted +1`, loss post-active WR `18.8% -> 25.8%`), while H74 still says
  `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`.
- Verification:
  - PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (17 tests).
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (20 tests).
  - PASS real-trace H75-vs-H71 analyzer command.
  - PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py docs/tools/self-play-observer.md`.
- Latest trace: `.claude/traces/experiments/072-druid-run-phase-survival-diagnostic.md`.
- Resume recommendation: H77 should target Druid Garden timing/economy/path-lag
  pressure first, not raw Spore/Wrath values. Use `--druid-run-phase` beside
  H74 comparison for all future Druid probes.

## 2026-07-29 Codex H75 update

- H75 completed as a measured coupled Druid card-data probe, then rejected and
  rolled back.
- Probe tested the exact H72+H73 combination:
  - `dr_spore_cloud` star 1 AS base `0.15 -> 0.20`.
  - `dr_spore_cloud` star 2 AS/ATK bases `0.20 -> 0.25`.
  - `dr_wrath` star 1 `atk_base_pct` `0.80 -> 1.20`.
  - `dr_wrath` star 2 `atk_base_pct` `1.20 -> 1.60`.
  - Spore scaling/caps/star 3, Wrath scaling/HP/caps/star 3, World Tree,
    runtime, AI, difficulty, UI, and protected `godot/sim/**` unchanged.
- Multi-review endorsed this only as an interaction falsification screen, not
  an adoption candidate. Returned reviewers agreed on strict gates and a
  YAML-only/codegen-only safe surface.
- Same-seed 60-run D1 `soft_druid` candidate with seed `2026072901`: 10/60
  clears, avg HP -3.45, avg rounds 11.20.
- H75 comparison vs H71: R9-R11 focus WR `34.6% -> 41.0%` (+6.4pp), but H74
  screen verdict stayed `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`.
- Active-loss survivor margin did not move: ally `0.0 -> 0.0`, enemy
  `13.8 -> 13.8`. The intended `dr_spore_cloud+dr_wrath` focus combo had
  `+0.0pp` WR delta and only `-0.1` enemy survivor movement.
- Decision: REJECT. The candidate only relabeled the failures from
  `debuff_too_small` to `damage_shortfall`/mixed margins and did not produce
  terminal or survivor-margin movement.
- Retained non-gameplay hardening: `test_spore_cloud_s2_sets_enemy_as_and_atk_debuff`
  now asserts adopted Spore star 2 AS/ATK debuff math exactly.
- Post-rollback verification:
  - PASS `python3 scripts/codegen_card_db.py --check`.
  - PASS `python3 -m unittest scripts.tests.test_card_desc_codegen scripts.tests.test_lint_card_spawn -q` (13 tests).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `test_druid_system.gd` 54/54.
  - PASS `test_chain_engine.gd` 21/21.
  - PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_druid_system.gd`.
- Latest trace: `.claude/traces/experiments/071-druid-spore-wrath-coupled-probe.md`.
- Resume recommendation: H76 should pivot away from Spore/Wrath base-number
  probes. Inspect Druid path-lag/payoff acquisition and board-state conversion,
  especially why Spore+Wrath frames are present but not winning, or broaden to a
  survival-curve diagnostic before touching more card numbers.

## 2026-07-29 Codex H74 update

- H74 completed as behavior-neutral Druid probe observability; no gameplay,
  card values, AI scoring, generated card DB, or protected `godot/sim/**` files
  were changed.
- Multi-review result was split: design/measurement critics preferred a ledger
  before a coupled Spore+Wrath probe, while the implementation critic warned
  that true pre-combat contribution tracing would cross into protected sim
  instrumentation. Adopted compromise: a Python-only baseline-comparison ledger
  using existing trace events.
- Added `--druid-compare-baseline=<trace_dir>` to `scripts/analyze_ai_trace.py`.
  It reports candidate-vs-baseline clears, average final HP, R9-R11
  focus-active WR, active-loss survivor margins, bottleneck deltas,
  focus-combo deltas, and a conservative screen verdict.
- H72 vs H71 comparison now reports `WEAK_LOCAL_SIGNAL_DO_NOT_ADOPT`: 9/60 to
  10/60 clears, avg HP `-4.23 -> -3.65`, R9-R11 focus WR `34.6% -> 39.8%`,
  but active-loss ally survivors remained `0.0 -> 0.0` and enemy survivors
  barely moved `13.8 -> 13.6`.
- H73 vs H71 comparison now reports `REJECT_FLAT_OR_NOISY`: 9/60 to 9/60
  clears, avg HP `-4.23 -> -3.80`, R9-R11 focus WR `34.6% -> 37.0%`,
  active-loss ally survivors `0.0 -> 0.0`, enemy survivors `13.8 -> 14.1`.
- Verification:
  - PASS `python3 -m py_compile scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace -q` (15 tests).
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (18 tests).
  - PASS H72/H73 comparison commands against the H71 baseline.
  - PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- Latest trace: `.claude/traces/experiments/070-druid-probe-comparison-ledger.md`.
- Resume recommendation: H75 can run one explicitly coupled Spore+Wrath
  YAML-only probe if continuing Druid. Use H71 as baseline and the new
  comparison report as the screen gate; do not adopt unless clears, avg HP,
  focus-active WR, and active-loss survivor margins move together, then confirm
  on a disjoint seed.

## 2026-07-29 Codex H73 update

- H73 completed as a measured Druid offensive card-data probe, then rejected and rolled back.
- Probe tested: `dr_wrath` star 1 `atk_base_pct` `0.8 -> 1.2`, star 2
  `atk_base_pct` `1.2 -> 1.6`; tree scaling, HP, unit caps, star 3, World
  Tree, Spore Cloud, runtime, and AI unchanged.
- Multi-review converged on a Wrath base-only probe because H72 exposed
  `damage_shortfall`, while most failed Wrath frames were star 1 / zero-tree.
- Same-seed 60-run D1 `soft_druid` candidate with seed `2026072901`: 9/60
  clears, avg HP -3.80, avg rounds 11.08. This did not improve clears over the
  H71 accepted baseline.
- H73 ledger result: 81 R9-R11 focus-active frames, 30 wins / 51 losses, 37.0%
  WR. Active losses still ended with 0.0 allied survivors and about 14.2 enemy
  survivors.
- Decision: REJECT. Isolated Wrath base damage did not pass clear-rate,
  focus-active WR, or survivor-margin gates.
- Retained non-gameplay hardening: `test_druid_system.gd` now asserts exact
  adopted Wrath star 1/2 ATK/HP math instead of vague `assert_gt`.
- Post-rollback verification:
  - PASS `python3 scripts/codegen_card_db.py --check`.
  - PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q` (3 tests).
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `test_druid_system.gd` 53/53.
  - PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_druid_system.gd`.
- Latest trace: `.claude/traces/experiments/069-druid-wrath-base-offense-probe.md`.
- Resume recommendation: H74 should not continue isolated Spore or Wrath base
  buffs. Either add a focused battle contribution ledger for Druid focus cards,
  or explicitly test a combined Spore+Wrath coupled hypothesis with attribution
  called out up front.

## 2026-07-29 Codex H72 update

- H72 completed as a measured Druid card-data probe, then rejected and rolled back.
- Probe tested: `dr_spore_cloud` star 1 AS base `0.15 -> 0.20`, star 2 AS/ATK
  bases `0.20 -> 0.25`; tree scaling, caps, star 3, runtime, and AI unchanged.
- Multi-review converged on a YAML-only base-value probe because H71's
  Spore-present losses were all star 1 and mostly zero-tree.
- Same-seed 60-run D1 `soft_druid` candidate with seed `2026072901`: 10/60
  clears, avg HP -3.65, avg rounds 11.18. This was only +1 clear and +0.58 HP
  over the H71 baseline.
- H72 ledger result: 83 R9-R11 focus-active frames, 33 wins / 50 losses, 39.8%
  WR. Spore-active all-round conversion improved to 42 wins / 33 losses
  (56.0%), but active losses still ended with 0.0 allied survivors and about
  14.2 enemy survivors.
- Decision: REJECT. The probe removed `debuff_too_small` as the dominant label
  but did not pass clear-rate, focus-active WR, or survivor-margin gates.
- Post-rollback verification:
  - PASS `python3 scripts/codegen_card_db.py --check`.
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS `test_druid_system.gd` 53/53.
  - PASS `test_chain_engine.gd` 21/21.
  - PASS `git diff --check -- data/cards/druid.yaml godot/core/data/card_db.gd godot/core/data/card_descs.gd godot/tests/test_chain_engine.gd godot/tests/test_druid_system.gd`.
- Latest trace: `.claude/traces/experiments/068-druid-spore-base-mitigation-probe.md`.
- Resume recommendation: H73 should target Druid offensive battle conversion,
  especially Wrath/World Tree R9-R11 damage shortfall. Do not keep pushing
  Spore base mitigation without new evidence.

## 2026-07-29 Codex H71 update

- H71 completed: behavior-neutral Druid active battle ledger added to `scripts/analyze_ai_trace.py`
  via `--druid-active-ledger`; no gameplay/card/AI values changed.
- Multi-review converged on observability before another gameplay probe because H67 AI variants and
  H70 Lifebeat reach both produced weak or false-green movement.
- New ledger scopes R9-R11 Druid focus-active battles and classifies each loss by one primary
  bottleneck, grouped by focus combo, focus card, and path.
- 60-run `soft_druid` D1 baseline with seed `2026072901`: 9/60 clears, avg HP -4.23, avg rounds
  11.07. Boss reward application remained clean for eligible R4/R8/R12 runs.
- H71 ledger result: 81 R9-R11 focus-active frames, 28 wins / 53 losses, 100% detail/star/tree
  coverage. Primary bottlenecks: `debuff_too_small` 30, `debuff_missing` 15,
  `enemy_pressure_spike` 6, `damage_shortfall` 1, `board_mass_shortfall` 1.
- Interpretation: the next Druid gameplay probe should target Spore Cloud early mitigation or
  Spore/Wrath pairing value. Do not retry Lifebeat all-Druid reach or broad AI activation/promotion
  variants without new evidence.
- Verification:
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace` (14 tests).
  - PASS `python3 -m unittest scripts.tests.test_analyze_ai_trace scripts.tests.test_summarize_self_play_report -q` (17 tests).
  - PASS `git diff --check -- scripts/analyze_ai_trace.py scripts/tests/test_analyze_ai_trace.py`.
- Latest trace: `.claude/traces/experiments/067-druid-active-battle-ledger.md`.
- Resume recommendation: H72 should run one narrow Spore Cloud star 1/2 mitigation card-data probe,
  measured by same-seed Druid clears, focus-active WR, active-loss survivor margins, and the new
  active ledger. Confirm on disjoint seed before adoption.

## 2026-07-29 Codex H70 pause update

- H70 completed as a measured Druid balance probe, then paused per user request.
- Probe tested: `dr_lifebeat` star 1/2 `tree_shield.target` from adjacent cards to all Druid cards.
- Decision: REJECTED and rolled back. It moved clears from 4/30 to 5/30 and avg HP from -4.17 to
  -2.83 on the same seed, but active losses still had 0.0 allied survivors and about 14.7 enemy
  survivors. The result was too weak to adopt or spend another run on disjoint-seed confirmation.
- Post-rollback verification:
  - PASS `python3 scripts/codegen_card_db.py --check`.
  - PASS `python3 -m unittest scripts.tests.test_card_desc_codegen -q`.
  - PASS `test_druid_system.gd` 53/53.
  - PASS `python3 scripts/lint_card_spawn.py`.
- Latest trace: `.claude/traces/experiments/066-druid-lifebeat-shield-reach-probe.md`.
- Resume recommendation: continue Druid R9-R11 combat conversion, but do not retry Lifebeat
  all-Druid reach as-is. The next probe should target payoff battle math or failed active-battle
  survivor margins more directly.

## 2026-07-29 Codex H69 update

- H69 completed: Druid combat data/runtime parity fixes before any further balance tuning.
- Adopted changes:
  - `dr_spore_cloud` ★3 now applies its YAML-defined self `tree_shield` at battle start.
  - `dr_wrath` ★3 now uses explicit `kill_hp_recover: 0.15`, stores active recovery state only
    while its unit-cap condition holds, and materializes that state into live/headless combat.
  - Combat `kill_hp_recover` heals the attacker by max HP percentage on kill, capped at max HP.
  - `dr_grace` ★3 post-combat `free_reroll` now reaches `ChainEngine` and the pending free-reroll
    callback.
  - `test_druid_theme_system_handles_all_current_yaml_actions` now guards current Druid YAML action
    names against silent runtime no-ops.
- H69 evidence:
  - Same-seed `soft_druid`: 4/30 clears, avg HP -4.17, avg rounds 11.07.
  - Focus-active Druid battles remain 27/62 wins; active losses still end with 0.0 allied survivors
    and about 15.9 enemy survivors.
  - Loss buckets remain centered on `path_lag_hold_pressure` and `combat_conversion_failure`.
  - 35-run all-strategy smoke stayed broad-system clean: 17/35 clears overall, `soft_druid` 0/5.
- Verification completed:
  - PASS `python3 scripts/codegen_card_db.py --check`.
  - PASS `python3 scripts/lint_card_spawn.py`.
  - PASS focused Python guards 47/47.
  - PASS focused GUT: Druid 53/53, Chain 21/21, Combat Basics 17/17, Combat Advanced 15/15,
    GameManager Logic 37/37, Headless Runner 15/15.
  - PASS full GUT 1272/1272 across 57 scripts.
  - PASS `git diff --check`.
- Latest trace: `.claude/traces/experiments/065-druid-combat-data-parity.md`.
- Resume recommendation: continue Druid combat conversion as a measured balance probe, not another
  correctness pass. Prefer Spore Cloud/Wrath/World Tree active R9-R11 battle math and survivability;
  avoid repeating H67 acquisition/commitment variants unless the evaluator changes.

## 2026-07-02 Codex autonomous update

- G-4 D5-D8 난이도 후속 캘리브레이션 완료: D4 적 유닛 수 보정은 ×1.15에서 ×1.10으로 완화. D7 적 ATK는 ×1.30에서 ×1.10으로 완화. D7 보스 업그레이드는 R12 레어, R15 에픽으로 지연하고 R15의 레어+에픽 중첩을 제거.
- 70-run D7-D8 확인 sweep (`--runs=10`, 7 strategies, seed=42, best_genome): D7 clear 1.4%, avg rounds 9.03; D8 clear 1.4%, avg rounds 8.13. 이전 0% 벽은 깨졌지만 여전히 극고난도 영역.
- Small full sweep (`--runs=5`, 7 strategies, seed=42, best_genome): D1 28.6%, D2 25.7%, D3 22.9%, D4 5.7%, D5 8.6%, D6 2.9%, D7 0.0%, D8 0.0%. 작은 표본은 D7-D8 희박 clear를 놓칠 수 있어 대형 sweep/사람 플레이 표본으로 미세 튜닝 권장.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_difficulty.gd -glog=1 -gexit` — 7/7
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1109/1109 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` — 10 tests OK
  - PASS `git diff --check`
- 자율 진행 셋업 완료: 난이도 수치는 버그 수정 외 동결하고, `Plans.md`의 "Playable Prototype Completion After Difficulty"를 새 Active Plan으로 전환.
- 다음 우선순위: G-6 상세 메타 진행 화면 → G-7 업그레이드 부착 비교 UX → G-8 실제 플레이 중 튜토리얼 오버레이 → G-9 성장 체인 가독성 → G-10 sim ON_REROLL parity → G-11 stale design backlog cleanup.
- 다음 착수 권장: G-6. `godot/scripts/ui/run_start_screen.gd`, `godot/scenes/ui/run_start_screen.tscn`, `godot/core/meta_progress.gd`, `godot/tests/test_run_start_screen.gd`, `godot/tests/test_meta_progress.gd`를 같이 수정해 전체 해금/업적 상태를 시작 화면에서 확인 가능하게 만든다.
- G-6 상세 메타 진행 화면 완료: `MetaProgress.get_full_progress_text()`와 unlock/achievement status row API 추가. `RunStartScreen`의 `PROGRESS` 버튼으로 접힘형 상세 패널을 열어 전체 커맨더/부적 해금 상태, 완료 업적, 잠긴 목표를 확인 가능.
- G-6 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta_progress.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 6/6
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1111/1111 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-7. `godot/scripts/build/build_phase.gd`, `godot/scenes/build/build_phase.tscn`, `godot/scripts/build/upgrade_shop.gd`, `godot/scripts/ui/upgrade_visual.gd`, `godot/tests/test_build_phase_upgrade_shop.gd`를 중심으로 업그레이드 대상 선택 시 슬롯/부착 가능 여부/효과 미리보기를 표시한다.
- G-7 업그레이드 부착 비교 UX 완료: `TargetSelectOverlay`가 context/detail/preview label을 받을 수 있게 확장됨. 업그레이드 구매/무료 업그레이드 대상 선택 시 업그레이드 효과, 카드별 `Slots n/m -> n+1/m`, full slot `FULL n/m` 표시.
- G-7 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_rusty_wrench_detach.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_attach.gd -glog=1 -gexit` — 14/14
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1113/1113 across 48 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-8. `BuildPhase`에 첫 런/초기 런용 in-run tutorial hint overlay를 추가한다. 시작 화면 가이드는 이미 있으므로, 상점 구매/보드 배치/업그레이드/BUILD 확정의 맥락형 힌트와 저장된 dismiss 상태를 우선 검토한다.
- G-8 실제 플레이 중 튜토리얼 오버레이 완료: 첫 런 BuildPhase에서 `TUTORIAL` 패널을 표시한다. 상태별 힌트는 카드 구매 → 벤치에서 FIELD 배치 → UPGRADES 구매 → 업그레이드 대상 선택 → BUILD COMPLETE 준비 순서로 갱신된다. `DISMISS` 버튼은 현재 런에서 숨기고 `tutorial_dismissed` 신호를 emit한다.
- G-8 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_tutorial.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 6/6
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1119/1119 across 49 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: G-9. `godot/scripts/chain/chain_visual.gd`, `godot/scenes/chain/chain_visual.tscn`, `godot/tests/test_chain_engine.gd` 또는 신규 `test_chain_visual.gd`를 중심으로 trigger count/source-target/reward event 가독성을 개선한다.
- G-9 성장 체인 가독성 완료: `ChainVisual`에 페이즈/최근 이벤트 로그 패널을 추가했다. 체인 이벤트는 `소스 카드 -> 대상 카드`, `+Unit`/`+ATK%` 같은 보상 요약, Layer1/Layer2 키워드를 함께 표시하고, 완료 시 trigger count와 gold 보상을 요약한다. 빈 상태에서는 새 로그 패널을 숨겨 빌드 화면 방해를 줄인다.
- G-9 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_engine.gd -glog=1 -gexit` — 18/18
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1124/1124 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: G-10. `godot/sim/shop_logic.gd`, `godot/sim/headless_runner.gd`, `godot/core/chain_engine.gd`, `godot/tests/test_sim_shop_logic.gd`, `godot/tests/test_steampunk_system.gd`를 중심으로 headless sim reroll path가 live `game_manager.gd`의 ON_REROLL trigger와 같은 효과를 내도록 맞춘다.
- G-10 sim ON_REROLL parity 완료: `ShopLogic.reroll()`에 선택적 trigger callback을 추가했다. `HeadlessRunner`는 이 callback에서 `chain_engine.process_reroll_triggers(state.get_active_board())`를 호출하고 gold/terazin/levelup_discount를 state에 반영한다. `sp_interest` 리롤 성장, `ne_pawnbroker` 리롤 레벨업 할인, 실패 리롤 미발동을 테스트로 고정했다. `docs/design/backlog.md`에서는 ON_REROLL parity를 해결로 표시하고, RS/pending free-reroll 생성·소비는 별도 latent 항목으로 분리했다.
- G-10 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 20/20
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 12/12
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_steampunk_system.gd -glog=1 -gexit` — 50/50
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_pawnbroker_reroll.gd -glog=1 -gexit` — 6/6
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1129/1129 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: G-11. `docs/design/backlog.md`, `docs/design/boss-rewards.md`, `docs/design/upgrade.md`, `DESIGN.md`, `.claude/backlog.md`를 대조해 이미 구현된 보스 보상/시스템 미결 항목을 현재 코드 상태와 맞춘다.
- G-11 stale design backlog cleanup 완료: 이미 구현된 보스 보상 27종, 테라진 1차 경제, 리플레이/메타/난이도 1차 구현, 적 파워 곡선, 성장 체인 가시화, 업그레이드/Rusty Wrench/Alchemist epic shop, 금간 해골 상한 문구를 현재 구현 상태와 동기화했다. G6-G11 "Playable Prototype Completion After Difficulty" 계획은 완료로 닫고, 새 Active Plan은 "Prototype Hardening After Player-Facing Loop"로 전환했다.
- G-11 검증:
  - PASS doc review against `docs/design/backlog.md`, `docs/design/upgrade.md`, `docs/design/talismans.md`, `.claude/backlog.md`, and `Plans.md`.
  - PASS `git diff --check`
- 다음 착수 권장: H-1 desc_gen multi-block listen separation. `scripts/card_desc_gen.py`, `docs/design/card-desc-codegen.md`, generated `godot/core/data/card_descs.gd`, and the current `pr_transcend` description should be checked so separate OE listen targets do not collapse into one misleading reaction prefix.
- H-1 desc_gen multi-block listen separation 완료: 현재 codegen projection은 same-timing/non-primary block action에 `listen_override`를 주입하고, desc_gen은 `(timing, listen_key)` section별로 prefix/max_act를 분리한다. 설계 문서의 `generate_star_desc` 설명을 현재 계약에 맞췄고, `pr_transcend`가 `부화 시`/`변태 시`를 별도 `[반응]` 문장으로 유지하는 Python 회귀 테스트를 추가했다.
- H-1 검증:
  - PASS `python3 -m unittest scripts.tests.test_card_desc_codegen` — 2/2
  - PASS `python3 scripts/codegen_card_db.py --check`
  - PASS `git diff --check`
- 다음 착수 권장: H-2 sim pending free-reroll parity. G10의 paid reroll ON_REROLL callback은 해결됐으므로, 남은 범위는 live의 pending free-reroll 생성/소비와 headless AI reroll 의사결정의 표현 차이를 분리해 처리한다.
- H-2 sim pending free-reroll parity 완료: `ShopLogic.reroll()`이 pending 무료 리롤을 골드보다 먼저 소비하고, 무료/유료 성공 리롤 모두 ON_REROLL trigger callback을 발동한다. `AIAgent`는 pending 무료 리롤이 있으면 gold reserve 조건을 우회해 리롤할 수 있다. `HeadlessRunner`는 chain 시작 시 pending/round reroll을 live처럼 리셋하고 보스 보상 매턴 무료 리롤을 충전하며, chain callback으로 전당포/폐품 상회의 무료 리롤 적립을 `GameState.pending_free_rerolls`에 반영한다.
- H-2 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 22/22
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_pawnbroker_reroll.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_neutral_system.gd -glog=1 -gexit` — 57/57
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1133/1133 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- 다음 착수 권장: H-3 combat talisman regression coverage. 금간 해골/전쟁 북은 데이터/query 테스트보다 전투 엔진 적용 경로가 중요하므로 combat-level 회귀 테스트로 고정한다.
- H-3 combat talisman regression coverage 완료: `test_talisman.gd`에 전투 엔진 fixture를 추가해 전쟁 북의 수적 우위 ATK 감소가 실제 전투 피해로 반영되는지, 금간 해골의 `undying` 주입이 아군에게만 들어가는지, 첫 치사 피해만 HP 1 생존으로 막고 두 번째 치사 피해에는 사망하는지 고정했다.
- H-3 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit` — 38/38
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1136/1136 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
- H-4 착수 배경: 플레이어가 합성 결과와 체인 순서를 텍스트 로그 없이도 더 잘 읽도록 합성/체인 feedback을 개선한다.
- H-4 merge/chain polish pass 완료: `BuildPhase`가 최근 합성 결과를 HUD 라벨로 표시한다. ★1→★2는 무료 Rare 업그레이드 대기, ★2→★3는 최종 합성 또는 캐스케이드 보상 대상 이전을 요약한다. `ChainVisual`의 라인 위 플로팅 텍스트는 `#1 +Unit`처럼 발동 순번을 포함해 로그 패널을 보지 않아도 순서를 읽을 수 있다.
- H-4 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1137/1137 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- H-5 sim diversity next-slice triage 완료: 난이도 수치는 계속 동결하고 140-run sim 기준선을 재측정했다. 현재 best_genome, seed=42, 20 runs × 7 strategies 결과는 weighted 0.4850, card_coverage 0.2175, soft_steampunk 1/20, soft_druid 2/20, adaptive 11/20, aggressive 12/20. 다음 축은 broad difficulty가 아니라 낮은 focused 전략의 payoff/전환 안정성으로 확정.
- H-6 AI bench-space sale bug fix 완료: `_sell_weakest_for_upgrade()`가 벤치 공간 확보 중 보드를 팔 수 있던 버그를 제거하고 bench-only 판매로 제한했다. 대표 soft_steampunk seed에서 보드 판매 후 구매 실패 패턴이 사라졌고, 140-run 기준선은 weighted 0.4903, card_coverage 0.2195, soft_steampunk 2/20, soft_druid 3/20으로 개선.
- H-6 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_board_eval.gd -glog=1 -gexit` — 14/14
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json` — weighted 0.4903
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1139/1139 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- H-7 military target warning cleanup 완료: `MilitarySystem._dispatch_r_effect()`가 모든 r_conditional inner effect의 target을 선해석하던 흐름을 제거하고, 실제 target 리스트가 필요한 `train`/`conscript` 액션 안에서만 `_resolve_targets()`를 호출한다. `revive_scope_override`의 `self_all`/`self_and_adj_all`은 `resolve_command_revive()`/`resolve_revive_scope()` 전용 target으로 남아 generic dispatcher 경고를 내지 않는다.
- H-7 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_military_system.gd -glog=1 -gexit` — 81/81. 새 rank 4/10 `ml_command` RS 회귀 테스트 포함.
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=1 --seed=42 --baseline=res://sim/baseline.json` — `[military r_conditional]` warning 없음.
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1141/1141 across 50 scripts. At this point the remaining GUT warnings were the expected unknown revive-scope fallback test plus pre-existing float/int assertion warnings in `test_genome.gd`; H-8 cleaned those next. Godot still reports ObjectDB/resource warnings on exit.
- H-8 GUT warning-noise cleanup 완료: `test_genome.gd`의 JSON float 값 비교를 float-aware assertion으로 바꾸고, unknown revive-scope fallback warning을 `assert_push_warning()`으로 명시해 GUT summary warning total을 8개에서 0개로 줄였다.
- H-8 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_genome.gd -glog=1 -gexit` — 10/10, warning 없음.
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_military_system.gd -glog=1 -gexit` — 81/81, expected push_warning 명시.
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1141/1141 across 50 scripts, GUT warning total 없음. Godot still reports ObjectDB/resource warnings on exit.
- H-9 next playability slice selection 완료: 다음 completion-oriented track은 live run reward/flow hardening으로 확정. 밸런스와 visual polish는 queue에 남기되, 먼저 플레이어가 약속된 보상과 런 전환을 실제로 경험하는지 확인한다.
- H-10 착수 배경: `docs/design/replay.md`와 `docs/design/commanders.md`는 약탈자가 3연승마다 커먼 업그레이드를 얻는다고 설명하지만, 이전 `godot/scripts/game/game_manager.gd`는 해당 지점에서 TODO print만 남겼다. `godot/core/commander.gd`, `godot/scripts/game/game_manager.gd`, `godot/scripts/build/build_phase.gd`, `godot/tests/test_commander.gd`와 신규/확장 GameManager reward-flow 테스트를 중심으로 선택 가능한 커먼 업그레이드 → 대상 카드 부착 흐름을 연결하는 작업이었다.
- H-10 Raider 3-win reward flow 완료: `game_manager.gd`가 약탈자 승리 누적을 기록하고 3번째 승리 후 HP>0이면 보스 보상/정착 전에 커먼 업그레이드 3택1을 띄운다. 선택한 업그레이드는 `BuildPhase.start_free_upgrade_selection(..., "raider_win_streak")`로 필드 카드에 무료 부착되며, target overlay는 "Raider 3-win reward" 안내를 표시한다.
- H-10 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit` — 36/36
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 8/8
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit` — 34/34
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1144/1144 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- 다음 착수 권장: H-11 boss reward target/upgrade UX audit. `godot/scripts/game/game_manager.gd`, `godot/core/boss_reward.gd`, `godot/core/data/boss_reward_db.gd`, `godot/tests/test_boss_reward.gd`, `godot/tests/test_headless_rewards.gd`, `godot/tests/test_build_phase_upgrade_shop.gd`를 중심으로 dead `needs_upgrade_choice` path와 attach 보상 full-slot/target 안내를 확인한다.
- H-11 boss reward target/upgrade UX audit 완료: sequential multi-review fallback 결과, 보스 보상은 설계 문서처럼 "대상 카드 선택 + 랜덤 레어/에픽 부착"으로 유지하고 dead `needs_upgrade_choice` 선택형 업그레이드 경로는 제거했다. 선택형 업그레이드를 살리는 것은 live popup, `BossReward.apply_with_target()`, sim AI, 로그/테스트를 동시에 바꾸는 큰 범위라 H11 목적 밖으로 판정했다.
- H-11 구현:
  - `BossReward.can_target_reward()`/`can_select_reward()`/`get_free_upgrade_slots()` 추가. r8_1은 ★승급 가능+슬롯 1개, r8_7은 슬롯 1개, r12_7은 슬롯 2개, r12_1은 step1 ★2/step2 ★1 대상만 허용.
  - `BossReward.apply_with_target()`도 같은 eligibility를 통과하지 못하면 no-op 처리해 partial attach를 막는다.
  - `BossRewardDB`에서 `needs_upgrade_choice` 필드/등록 인자를 제거했다.
  - `GameManager`는 현재 보드에서 선택 가능한 보스 보상만 팝업에 노출하고, target overlay에 reward별 instruction/detail/preview note를 표시한다. 보스 target 선택 중 ESC는 스킵 대신 같은 선택을 다시 연다.
  - `AIRewardLogic`과 `HeadlessRunner`도 같은 target eligibility를 사용하도록 맞췄다.
- H-11 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward.gd -glog=1 -gexit` — 70/70
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_rewards.gd -glog=1 -gexit` — 17/17
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit` — 36/36
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 8/8
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1152/1152 across 50 scripts. Godot still reports ObjectDB/resource warnings on exit.
  - PASS `git diff --check`
- H-12 완료: end-to-end live run smoke를 추가했다.
  - Multi-review fallback 결정: 실제 combat engine을 smoke에서 돌리기보다 `main.tscn`과 `GameManager` live scene을 띄운 뒤 deterministic `_on_battle_finished()` 결과를 주입한다. 이렇게 run-start/UI/meta-save hook은 live로 검증하고, 전투 난수/시간 의존성은 smoke 밖에 둔다.
  - `GameManager`에 테스트 격리 hook 3개 추가: `meta_progress_save_path`, `battle_result_delay_sec`, `play_logger_enabled`. 기본값은 기존 동작을 유지하고, smoke에서는 별도 `user://meta_progress_live_smoke_test.cfg`, 즉시 battle-result timeout, PlayLogger 비활성으로 실행한다.
  - 신규 `test_game_manager_live_smoke.gd`는 run-start → commander/talisman selection → BUILD 진입, 비치명 전투 결과 → settlement → R2 BUILD, 치명 패배 → game-over/meta defeat save, R15 승리 → victory overlay/meta victory save/난이도 2 해금을 고정한다.
- H-12 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit` — 36/36
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1155/1155 across 51 scripts. Godot still reports ObjectDB/resource warnings on exit.
- H-13 완료: ObjectDB/resource warning triage를 닫았다.
  - Multi-review fallback 결정: verbose detail이 필요한 검증-health 작업이므로 원인 attribution을 우선하고, 엔진/GUT 이슈가 아니라 repo RefCounted 순환이면 좁게 수정한다.
  - `--verbose` 단독은 Godot rotated logger가 `user://logs/godot*.log`를 열지 못해 crash했으나, `--verbose --log-file /private/tmp/...`로 상세 attribution을 확보했다.
  - `test_boss_reward.gd` 단독 `4 resources still in use` 원인: `CombatEngine`이 `_mech`를 보유하고 `MechanicsHandler`가 `_e`로 engine을 다시 보유하는 RefCounted 순환. `CombatEngine.dispose()`와 `MechanicsHandler.dispose()`를 추가하고, `BattlePhase`, headless sim, combat/talisman/military/boss reward tests에서 호출하도록 정리했다.
  - `test_headless_runner.gd`/`test_headless_rewards.gd` 단독 `13 resources still in use` 원인: `HeadlessRunner.run()` 내부 `state.card_sold` 익명 signal callback이 `state`, `chain_engine`, `rng`, `self`를 캡처해 `state -> signal -> callback -> state` 순환을 만들었다. handler를 변수로 보관하고 return 전 disconnect한다.
- H-13 검증:
  - PASS `test_boss_reward.gd` 70/70, 종료 ObjectDB/resource 경고 없음.
  - PASS `test_combat_basics.gd` 15/15, `test_combat_advanced.gd` 15/15, `test_combat_integration.gd` 10/10, 종료 경고 없음.
  - PASS `test_combat_chain.gd` 9/9, `test_military_system.gd` 81/81, `test_talisman.gd` 38/38, 종료 경고 없음.
  - PASS `test_headless_runner.gd` 14/14 and `test_headless_rewards.gd` 17/17, 종료 경고 없음.
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1155/1155 across 51 scripts, no ObjectDB/resource exit block.
- H-14 완료: focused strategy payoff follow-up을 `soft_steampunk`로 진행했다.
  - Multi-review fallback 결정: 최신 fixed-evaluator 기준 최저 focused 전략이고, `docs/design/cards-steampunk.md`가 확산/집중 T1 분기와 hybrid penalty를 명시하므로 `soft_druid`보다 독립적인 다음 실험 축으로 적합하다고 판단했다.
  - 고정 evaluator: `godot --headless --log-file /private/tmp/godot_h14_140.log --path godot/ -s sim/ai_research/ai_batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json --trace-dir=/private/tmp/warforge_h14_trace_140`.
  - baseline 140-run: weighted 0.5064, AI quality 0.7378, `soft_steampunk` 3/20 avg_hp -5.6, `soft_druid` 4/20 avg_hp -7.95. Trace에서 `soft_steampunk`가 양쪽 T1 branch starter를 17/20 run에서 모두 구매했다.
  - 구현: `AIBuildPath`에 path-local `anti_penalty`를 추가하고 스팀펑크 spread/focus path만 36.0으로 설정했다. 드루이드/포식종 soft branch와 군대 strict branch는 기존 의미를 유지한다. 난이도, 카드 YAML, genome, evaluator는 수정하지 않았다.
  - 결과: 35-run weighted 0.4449→0.4599, `soft_steampunk` 0/5 avg_hp -16.6→1/5 avg_hp -6.6. 140-run weighted 0.5064→0.5095, AI quality 0.7378→0.7488, `soft_steampunk` avg_hp -5.6→-3.3, branch mixing 17/20→12/20. 승수는 3/20 유지라 완전 해결은 아님.
  - 상세 trace: `.claude/traces/experiments/011-steampunk-payoff-followup.md`.
  - 검증: PASS `test_ai_build_path.gd` 28/28, `test_ai_agent.gd` 14/14, `test_ai_board_eval.gd` 14/14, `test_headless_runner.gd` 14/14, PASS full GUT 1157/1157 across 51 scripts with no ObjectDB/resource exit block.
- H-15 완료: visual polish follow-up으로 chain/merge 피드백을 작게 보강했다.
  - `ChainVisual` 로그와 floating label에 `L->R`/`R->L`/`SELF` 흐름 힌트를 추가했다. 기존 카드명 `source -> target` 문구는 유지해 읽기와 회귀 호환을 보존했다.
  - 체인 라인은 살짝 굵게 시작해 줄어들고, floating label은 짧게 pulse 후 위로 drift/fade한다. 게임 로직/체인 엔진/카드 수치 변경은 없다.
  - `BuildPhase` merge summary label은 새 합성 기록 시 한 번 pulse한다. 트리에 없는 단위 테스트 인스턴스에서는 no-op이라 기존 merge bonus 테스트 구조를 유지한다.
  - 검증: PASS `test_chain_visual.gd` 6/6, PASS `test_build_phase_merge_bonus.gd` 6/6, PASS full GUT 1159/1159 across 51 scripts, PASS `git diff --check`.
- H-16 완료: 다음 hardening slice 선정 겸 `soft_steampunk` payoff timing probe를 수행했고, no-code-adopt로 닫았다.
  - Multi-review fallback 결정: H10-H15로 live reward/flow/visual polish는 한 바퀴 닫혔고, H14가 남긴 `soft_steampunk` T4/T5 timing은 fixed evaluator가 있으므로 작은 sim probe를 먼저 시도했다.
  - baseline 35-run: weighted 0.4599, `soft_steampunk` 1/5 avg_hp -6.6. Trace상 여러 run이 R8-R9까지 shop Lv2에 머물며 high-tier payoff 구매가 늦거나 없었다.
  - Variant A(R7+ reserve 8)는 levelup을 앞당겼지만 midgame survivability를 해쳐 weighted 0.4554, `soft_steampunk` 0/5 avg_hp -9.0으로 회귀해 REJECT.
  - Variant B(R9+ reserve 12)는 baseline과 같은 weighted 0.4599 / `soft_steampunk` 1/5로 no-op이라 REJECT.
  - 코드 변경은 남기지 않았다. 상세 trace: `.claude/traces/experiments/012-next-hardening-slice-probe.md`.
- 다음 착수 권장: 수동 플레이 관찰 기반 UX smoke 후보를 하나 찾거나, sim을 계속할 경우 levelup decision trace instrumentation / payoff-card valuation / transition-board replacement 중 하나를 fixed evaluator로 새로 선택한다.

## 2026-07-01 Codex autonomous update

- G-1 수집가 follow-up 완료: 첫 상점 refresh 1회에 한해 T2+ 카드 4장 이상 보장. UI 상점(`shop.gd`)과 headless sim 상점(`shop_logic.gd`) 모두 공통 `ShopPicker.apply_min_tier_guarantee` 경유.
- G-1 전략가 follow-up 완료: BuildPhase에 `SWAP (H)` 버튼/단축키 추가. 보드 카드 2장 좌클릭으로 교환하며 `Commander.hero_swap`가 `card_moved`/`board_changed`/`state_changed`를 방출.
- G-2 부적 선택 UI 1차 완료: 런 시작 시 `TalismanSelectPopup`에서 12종 부적을 선택하고 `GameState.talisman_type`에 반영.
- G-2 녹슨 렌치 UX 완료: BuildPhase에 `DETACH (D)` 버튼/단축키 추가. 업그레이드가 붙은 필드 카드를 선택해 마지막 업그레이드를 제거하고 50% 테라진을 환급.
- G-3 업그레이드 상점 UX 1차 완료: R1부터 커먼/레어 업그레이드 상점 표시, 테라진 구매→필드 카드 선택→즉시 부착 흐름 연결. `REROLL (T)` 버튼/단축키, 대상 취소 환불, 구매 불가 dim 상태 추가.
- G-4 런 시작 화면 1차 완료: `RunStartScreen`을 `main.tscn` 첫 화면으로 추가. `START RUN` 이후 해금된 커맨더/부적 선택으로 이어짐.
- G-4 메타 저장 1차 완료: `MetaProgress`가 `user://meta_progress.cfg`에 run stats, 초기 해금, 최대 난이도를 저장. 승리 시 다음 난이도를 해금하고, 런 시작 화면에서 해금 범위 안의 난이도를 선택 가능.
- G-4 난이도 전투/경제 1차 완료: `Difficulty` autoload 추가. live + headless sim 공통으로 D2 적 HP, D3 시작 골드, D4 적 유닛 수, D5/D7 보스 업그레이드, D6 상점/리롤 비용, D7 적 ATK, D8 플레이어 HP 적용.
- G-4 난이도 캘리브레이션 1차 완료: `difficulty_sweep_runner.gd` 추가. D3 시작 골드는 13→10 상대 페널티로 스케일 조정(현재 best genome 3g→2g). D4 적 수는 초기안 ×1.3이 clear 0% cliff를 만들어 ×1.15로 완화.
- G-4 업적 해금 1차 완료: 런 종료 시 필드 유닛, 장착 업그레이드, 필드 유니크 카드, 연승, 판매 수, 성장 이벤트, ★2+ 카드, 수적 우위 승리를 평가해 커맨더/부적을 해금.
- G-5 튜토리얼/온보딩 1차 완료: 런 시작 화면에 첫 런 가이드, 다음 해금 목표, 최근 해금 목록 표시. `tutorial_seen` 저장으로 첫 가이드는 `START RUN` 이후 접힘.
- 35-run sweep (`--runs=5`, 7 strategies, seed=42, best_genome): D1 28.6%, D2 25.7%, D3 22.9%, D4 5.7%, D5 0.0%, D6 5.7%, D7 0.0%, D8 0.0%. D5-D8은 표본 확대 후 추가 튜닝 권장.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_difficulty.gd -glog=1 -gexit` — 7/7
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_enemy_db.gd -glog=1 -gexit` — 18/18
  - PASS `godot --headless --path godot/ -s sim/difficulty_sweep_runner.gd -- --genome=res://sim/best_genome.json --runs=5 --seed=42` — completed 280 runs
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_shop_logic.gd -glog=1 -gexit` — 44/44
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_sim_shop_logic.gd -glog=1 -gexit` — 17/17
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit` — 36/36
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_strategist_swap.gd -glog=1 -gexit` — 6/6
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman_select_popup.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_talisman.gd -glog=1 -gexit` — 35/35
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_meta_progress.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_start_screen.gd -glog=1 -gexit` — 5/5
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_headless_runner.gd -glog=1 -gexit` — 10/10
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_rusty_wrench_detach.gd -glog=1 -gexit` — 3/3
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 4/4
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit` — 5/5
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `python3 -m unittest scripts.tests.test_lint_card_spawn` — 10 tests OK
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_card_pool.gd -glog=1 -gexit` — 17/17
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_combat_chain.gd -glog=1 -gexit` — 9/9
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_merge_system.gd -glog=1 -gexit` — 61/61
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_neutral_system.gd -glog=1 -gexit` — 57/57
  - PASS `git diff --check`
  - PASS full GUT `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit` — 1109/1109 across 48 scripts, no ignored test files. Godot still reports ObjectDB/resource warnings on exit.
- Verification-health follow-up 완료: `test_combat_chain.gd`, `test_merge_system.gd`, `test_neutral_system.gd` 수집 실패 해소. Neutral stale expectations were synced to current YAML/contracts (`ne_envoy` 1/2/4g, `ne_awakening` ★1 guard requires a matching common upgrade).
- G-1, G-2, G-3, G-4, and G-5 are now complete at playable prototype level. Next playable-run targets: detailed meta progression screen, richer upgrade comparison tooltips, or D5-D8 difficulty win-rate calibration.

## 2026-05-30 Codex restart update

- `fc90850` 에서 Codex용 meta-harness surface 커밋 완료.
- G-1 첫 조각 완료: 런 시작 시 `CommanderSelectPopup`에서 7종 커맨더를 선택하고 `GameState.commander_type`에 반영한 뒤 BuildPhase로 진입.
- 단조사 UX follow-up 완료: 일반 업그레이드 상점은 커맨더 시대 기준 R1부터 표시하고, 단조사 커먼 할인은 실제 표시 가격에 반영. 단조사 시작 보너스는 첫 빌드 확정 전 커먼 업그레이드 3택1 → 필드 카드 선택 → 무료 부착으로 동작.
- 2026-06-02 B-3 follow-up 완료: adaptive 드루이드 회피 원인을 AI 조기 테마 확정 + Druid producer/payoff scoring 부재로 진단하고 수정. adaptive Druid zero coverage 5장→2장, Druid theme coverage 0.1896→0.2468, weighted_score 0.4614(+0.0155 vs baseline). 상세: `.claude/traces/experiments/009-druid-ai-avoidance.md`.
- 추가 파일: `godot/scenes/ui/commander_select_popup.tscn`, `godot/scripts/ui/commander_select_popup.gd`, `godot/tests/test_commander_select_popup.gd`.
- 검증:
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander_select_popup.gd -glog=1 -gexit` — 2/2
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_commander.gd -glog=1 -gexit` — 35/35
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_shop_logic.gd -glog=1 -gexit` — 19/19
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_merge_bonus.gd -glog=1 -gexit` — 4/4
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_logic.gd -glog=1 -gexit` — 32/32
  - PASS `python3 scripts/lint_card_spawn.py`
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_theme_scorer.gd -glog=1 -gexit` — 11/11
  - PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ai_agent.gd -glog=1 -gexit` — 12/12
  - PASS `godot --headless --path godot/ -s sim/batch_runner.gd -- --genome=res://sim/best_genome.json --runs=20 --seed=42 --baseline=res://sim/baseline.json` — weighted_score 0.4614
  - Full GUT command exited 0 with 926 passing tests, but collection emitted pre-existing parse warnings for `test_combat_chain.gd`, `test_merge_system.gd`, and `test_neutral_system.gd`; those files were ignored by GUT and should be cleaned up in a separate verification-health pass.
- Remaining G-1 follow-up: 전략가 hero swap UI, 수집가 starting shop guarantee. Remaining AI follow-up: `soft_druid` win-rate is still 0/20 in the B-3 follow-up measurement.

# Prior Handoff — B-3 + B-4 완료 (2026-04-30, 2nd session)

## Status: ready

이번 세션은 **B-3 (카드 풀 활용도 분해) + B-4 (AI Layer 2 baseline 회복)** 까지 완료.
다음 세션은 **soft_X 5–10% 승률 회복** (S-2 / autoresearch) 또는 **드루이드 회피 진단** (B-3 follow-up) 부터 시작 가능.

## 이번 세션 변경사항 (커밋 2건)

| Commit | 내용 |
|--------|------|
| `1e19801` | docs(traces): B-3 카드 풀 활용도 분해 — theme lock 진단 |
| (pending) | chore(ai): ai_baseline.json 갱신 — Layer 1 동등 회복 (B-4) |

## 최종 상태

- **Layer 1 baseline**: 0.445902 (deterministic, B-7 fix 후)
- **Layer 2 AI baseline**: **0.4457** (B-4 완료 후 — 갭 0.0002, 사실상 동등)
- **AI quality**: 0.7730 (card_diversity 1.0, board_strength_curve 0.97, economy 0.67, merge 0.46)
- 카드 풀: 68장 확정. 0 dead, 19 weak, 49 active
- GUT 921/921 통과 (B-7 fix 이후 변경 없음)
- main 동기화 (33 commits ahead of origin/main, 미푸시)

## B-3 핵심 finding

### Evaluator card_coverage = 0.1896 의 진짜 원인
- **드루이드 테마** 가 병목 (0.1896, 다른 테마 0.23–0.28)
- **0장 dead** — 모든 68장이 5% 이상 등장
- 신규 13장 (0fd2d5e) 0 dead / 3 weak / 10 active. **풀 확장 직접 영향 가설 REJECT**
- 진짜 원인: **AI theme lock**
  - soft_X 4종이 자기 테마 외 21–26장을 안 산다
  - adaptive 마저 드루이드 5장 (`dr_deep`, `dr_origin`, `dr_resonance`, `dr_spore_cloud`, `dr_world`) 회피
  - economy 는 정반대 — 66/68 카드 구매 (풀 활용 양호)

### 0% 붕괴 원인 분리
- soft_steampunk: 풀 잠금 + 너프 누적 = 5%
- soft_druid: 풀 잠금 + AI 의 드루이드 시너지 평가 부재 가설 → 10%
- economy: 풀 활용 정상이지만 10% — **풀 문제 아님, 다른 메커니즘**

## B-4 핵심 finding

### baseline 16일 stale 발견
- 마지막 갱신: 2026-04-14 (`d745193`). 전략 이름 stale (`steampunk_focused` → `soft_steampunk` 미반영)
- 재측정 (20 run × 7 strategy, seed=42): **0.4457**
- 2회 측정 byte-identical → 결정성 확인됨

### 갭 해소 메커니즘 (자연스러운 회복)
- B-7 결정성 fix 직접 효과는 작음 (variance 0 ↔ 0.0075)
- **누적 효과 합산**: 군대 strict_anti, adaptive R1 가드, has_bench_space fix, 기타 4월 18~26 AI/sim 개선
- AI quality 0.69 → 0.77 (card_diversity max, board_strength_curve 0.97)

### 잔존 문제 (다음 세션 영역)
- **승률 분포 좁음**: 5–30% (max 30%, aggressive). Layer 1 의 σ < 0.10 목표 미달
- **soft_X 5–10%**: 풀 잠금 (B-3) + 카드 너프 (B-2) 합작
- **adaptive 드루이드 회피**: ai_agent.gd 평가 함수에서 드루이드 시너지 인식 부재 추정

## 다음 세션 진행 — 옵션 3가지

### 옵션 A. AI v2 의사결정 함수 검토 (B-3/B-4 follow-up)
**Why**: adaptive 가 드루이드 5장 회피 → 평가 함수에 드루이드 시너지 부재 가설 검증
**파일**: `godot/sim/ai_agent.gd` (`STRATEGY_NAMES`, theme bonus 로직), `ai_theme_scorer.gd`
**예상 hours**: 2–4시간
**완료 조건**: adaptive 가 드루이드 카드 회피하지 않음 (퍼-strategy zero-coverage 5장 → 0–2장)

### 옵션 B. autoresearch Layer 2 시도 (S-2 영역)
**Why**: B-4 baseline 회복으로 gradient 신호 정상화. 17개 ai_params 탐색 가능.
**명령**:
```bash
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=30 --strength=0.20 --runs=20
```
**예상 hours**: 2–6시간 (autoresearch 자체는 자율, 모니터링만)
**완료 조건**: weighted_score ≥ 0.50 (현재 0.4457) OR soft_druid 0% 탈출

### 옵션 C. UI 작업 (G-1 커맨더 선택, P1)
**Why**: sim 영역은 회복됨. UI 미완 5종 (G-1~5) 이 "런 1회 풀로 돌려본다" 의 진짜 병목.
**파일**: 새 scene + `commander.gd` UI 연결
**예상 hours**: 4–8시간 per scene

## 미해결 backlog (다음 세션 영역 외)

- **B-6**: stale baseline 감지 hook (P3, 별도 세션) — **본 세션이 16일 stale 의 2번째 사례**, 재발 검토 가치 있음
- **G-1~5**: UI 미완
- **S-1~3**: card_coverage 70% 추격, 전략 σ < 0.10, 평균 WR 압축
- **기술부채**: desc_gen multi-block listen 분리 (높음), sim ON_REROLL trigger (중)

상세는 `.claude/backlog.md` 참조.

## Next entry point

```bash
# 옵션 A 시작
cat godot/sim/ai_agent.gd | head -50
grep -n "druid\|theme" godot/sim/ai_theme_scorer.gd | head -20

# 옵션 B 시작 (autoresearch)
python3 godot/sim/ai_research/ai_autoresearch.py --iterations=30 --strength=0.20

# 옵션 C 시작 (UI)
ls godot/scenes/popups/   # 기존 popup 패턴 참조
```
