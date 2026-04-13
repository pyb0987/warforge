---
name: autoresearch-v2
verdict: adopted
weighted_score_start: 0.5904
weighted_score_end: 0.6583
clear_rate: 5.7%
iterations_total: 55
adopts_total: 9
date: 2026-04-04
---

# Autoresearch v2 — AI v6 + Genome Optimization

## Scope
AI agent v6 (structural changes only) + 4-phase genome optimization.

## AI v6 Changes (from v5)
- Per-strategy `levelup_schedule` (steampunk/druid/predator: R7->ShopLv4, R9->ShopLv5)
- Per-strategy `capstone_cards` with urgency rerolls (+3 when ShopLv4+ and no capstone)
- `_has_any_card()` helper for capstone detection
- Prioritize levelup over buying in `_play_theme_focused()`

### v6 Scoring Changes (REVERTED)
Attempted but reverted (all made things worse):
- Stronger tier scoring for theme cards (T3:+5, T4:+10, T5:+15) — caused AI to stop buying
- Neutral penalty after R6 — reduced card count without better replacements
- T1 saturation penalty at 5+ board cards — same issue
- Aggressive board transition (sell T1 neutrals) — lost accumulated CP, died faster
- Reduced CP weight in card_value — disrupted sell decisions

**Key lesson**: AI scoring changes that penalize buying are counterproductive when the shop doesn't reliably offer better alternatives. The bottleneck is game balance (military 2x CP via TRAIN chain), not AI card selection.

## Phase Results

### Phase 1a: CP curve + Economy (15 iterations)
- 5 ADOPTs, 0.5904 -> 0.6244 (+5.8%)
- Economy mutation was most productive (+0.013 per ADOPT)

### Phase 3: Enemy Composition (15 iterations)
- 0 ADOPTs, enemy comp exhausted at this baseline
- Large mutations (0.40) caused massive regressions

### Phase 1b: CP curve + Economy (15 iterations)
- 2 ADOPTs, 0.6244 -> 0.6368 (+2.0%)

### Phase 2: Shop Tier Weights (15 iterations)
- 2 ADOPTs, 0.6368 -> 0.6583 (+3.4%)
- emotional_arc +0.078 was the biggest gain

### Phase 1c: CP curve + Economy fine-tuning (10 iterations)
- 0 ADOPTs, Phase 1 exhausted at this baseline

## Final State (0.6583)

| Axis | Score | vs v1 (0.595) |
|------|-------|---------------|
| board_utilization | 0.630 | +0.013 |
| activation_utilization | 0.976 | +0.008 |
| win_rate_band | 0.706 | +0.237 |
| tipping_point_quality | 0.800 | +0.229 |
| dominance_moment | 0.914 | +0.019 |
| theme_ratio_variance | 0.303 | -0.050 |
| card_coverage | 0.219 | +0.035 |
| emotional_arc | 0.706 | n/a (new) |

### Strategy Clear Rates
| Strategy | WR | avg HP |
|----------|-----|--------|
| aggressive | 10% | -11.4 |
| druid_focused | 0% | -6.1 |
| economy | 10% | -7.0 |
| hybrid | 10% | -2.4 |
| military_focused | 10% | -5.6 |
| predator_focused | 0% | -12.5 |
| steampunk_focused | 0% | -9.9 |
| **TOTAL** | **5.7%** | |

## Remaining Issues
- druid/predator/steampunk still 0% clear rate
- theme_ratio_variance 0.303 (low — strategy diversity is poor)
- card_coverage 0.219 (still low)
- Military dominance reduced (10% vs v1's 30%) but others haven't caught up

## Next Steps
- AI v7: address why druid/steampunk/predator TRAIN-like scaling doesn't compound
- Consider card effect tuning (currently forbidden by program.md)
- More autoresearch iterations with larger sample sizes
