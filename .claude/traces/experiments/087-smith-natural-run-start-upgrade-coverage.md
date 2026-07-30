# 087 — Smith Natural-Run Start-Upgrade Coverage

Date: 2026-07-30

## Goal

Extend natural visible-control terminal coverage from initially unlocked
commanders to a locked special commander with extra setup flow.

## Context

H90 proved both initially unlocked commanders, Gambler and Breeder, can reach a
terminal overlay through the same visible-control playthrough path. Smith is a
good next identity because it has a distinctive start free-upgrade flow. Earlier
live-report work had already shown special commander free-upgrade modals can be
an integration risk; H91 verifies that the natural playthrough path survives the
real Smith flow.

## Change

Added `test_live_smith_visible_control_playthrough_resolves_start_upgrade` to
`test_game_manager_live_smoke.gd`.

The test:

- explicitly unlocks Smith in the isolated smoke profile;
- selects Smith through the commander popup;
- selects Flint through the talisman popup;
- plays through visible controls only;
- detects the Smith start upgrade by observing pending upgrade source
  `smith_start` and an attached-upgrade count increase;
- continues through real battles to the real terminal overlay.

The existing natural playthrough helper now returns small telemetry counters so
identity-specific assertions can be made without changing gameplay code.

## Evidence

Focused live smoke:

```text
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_game_manager_live_smoke.gd -glog=1 -gexit
```

Result:

```text
16/16 passed.
1131 asserts.
```

Observed Smith run:

```text
[Commander] Selected: 단조사
[UpgradeShop] 추진부스터 → 생명의 맥동 (-0t)
[Commander] 무료 업그레이드 적용: C5 (smith_start)
[Commander] 단조사 시작 보너스 적용
[Game] GAME OVER at round 8
```

Card-spawn guard:

```text
python3 scripts/lint_card_spawn.py
```

Result: exited 0 with no output.

Full GUT:

```text
/usr/bin/env HOME=/private/tmp/warforge_h91_fullgut_home godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit
```

Result:

```text
Scripts              57
Tests              1280
Passing Tests      1280
Asserts            9081
---- All tests passed! ----
```

Whitespace/conflict guard:

```text
git diff --check
```

Result: exited 0.

Protected simulator boundary:

```text
git status --short -- godot/sim
```

Result: no output.

## Decision

ADOPT.

Smith/Flint now has natural visible-control terminal coverage, including the
free start-upgrade modal and target-selection flow.

## Protected Boundary

No `godot/sim/**` files were edited. H78 remains gated on explicit protected
simulator approval.

## Next

Continue special-identity natural coverage only when it reduces a distinct
completion risk. Raider's real 3-win reward inside a natural terminal playthrough
is the most obvious unprotected follow-up. Protected H78 remains available only
after explicit simulator approval.
