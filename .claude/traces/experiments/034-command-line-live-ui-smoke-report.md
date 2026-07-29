# Episode 034: Command-line live UI smoke report

## Context

H37 introduced a small live UI observer/driver helper for the existing
`GameManager` smoke tests. Its carry-over recommended promoting that shared
observer vocabulary into a bounded command-line report so manual playtest
observations can be reproduced and archived.

## Gap

Before H38:

- "Play it yourself and tell me what you see" depended on ad hoc GUT output or
  manual inspection.
- The live observer lived under `res://tests/`, which made reuse from tools
  awkward.
- There was no JSON artifact that recorded the visible UI owner/actionability
  state across run start, merge rewards, and boss rewards.
- The live smoke checked modal flow, but did not assert that the BUILD surface
  was clean after reward settlement.

## Change

Moved the live UI observer/driver to `res://tools/live_ui_probe.gd` and updated
the live smoke tests to preload that production-adjacent helper.

Added `res://tools/live_ui_smoke_report.gd` plus
`res://tools/live_ui_smoke_report.tscn`. The scene runner emits a JSON report
for a short scripted path:

- start run;
- select commander;
- select talisman;
- reach R1 BUILD;
- buy/merge three copies to trigger a merge reward;
- select the first upgrade reward through `UpgradeChoicePopup`;
- reach R4 boss reward;
- select the first no-target boss reward through `BossRewardPopup`;
- verify the R5 BUILD surface is clean.

The report includes:

- schema version;
- selected commander/talisman;
- `ok` and `errors`;
- step-by-step snapshots;
- merge reward details;
- boss reward details;
- final phase/round/surface snapshot.

The first scene-run report exposed a real UI cleanup issue: after R4 boss reward
settlement entered BUILD, `chain_visual.visible` could remain true with stale
chain feedback. Fixed `GameManager` so entering BUILD hides the chain visual
after clearing links, and removed the redundant settlement-side show call.

Documented the tool in `docs/tools/live-ui-smoke-report.md`.

## Implementation Notes

Direct `-s` script execution was rejected for this tool because Godot custom
scripts run that way did not resolve project autoload identifiers in this repo.
The report now runs as a project scene:

```text
godot --headless --log-file /private/tmp/warforge_h38_live_ui_report_v2.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h38_live_ui_report_v2.json --commander=gambler --talisman=flint
```

Use `--out` for parseable JSON because normal `GameManager` logs still print to
stdout/stderr during scene execution.

## Verification

Report:

```text
PASS godot --headless --log-file /private/tmp/warforge_h38_live_ui_report_v2.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_h38_live_ui_report_v2.json --commander=gambler --talisman=flint
  ok=true; steps=9; final=BUILD R5; final.chain_visible=false

PASS python3 -c 'import json; p="/private/tmp/warforge_h38_live_ui_report_v2.json"; d=json.load(open(p)); assert d["ok"] is True; assert d["final"]["phase"] == "BUILD"; assert d["final"]["round"] == 5; assert d["final"]["chain_visible"] is False; assert d["events"]["merge_reward"]["attached"] is True; print("ok", len(d["steps"]))'
  ok 9
```

Focused:

```text
PASS godot --headless --log-file /private/tmp/warforge_h38_live_smoke.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
  9/9; 243 asserts

PASS godot --headless --log-file /private/tmp/warforge_h38_chain_visual.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_chain_visual.gd -glog=1 -gexit
  6/6

PASS godot --headless --log-file /private/tmp/warforge_h38_boss_reward_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_boss_reward_popup.gd -glog=1 -gexit
  2/2

PASS godot --headless --log-file /private/tmp/warforge_h38_upgrade_choice_popup.log --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_upgrade_choice_popup.gd -glog=1 -gexit
  2/2

PASS git diff --check
```

Full:

```text
PASS godot --headless --log-file /private/tmp/warforge_h38_full_gut.log --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
  1221/1221; 7792 asserts
```

## Decision

Keep the H38 change.

Reason:

- It creates a durable observability artifact for the playable UI path.
- It converts the previous observer helper into a reusable tool surface without
  introducing broad autoplay architecture.
- It found and fixed a real live UI cleanup bug.
- Focused and full verification pass.

Carry-over:

- The next plausible completion slice is to make the live smoke report cover one
  targeted-choice gate, because current report coverage only proves no-target
  boss rewards and merge upgrade rewards.
- A later slice can add screenshot/canvas evidence once semantic UI ownership is
  broader.
