# Handoff — D + C 완료, 카드 풀 확장

## Status: paused

세션 마무리 (2026-04-25). 전투 시뮬 양대 결함 D/C 해결 + 카드 풀 13장 확장 + 평가/탐색 인프라 재설계 완료. 다음 세션 진입 전 검증/플레이테스트가 자연스러운 다음 단계.

## 최종 상태
- GUT 933/933 → 979/979 pass (병합 카드 도입 후, +71 tests this session)
- main 브랜치, 100+ commits ahead of origin
- C(CP formula) 병합 완료 (claude/frosty-lumiere-e9b9af → main)
- D(combat side bias) 병합 완료 (claude/wizardly-bassi-004ffa → main, simultaneous damage queue)
- 모든 Tier 0 protect 파일 chmod 444 복원 (best_genome.json, baseline.json)

## 이번 세션 주요 워크스트림 (chronological)

### 1. 두-step evaluator 재설계
- `target_wr_curve.json`: 4 anchor (R0/R4/R8/R12/R15 = 1.00/0.80/0.50/0.25/0.07) + 기하 보간
- `calibrate_target_cp.py`: 수학 + iterative calibration (segment tolerance, 3-iter moving avg, best-iter tracking)
- `calibration_runner.gd`: 경량 godot runner (evaluator 미호출)
- 평가축 9 → 8: `win_rate_band` + `emotional_arc` → `per_round_wr_match` (segment Gaussian)
- 자동탐색 내부 calibration loop (target_cp 변이 제거)

### 2. ml_factory rank 스케일링 재설계
- target rank → factory self rank (compound 폭증 차단)
- rate 원복 (0.02/0.03/0.05). 정체성 유지 + 상한 자연 형성
- doc 정량 수치 제거 (YAML SSOT)

### 3. D — Combat side bias 해결
- 원인: single-phase tick에서 team 1 먼저 이동 → team 0이 first-strike
- 1차(직접): 2-phase + interleaved iteration + pos snapshot → 100% → ~50% bias
- 2차(wizardly-bassi 병합): simultaneous damage queue → 완전 50/50 가능 영역
- 도구: `preset_parity_runner.gd`, `side_bias_test.gd`

### 4. C — CP formula 재설계 (frosty-lumiere 병합)
- theme-based enemy pool (preset → theme units)
- range/ms 항 추가 (multiplicative, symbolic regression validated)
- card_instance.gd / analyze_card_cp.py PresetGen SSoT 통합
- target_cp + baseline 재calibration
- boss_scaling.{atk_mult,hp_mult} → cp_mult (의미론 정합)

### 5. 보스 보상 정책
- 승리 시만 → 생존 시 (HP > 0). R8/R12 패배 후 후속 라운드 무력화 방지

### 6. 카드 풀 확장 (peaceful-cannon 6 phases)
- 신규 13장 (테마 4 + 중립 9)
- 코드 ~3500줄 (theme_system, neutral_system, chain_engine, codegen, tests, descs)
- multi-review 다단 검증 (Phase 3a/3b-1/3b-2a/3b-2b/4/6 각각)

### 7. 외부 워크스트림 (병렬, 이미 병합)
- 패배 데미지 라운드 배수 (R1=0.2 → R15=1.2)
- 합성 60기 cap + 회귀 테스트
- AI 전략 soft commit 재설계 (R1-R3 오픈, R4+ 테마 선호)
- T1↓ T4/T5↑ tier monotonic CP rebalance
- UI 툴팁 (태그별 강화 누적)

## 신규 자료

**핸드오프 / 계획**:
- `docs/design/combat-symmetry-handoff.md` (D, RESOLVED 헤더 추가됨, history 보존)
- `docs/design/unique-effect-plan.md` (보류, factory 자체-rank 변경으로 시급도 저하)
- `docs/episodes/2026-04-25-cp-formula-applied.md` (C 작업 archive)

**Trace**:
- `.claude/traces/failures/008-no-op-test-setup-lines.md`
- `.claude/traces/evolution/017,018,019-*.md` (CP formula evolution)
- `.claude/traces/experiments/002-cp-formula-theme-system.md`

**Memory (글로벌)**:
- `feedback_no_op_lines.md` (no-op setup line anti-pattern)
- `feedback_tdd_invariant_boundary.md` (외부 세션 추가)

## 사이드 이슈 (별도 task)
- **r12_6 보스 보상 버그** — 별도 task로 분리됨 (이 세션 범위 밖)

## 다음 세션 진입 시 권장 순서

1. **상태 검증**: `preset_parity_runner.gd` — C 효과 + D 잔여 (대각선 50/50, off-diagonal 30-70% 진입 여부)
   - ※ `side_bias_test.gd`는 da0ca88에서 삭제됨 (broken old-API). 대각선이 D 검증을 흡수.
2. **플레이테스트 1회** — 새 시스템 통합 체감
   - 새 13장 카드 등장
   - factory self-rank 스케일링
   - 보스 보상 생존 시 지급
   - 새 CP formula로 calibrated 난이도
3. **r12_6 spawn task** 진행 상태 확인 (별도 진행 중인지)

## 기술부채 / Dormant
- D side bias: simultaneous damage 후 잔여 검증 필요. 만약 50/50 미달이면 collision iteration 순서까지 검토.
- C off-diagonal: 새 formula 측정 결과에 따라 PRESET_RECIPES 재조정 가능성.
- `unique-effect-plan.md`: factory 외 다른 OP-stack 카드(ml_assault, sp_charger 등) 발견 시 활용.
- handoff.md 이전 phase의 dormant 항목들 (retrigger 하드코드, _find_block first-match 등) 미해결 잔존.

## Next entry point
다음 세션 첫 작업:
```
1. side_bias_test.gd 실행 → D 검증 결과 확인
2. preset_parity_runner.gd 실행 → C 검증 결과 확인  
3. 결과 따라:
   - 두 검증 모두 통과 → 플레이테스트 또는 새 작업
   - 미통과 → 잔여 편향 진단 (각 handoff §3-§4 참조)
```
