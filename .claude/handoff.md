## Status: paused
## Last completed: Phase 1 autoresearch + AI 튜닝 실험 일단락 (2026-04-19)

## Current state:

### Phase 1 최종 결과 (committed)
- **weighted_score 0.5411** (초기 0.4458 대비 +21%)
- 최신 커밋: [3dce300] failures/007
- Tier 0 파일 모두 chmod 444

### best_genome.json (Preset A)
- cp_curve: [0.69, 0.80, 1.44, 3.30, 3.63, 3.99, 4.82, 5.30, 5.83, 10.06, 11.91, 14.58, 23.68, 30.40, 35.61]
  - R15/R1 = 51.3× 복리 성장 (SC tavern 130× 레퍼런스 ~40%)
  - Mutator B (geometric, ratio floor 1.1)
- base_income: [5,5,5,5,5, 6,6,6,6,6, 7,7,7,7,7] (Preset A)
- levelup_cost: {2:7, 3:8, 4:9, 5:10, 6:11}
- max_interest: 4

### 전략별 60-run WR
- aggressive 6.67% (4/60) — 최고, target band 진입
- adaptive 5.00%, soft_predator 5.00%
- economy 1.67%, soft_druid 1.67%, soft_military 1.67%
- **soft_steampunk 0/60** — 구조적 문제 (failures/007 참조)

### 진단된 미해결 이슈
1. **soft_steampunk 0% WR**
   - 원인: T4/T5 카드 구조적 미접근 (60 runs에서 sp_T4 1장, sp_T5 0장)
   - AI build_path 자체는 올바름, shop tier weights + economy 구조 문제
   - AI 파라미터 튜닝 3회 시도 모두 실패 (failures/007)
   - **사용자 메모**: steampunk 전략의 카드 해석 로직 재점검 필요
2. **mean WR 2-3%** vs target 7.5% — Phase 1 단일 레버로는 gap 못 채움

## Remaining:

### 다음 세션 계획 (사용자 지시)
- [ ] **사용자 플레이테스트** — 현 best_genome.json으로 직접 플레이
  - 실행: `godot --path godot/` 또는 Godot 에디터에서 프로젝트 열기
  - game_manager.gd:37이 res://sim/best_genome.json 자동 로드
  - R15 CP=35.61 (default 4.5 대비 ~8x) 상당히 어려움
  - 관찰 포인트: 어디서 막히는가, 빌드 완성도, AI 대비 체감 gap
- [ ] 플레이 후 결정:
  - soft_steampunk 카드 해석 이슈 분석 + 재설계
  - Phase 2 (shop tier weights) 진입 여부
  - 다른 방향 (CP 재튜닝, AI build_path 심층 개선)

### 이 세션에서 폐기된 경로
- A (off_theme_penalty 20→12): military regression → revert
- B (pressure-aware dynamic penalty): 전면 regression → revert
- Preset B (base_income 6/7/8): SP +1이지만 타 전략 −6 → revert
- 결론: AI 휴리스틱 단일 튜닝은 전략간 비대칭 → 모두 실패

## Next entry point

**옵션 A (추천): 플레이테스트 결과 수집**
- 사용자 직접 R1-R15 플레이
- 테마별 빌드 시도: steampunk 집중 / 혼합 / 기타
- AI의 0-7% WR이 인간 대비 얼마나 낮은지 체감
- steampunk 카드 해석 이슈의 구체 사례 관찰

**옵션 B (플레이테스트 후): Phase 2 진입**
- Shop tier weights 탐색 (card_coverage 0.177 → 0.70 목표)

**옵션 C: steampunk AI 카드 해석 재설계**
- 플레이테스트로 확인된 이슈를 근거로 ai_build_path + ai_synergy_data 수정

## 주요 참조 파일

### Phase 1 인프라
- godot/sim/program.md — 탐색 공간 정의 (chmod 444)
- godot/sim/genome_bounds.json — bound single source (chmod 444)
- godot/sim/evaluator.gd — 비대칭 σ (0.07/0.15)
- godot/sim/autoresearch.py — mutator B + preset toggle (Tier 0)
- godot/sim/best_genome.json — 최적 genome (chmod 444)

### 실패 기록
- .claude/traces/failures/002 — evaluator σ 3회 재발 history
- .claude/traces/failures/007 — AI 휴리스틱 단일 상수 튜닝 실패

### 플레이테스트 관련
- godot/scripts/game/game_manager.gd:37 — best_genome.json 로드
- godot/core/data/enemy_db.gd:45 — CP curve 사용
