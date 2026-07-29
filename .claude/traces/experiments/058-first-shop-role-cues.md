# 058 - First-Shop Role Cues

Date: 2026-07-29
Slice: H62

## Context

H61 made the first BUILD surface say what to do next, usually to buy from
SHOP. The next player question is which shop card is worth buying. Difficulty
and economy tuning remain intentionally paused.

## Advisory Multi-Review

Decision: choose the next small development slice after H61.

- First-3-minutes UX critic: score 9, advisory pass for first-shop role cues.
  Frame challenge: after readiness clarity, the player is answering "which shop
  card helps my chain/combat/economy plan?", not yet enemy pressure or roadmap.
- Engineering verification critic: score 8, advisory pass for a compact
  shop-only role line derived from CardDB timing/action data and verified by
  live UI report snapshots.
- Product sequencing critic: score 9, advisory pass for compounding the
  H58-H61 onboarding arc without touching paused balance/economy work.

Integrated decision: implement a compact shop-card face cue now. Defer enemy
preview and run roadmap until first-shop purchase literacy is legible.

## Implementation

- Added `RoleLabel` to `card_visual.tscn`.
- `card_visual.gd` now derives a shop-only face role line from the
  representative structured effect block:
  - timing examples: `시작`, `반응`, `전투`, `패배`, `리롤`, `합성`, `판매`;
  - mechanic examples: `유닛+`, `강화`, `경제`, `보호`, `화력`, `전환`, `연결`.
- Existing detailed card rules remain in tooltips; no card data or balance
  values changed.
- `LiveUiProbe` exports `shop.card_offer_roles` with slot, card id, name,
  tier text, role text, visible state, and rect.
- `live_ui_smoke_report.gd` records `events.shop_role_cues` at initial and
  post-unlock BUILD entry and fails if any non-empty offer lacks a visible role
  cue.
- `summarize_live_ui_report.py` validates the rendered role summaries and adds
  `First-shop role cues rendered: ...` to the Markdown summary.
- `docs/tools/live-ui-smoke-report.md` documents the role-cue contract.

## Verification

- PASS `python3 -m unittest scripts.tests.test_summarize_live_ui_report`
  - 24 tests.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_build_phase_upgrade_shop.gd -glog=1 -gexit`
  - 16 tests, 101 asserts.
- PASS `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit`
  - 12 tests, 580 asserts.
- PASS headless live UI report:
  - `godot --headless --log-file /private/tmp/warforge_live_ui_smoke_h62.log --path godot/ res://tools/live_ui_smoke_report.tscn -- --out=/private/tmp/warforge_live_ui_smoke_h62.json --commander=gambler --talisman=flint`
- PASS summary:
  - `python3 scripts/summarize_live_ui_report.py --report=/private/tmp/warforge_live_ui_smoke_h62.json --out=/private/tmp/warforge_live_ui_smoke_h62_summary.md`
  - Summary includes `First-shop role cues rendered: ...` with visible examples
    such as `증기 조립소=시작 · 유닛+`, `방랑 상인=패배 · 경제`, and
    `생명의 맥동=전투 · 보호`.
- PASS `python3 scripts/lint_card_spawn.py`.
- PASS `python3 -m unittest discover -s scripts/tests`
  - 105 tests.
- PASS `git diff --check`.
- PASS exact merge-marker scan:
  - `rg -n "^(<{7}|>{7}|={7})( |$)" . --glob '!godot/.godot/**' --glob '!*.import'`
  - exit 1 with no output, meaning no matches.
- PASS full GUT:
  - 57 scripts, 1259 tests, 8348 asserts.

## Outcome

Adopted. The first shop now gives each visible card offer a short, structured
role cue before purchase, so H61's "buy a card" next-action hint leads into a
more informed first decision instead of a blind click.

## Deferred

- Enemy/battle preview remains a strong next candidate after shop choice is
  legible.
- A compact run roadmap/reward cadence remains useful later, but it is broader
  than this first-shop literacy slice.
- Role taxonomy may need design polish after more manual play, but it is now
  generated from structured effect blocks rather than hand-authored per card.
