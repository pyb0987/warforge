# CP Formula Application — Handoff

> 작성: 2026-04-25. 후속 세션이 이 문서만 보고 이어갈 수 있는 self-contained handoff.
> 선행 세션의 결과 (테마 enemy 시스템 + 새 CP 공식) 을 코드 전체에 적용하는 작업.

## 0. 현재 상태 (이 핸드오프 시작 시점)

### 확정된 새 CP 공식

```
CP = 19.35 + (atk/as)^0.249 × hp^0.905
```

- 위치: [godot/sim/preset_generator.gd](../../godot/sim/preset_generator.gd) (canonical, GDScript)
- 미러: [scripts/preset_generator.py](../../scripts/preset_generator.py) (Python mirror, sim/analysis용)
- 함수: `PresetGenerator.unit_intrinsic_cp(unit_id, stat_mult=1.0) -> float`
- 검증: 5 독립 탐색 라인에서 최적 확정 ([trace](../../.claude/traces/experiments/002-cp-formula-theme-system.md))

### 새 enemy 시스템

- 4 abstract roles → **4 themed presets** (predator/druid/military/steampunk)
- 적 유닛은 [UnitDB](../../godot/core/data/unit_db.gd) 의 player pool 공유 (각 테마 10 유닛, 총 40)
- Recipe: 각 테마 10 유닛 동일 가중치 (0.10) — `THEME_RECIPES` in preset_generator
- `genome.enemy_stats`, `genome.enemy_composition` — **dead fields** (필드는 남았으나 런타임 미사용)

### 커밋 이력 (참고)
- `40e64ef` — Phase 1+2 core (theme system + parameterized formula)
- `a070b5b` — Option A (range/ms) + Option C (symbolic regression)
- `8e84d25` — Option D (additive form) — Phase 2 multiplicative 최종 확정

## 1. 작업 목표 (Sprint Contract)

```
Done when:
- [ ] CP 공식 단일원천 확정: scripts/analyze_card_cp.py 가 preset_generator를
      import하여 사용 (자체 공식 제거)
- [ ] 기타 CP 계산 위치 audit 완료 (찾으면 같이 SSoT로 통합)
- [ ] target_cp_per_round 재측정 + best_genome.json 갱신 (calibrate_target_cp.py)
- [ ] baseline.json 재생성 (autoresearch baseline)
- [ ] R4/R8/R12/R15 보스 라운드 난이도 수동 검증 (각 보스 vs 표준 빌드 5+ 게임)
- [ ] GUT 회귀 902/903+ pass

Evaluator: Tier 2 (haiku) + 체크리스트:
- preset_generator.unit_intrinsic_cp 가 유일한 CP 공식 (grep으로 확인)
- analyze_card_cp.py 의 출력이 preset_generator 호출과 일치
- target_cp_per_round 재측정 후 per-round survival ≈ target_wr_curve
- 보스 4개 모두 normal 라운드 대비 1.2~1.5× 난이도 (정성적)
- GUT 회귀 pass
```

## 2. CP 단일원천 통합 (필수)

### 2.1 발견된 별도 공식: `analyze_card_cp.py`

```python
# 현재 (OLD 공식)
cp = n * (atk / attack_speed) * hp

# 변경 (SSoT 사용)
from preset_generator import unit_intrinsic_cp
cp = sum(unit_intrinsic_cp(uid) * count for uid, count in card_units.items())
```

### 2.2 Audit 체크리스트

런타임 코드에 별도 CP 계산이 있는지 확인. grep 결과 (선행 세션 조사):
- `godot/core/data/enemy_db.gd` — `PresetGen.derive_comp` 사용 ✓ (SSoT)
- `godot/core/talisman.gd`, `card_instance.gd`, `chain_engine.gd`, `military_system.gd`,
  `steampunk_system.gd`, `predator_system.gd`, `combat_engine.gd`, `mechanics_handler.gd` —
  **CP 키워드 등장하지만 계산 아님** (atk/hp 직접 사용; 전투 로직). audit 필요.
