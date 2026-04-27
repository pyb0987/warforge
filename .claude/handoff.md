# Handoff — iter 22 완료 (fresh_ref + spawn_card funnel + 임계값 되돌림)

## Status: ready

작업 1 + 2 완료 (2026-04-26). 작업 1 = 합성 fresh 정책 + 단일 진입점 (P5 2.5단계). 작업 2 = dr_world unique mult 정책 = 현행 유지 (플레이테스트 검증).

## 최종 상태

- GUT **1017/1017 통과** (cache 재빌드 후)
- Lint 단위 테스트 10/10 통과
- pre-commit hook 활성 (`core.hooksPath = .githooks`, worktree config)
- Branch: `claude/quirky-leakey-843bab` (uncommitted)

## 이번 세션 변경사항

### 작업 1 — fresh_ref 합성 정책 + spawn_card 단일 진입점 (P5 2.5단계)

| 영역 | 변경 |
|---|---|
| `try_merge` | `fresh_ref: CardInstance = null`. 캐스케이드 fresh 전파는 로컬 `fresh_set: Array` |
| Survivor 선정 | 3-tier: 업그레이드 max → non-fresh 우선 → leftmost iteration |
| `absorb_donor` | `skip_units: bool = false` — fresh donor 유닛만 skip |
| `spawn_card` | 신규 카드 단일 진입점 (create + commander + bench + try_merge with fresh) |
| `add_clone` | 시스템 카드 경로 (auto-merge 미트리거) |
| 호출처 | shop.gd / shop_logic.gd → spawn_card. game_manager / headless_runner → add_clone |
| Lint | `scripts/lint_card_spawn.py` + 10 단위 테스트 + `.githooks/pre-commit` |

### 임계값 되돌림 (iter 21 3배 → 2배)

| 카드 | 항목 | 이전 (iter 21) | 현재 (iter 22) |
|---|---|---|---|
| dr_lifebeat | low_unit thresh | 2/6/18 | 2/**4**/**8** |
| dr_origin | low_unit thresh | 2/6/18 | 2/**4**/**8** |
| dr_deep | low_unit thresh | 2/6/18 | 2/**4**/**8** |
| dr_wrath | unit_cap | 3/9/27 | 3/**8**/**16** |

### 작업 2 — dr_world unique mult 정책 = 현행 유지

데이터: `scripts/analyze_dr_world_mult.py` (best 시나리오 144×, median 19×).
결정: 컨텐츠로 의도된 OP 구간, 플레이테스트로 검증 (옵션 D).

### Side fix

`add_specific_unit` + line 506 stack 추가 사이트의 `unique_*_mult` 키 누락 보강. iter 21에서 미처 갱신되지 않은 부분 (test_evaluator 노출).

## 신규 자료

- `.claude/traces/evolution/022-merge-fresh-policy-and-spawn-funnel.md`
- `.claude/traces/search-set.md` SS-009 등재 (card spawn 단일 진입점)
- `docs/episodes/2026-04-26-dr-world-mult-decision.md` (작업 2 결정)
- `scripts/lint_card_spawn.py` + `scripts/tests/test_lint_card_spawn.py`
- `scripts/analyze_dr_world_mult.py` (재현 가능 분석)
- `.githooks/pre-commit`

## 다음 세션 권장 순서

1. **커밋 + 머지**: 위 모든 변경사항을 단일 PR/커밋 시퀀스로 정리. iter 22 trace 참조하여 logical chunks로 분할 가능.
2. **플레이테스트 1회**: 새 fresh 정책 + 임계값 체감.
   - ★ 합성 시 마지막 산 카드의 유닛이 빠짐을 시각/수치로 확인
   - 드루이드 임계값(★2=4, ★3=8) 체감 — 합성 직후 즉시 발동되는지
   - dr_world ★3 빌드 도달 게임의 압도력 측정 (작업 2 검증)
3. **DESIGN.md / docs/design 동기화** (iter 22 변경 반영) — 별도 작업.

## 기술부채 / Dormant

- DESIGN.md / docs/design 미동기화 (iter 22).
- 다른 worktree/clone에서 `core.hooksPath = .githooks` 활성화 수동. README/setup 문서화 별도.
- dr_world unique mult — 플레이테스트 결과에 따라 cap 도입 검토.
- 이전 phase의 dormant 항목들 (retrigger 하드코드, _find_block first-match 등) 미해결 잔존.

## Next entry point

```
1. git status 확인 후 커밋 분할 (yaml/codegen, gd refactor, lint+hook, traces)
2. preset_parity_runner.gd 실행 → 회귀 영향 확인 (D/C 검증 유지)
3. 플레이테스트 1회 — 작업 1 + 2 통합 체감
```
