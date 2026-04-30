---
date: "2026-04-30"
verdict: adopted
trigger: "B-7 sim 비결정성 진단 (B-5 부작용 발견)"
---

# Evolution 023 — combat_engine RNG 결정성 복원

## Context

B-5 (baseline.json 갱신) 진행 중 부작용 발견: `--seed=42 --runs=10` 동일 호출에서 weighted_score 가 8회 측정에 stdev 0.0075, range 0.0197 변동.

이는 autoresearch ADOPT 판정의 typical delta (+0.005~0.01) 와 동급 noise. 모든 ADOPT 판정의 신뢰성에 영향.

## Diagnosis

`grep -rn "\b(randf|randi|randomize)\(" godot/combat/` 로 전수조사:
- `combat_engine.gd:475` — unit overlap 시 separation jitter 에 글로벌 `randf()` 호출
- `mechanics_handler.gd:150` — critical hit chance 판정에 글로벌 `randf()` 호출

두 위치 모두 Godot 글로벌 RNG 사용 — `chain_engine.set_seed()` 등으로 sim 이 시드를 주입해도 combat 경로는 무관.

**검증**: combat_engine 전체에 `_rng` 또는 RandomNumberGenerator 인스턴스 부재. 글로벌 `randf()` 만 사용.

## Change (Surgical)

| 파일 | 변경 |
|------|------|
| `combat_engine.gd` | `_rng := RandomNumberGenerator.new()` 추가, `_init()` 에서 `randomize()` (UI 기본 동작 유지), `set_seed(s: int)` 메서드 추가, line 475 `randf()` → `_rng.randf()` |
| `mechanics_handler.gd` | line 150 `randf()` → `_e._rng.randf()` |
| `headless_runner.gd` | `engine.setup()` 직전에 `engine.set_seed(_seed + round_num * 100003)` 호출 |
| `unit_tournament.gd` | `engine.set_seed(seed_val)` 호출 |
| `preset_parity_runner.gd` | `engine.set_seed(seed_val + 750000)` 호출 |

UI 경로 (`game_manager.gd` 의 CombatEngine 사용처) 는 변경 없음. `_init()` 의 `randomize()` 가 기존 비-deterministic crit 동작 유지.

## Verification

```bash
# 5회 동일 seed 측정
for i in 1..5: godot ... --seed=42 --runs=10
→ 모든 run: weighted_score = 0.445902 (variance 0)

# GUT
→ 921 tests passing
```

## Effect

- **autoresearch ADOPT 판정 신뢰성 복원**: noise floor 0 → ADOPT delta 가 모두 진짜 신호
- **baseline.json 결정성**: 0.4491 (noisy) → 0.445902 (deterministic)
- **B-3 (카드별 등장 빈도) 의 측정 신뢰성**: 이전엔 noise 위 측정이라 의심됐으나 이제 의미 있는 분포 측정 가능

## Rollback Plan

각 파일의 set_seed 호출 + `_rng.randf()` 변경 revert. 글로벌 `randf()` 로 복귀하면 비결정성 재발.

## Lesson

**Hidden global state 위험**: 글로벌 `randf()` 는 seed 인자 없이 동작 — 코드 리뷰에서 "global randf() 금지" 규칙 필요. 향후 P5 사다리 검토:
- 린터 규칙: `randf()|randi()|randomize()` 직접 호출 금지 (모두 instance 메서드만)
- `traces/search-set.md` 에 SS-XXX 추가 (combat 경로의 seed 일관성 검증)