- `godot/scripts/ui/card_tooltip.gd`, `card_visual.gd` — 카드 표시. CP 표시 시 통합 필요.
- `godot/sim/ai_board_evaluator.gd` — AI 평가용. 자체 heuristic일 수 있음.

**작업 순서**:
1. `analyze_card_cp.py` 부터 통합 (Python에서 import 가능)
2. UI 코드 (`card_tooltip.gd`, `card_visual.gd`) 의 CP 표시가 있다면 `PresetGenerator.unit_intrinsic_cp` 호출
3. AI evaluator 가 자체 CP 계산하면 SSoT로 통합 (단, 성능 영향 검증)
4. 각 .gd/.py 파일에 grep "atk.*hp\|hp.*atk" — 의심스러운 패턴 점검

## 3. target_cp_per_round 재측정

### 배경
- 새 CP 공식으로 unit별 가치가 달라짐 → 같은 target_cp 가 더/덜 어려운 라운드 의미
- `target_cp_per_round` (15 element array in genome) 은 **이전 공식** 기준으로 calibrate된 값

### 절차
```bash
# 현재 best_genome 백업
cp godot/sim/best_genome.json godot/sim/best_genome_pre_cp_recalibration.json

# Calibrate (calibrate_target_cp.py 사용; 권한: chmod +w 필요)
chmod +w godot/sim/best_genome.json
python3 godot/sim/calibrate_target_cp.py \
    --genome godot/sim/best_genome.json \
    --curve godot/sim/target_wr_curve.json \
    --output godot/sim/best_genome.json

# Baseline 재측정 (autoresearch baseline용)
chmod +w godot/sim/baseline.json
godot --headless --path godot/ -s res://sim/batch_runner.gd -- \
    --genome=res://sim/best_genome.json --output=res://sim/baseline.json
```

**검증**: 새 baseline 의 per-round WR 곡선이 `target_wr_curve.json` 의 anchor에
근접해야 함 (R5: 70%+, R8: 40-60%, R12: 20-40%, R15: 10-30%).

## 4. 보스 밸런스 검증

### 보스 라운드: R4, R8, R12, R15 (×1.3 boss_atk_mult 적용)

새 시스템에서 보스도 random preset 선택 (4 테마 중). 검증 방법:

**4.1 자동 측정**: 각 보스 라운드를 표준 빌드 (e.g., `aggressive` AI) 로 100회 시뮬:
```bash
godot --headless --path godot/ -s res://sim/headless_runner.gd -- \
    --strategy=aggressive --runs=100 --target_round=4
# R4, R8, R12, R15 각각 측정 → WR & avg HP loss 비교
```

**4.2 정량 기준**:
- R4 WR: 60-75% (초반 보스, 약간 도전적)
- R8 WR: 40-55% (중반 보스, 빌드 갖춘 시점)
- R12 WR: 25-40% (후반 보스, 결정적)
- R15 WR: 15-30% (최종 보스, 클리어 보상)

**4.3 정성 검증** (선택):
- 4 테마 × 4 보스 라운드 = 16 매트릭스 측정
- 어떤 테마가 어떤 라운드에서 비정상적으로 쉽거나 어려우면 표시
- 예: R4 druid 보스 = 너무 빨리 도착하는 강유닛 → 90% 패배 — 조정 필요

### Recipe 조정 (선택)
보스에서 특정 테마가 과도하게 강/약하면 [preset_generator THEME_RECIPES](../../godot/sim/preset_generator.gd) 의 가중치 조정. 현재 모두 0.10 균등.

## 5. 기존 AI/시스템 호환성 검증

### 영향 받을 가능성 있는 시스템
1. **autoresearch (target_cp용)**: `genome.enemy_composition`, `genome.enemy_stats` 를
   mutator로 변경하지만 더 이상 영향 없음 (dead fields). autoresearch.py 자체는 여전히
   다른 axes (economy/shop) 변경 가능 — 확인 필요.
