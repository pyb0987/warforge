# 드루이드 집중 분석 — has_bench_space fix 이후 (2026-04-18)

Commit bd897f1 적용 후 20-run trace (seed=42). 드루이드만 WR 개선 없음(25%)의 원인 탐색.

## 구매/합성 단계: 정상화

| 지표 | 드루이드 | 포식종 (기준) |
|------|-----|-----|
| ★2 merges 총합 | 184 | 177 |
| ★3 merges | 1 | 3 |
| 테마 ★2 커버리지 | dr_lifebeat★2(26), dr_cradle★2(20), ..., dr_wt_root★2(1) | pr_nest★2(26), pr_farm★2(23), pr_apex_hunt★2(2) |
| 최종 보드 테마 카드 수 | 5.3 평균 | 6.1 평균 |

드루이드도 충분히 합성되고 카드를 채움. **구매 단계는 더 이상 병목 아님.**

## 전투 단계: R12+에서 무너짐

### 라운드별 WR (20 runs)

| 라운드 | 드루이드 | 포식종 |
|--------|-----|-----|
| R1–R7 | 95–100% | 100% |
| R8 (보스) | 75% | 95% |
| R9–R11 | 95–100% | 100% |
| **R12 (보스)** | **63%** | 95% |
| R13 | 81% | 100% |
| R14 | 86% | 95% |
| **R15** | **42%** | 85% |

### 패배 분포 (15 losing runs)

- R15 단일 패 (HP=30에서 패배): 7회 — 전까지 무손상이었는데 R15에서 돌연 패배.
- R12–R14 연패: 5회 — 보스 R12에서 시작해 연쇄 붕괴.
- R8 보스 패: 3회.

**해석**: 전반부는 드루이드도 강함. 후반 고CP 적에게 구조적으로 뒤짐.

## 가설

1. **Adjacency 미흡**: 드루이드 카드 다수가 인접 의존적 효과.
   - dr_lifebeat tree_shield `self_and_both_adj`
   - dr_origin tree_absorb `adj_druids`, tree_breed `adj_or_self`/`both_adj_or_self`
   - dr_earth tree_shield ★3 `all_druid`
   - 현재 `_THEME_ADJ_HINTS`에는 dr_cradle/dr_origin/dr_wt_root/dr_world만 등록. dr_lifebeat/dr_earth 누락.
2. **forest_depth 축적 느림**: ★2 합성 시점(R10+)부터 트리 축적. R12 보스까지 트리 수 부족 → dr_world multiply_stats 스케일 낮음.
3. **드루이드 카드 자체 combat 출력 약함**(E 영역 — 이 AI 레이어에서 해결 불가).

## 다음 단계 제안

**C (Position solver)가 1순위** — adjacency는 AI가 개선할 수 있는 영역이고, 드루이드 카드들이 가장 의존적.
- `_THEME_ADJ_HINTS`에 dr_lifebeat(both_adj), dr_earth(all_druid for ★3) 추가
- 또는 YAML target 자동 파싱으로 auto-derive (trace 014 revive scope 패턴)

**E (게임 밸런스)는 별도 세션** — AI 개선만으로는 R15 42% → 85%까지 끌어올리기 어려움. weighted_score autoresearch 필요.