2. **diagnostic_game.gd, side_bias_test.gd**: 옛 API 사용 — 컴파일 에러. 수정 또는 삭제.
3. **AI evaluator**: `ai_board_evaluator.gd` 가 player CP 평가 시 새 공식 반영 필요.

### Audit 명령
```bash
# 옛 API 호출 흔적
grep -rn "derive_comp.*genome.enemy_stats\|get_enemy_comp\|get_enemy_stat" \
    --include="*.gd" --include="*.py"

# Preset 이름 (옛 추상 role)
grep -rn '"swarm"\|"heavy"\|"sniper"\|"balanced"' \
    --include="*.gd" --include="*.py" | grep -v "test_\|cp_formula_research"
```

옛 preset 이름은 player card 효과(themed unit tags) 와 헷갈릴 수 있으므로 신중히 검토.

## 6. Genome 정리 (선택, 후속 작업)

`genome.enemy_stats`, `genome.enemy_composition` 필드는 dead. 제거 가능한 시점:
- 모든 best_genome.json 들이 새 시스템으로 재생성됨 (이번 handoff 완료 후)
- autoresearch가 더 이상 mutate하지 않음 확인

제거 시: [genome.gd](../../godot/sim/genome.gd) 의 해당 필드 + `validate()` 의 검증 로직 + JSON load 로직.

## 7. 알려진 이슈 (Phase 2 종료 시점)

- `test_headless_runner::test_cp_scale_affects_difficulty` — 1 balance test 실패 (902/903 pass).
  새 시스템에서 difficulty 가정 변경됨. target_cp 재측정 후 이 test도 통과 가능성 있음.
- `side_bias_test.gd`, `diagnostic_game.gd` — 옛 API. Phase 1 후 cleanup 안 했음.
- Military preset이 tier1-2에서 약함 (in-band 13/36 중 약 6셀 military 관련) — 디자인 의도로 수용.

## 8. 작업 순서 (권장)

1. **CP SSoT 통합** (1-2h)
   - `analyze_card_cp.py` 변경
   - UI/AI evaluator audit + 통합
2. **target_cp 재측정** (~30min)
   - calibrate_target_cp.py 실행
   - baseline.json 재생성
3. **GUT 회귀** (~5min)
   - 902+ pass 확인
4. **보스 측정** (~30min)
   - 100 runs × 4 보스 라운드
   - WR 정량 기준 비교
5. **불균형 시 조정** (~선택, 1h)
   - THEME_RECIPES 가중치 조정 또는 boss_scaling 변경
6. **커밋 + handoff 종료** (~10min)

총 예상: **2-4h** (음악 정량 audit 깊이에 따라 다름).

## 9. 관련 파일

**필수 읽기**:
- `.claude/traces/experiments/002-cp-formula-theme-system.md` — 5 탐색 라인 결과 + lessons
- `godot/sim/preset_generator.gd` — canonical CP formula + UNIT_STATS + THEME_RECIPES
- `godot/core/data/enemy_db.gd` — 새 generate() (테마 기반)
- `scripts/analyze_card_cp.py` — **변경 필요**
- `godot/sim/calibrate_target_cp.py` — 재측정 도구

**참고만**:
- `godot/sim/cp_formula_research/` — autoresearch 인프라 (변경 시 protect 해제 필요)
- `godot/sim/unit_tournament.gd` — 1v1 tournament (Option C 측정 도구)

**보스 관련**:
- `godot/core/data/enemy_db.gd::generate()` — boss_round 적용 위치 (`is_boss := round_num in [4, 8, 12, 15]`)
- `godot/sim/genome.gd` — `boss_scaling` 필드 (`{"atk_mult": 1.3, "hp_mult": 1.3}`)

## 10. 작업 종료 시 (handoff 완료)

- 본 문서를 `docs/episodes/2026-04-XX-cp-formula-applied.md` 로 이전하거나 archive
- evolution trace 신설: `.claude/traces/evolution/NNN-cp-formula-applied.md`
- 발생한 추가 이슈는 Phase 3 핸드오프 신설
