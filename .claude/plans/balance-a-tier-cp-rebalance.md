# 핸드오프 — A: 티어별 base CP 재조정

**작성일**: 2026-04-20
**선행 세션**: Phase 1 autoresearch + 플레이테스트 피드백 1회차

## 배경

플레이테스트 결과 **T4/T5 카드가 T1 ★3 빌드에 밀림** 확증. 원인 조사 결과 **T4/T5의 base CP가 T1보다 오히려 낮거나 비슷**.

### 수치 증거

| 카드 | 티어 | base CP (ATK/AS × HP) |
|---|:-:|:-:|
| **sp_workshop** | T1 | **1287** |
| **dr_cradle** | T1 | **1200** |
| dr_lifebeat | T1 | 1100 |
| sp_assembly | T1 | 980 |
| sp_furnace | T1 | 393 |
| **T1 평균** | — | **658** |
| ml_command (통합사령부) | T5 | 1050 |
| dr_wrath (태고의 분노) | T4 | 913 |
| sp_arsenal (제국병기창) | T5 | 830 |
| **T5 평균** | — | **784** |
| **T4 평균** | — | **575** ⚠️ (T1보다 낮음!) |
| ml_factory (군수공장) | T4 | 453 |
| pr_apex_hunt | T4 | 360 |

## 목표

- **T1 base CP 평균 658 → ~500로 하향**
- **T2/T3/T4/T5 순차 상승 곡선** 만들기
- 제안 목표선:
  - T1: ~500
  - T2: ~700
  - T3: ~900
  - T4: ~1200
  - T5: ~1600

## 작업 범위

### 1. 전체 카드 base CP 산정 스크립트 작성
`scripts/analyze_card_cp.py` — 모든 55장 카드의 base CP 출력 (T1/T2/T3/T4/T5 평균)

### 2. 카드별 유닛 구성 (comp) 재조정
YAML 파일의 `comp` 섹션 수정:
- T1 카드: 유닛 수 감소 or 약한 유닛으로 대체
- T4/T5 카드: 강한 유닛 or 유닛 수 증가

### 3. 유닛 스탯 조정 검토
유닛 자체 stat 변경은 여러 카드에 영향 → 카드별 comp 변경이 우선

### 4. 재생성 + 검증
- `python3 scripts/codegen_card_db.py`
- GUT 테스트 902건 유지
- sim baseline 재촬영 (WR 분포 변화 확인)

## 주의사항

### ★ 합성 보너스 (예상 외 발견)
`game_state.gd:247` — **★1→★2 합성 시 ATK/HP ×1.30 자동 적용** (`multiply_stats(0.30)`).
사용자 **의도 외**임이 확인됨. 이 세션 또는 Session B에서 처리 검토.
- 제거하면 ★2/★3의 매력이 effect 변화로만 정당화되어야 함
- 현 effect 증가분이 부족할 경우 추가 balance 필요

### 설계 문서 동기화
- `docs/design/cards-*.md` 각 테마별 업데이트
- DESIGN.md 변경 영향 맵 확인

## 검증 기준

- T1 avg CP ≤ 600
- T4 avg CP ≥ 1100, T5 avg CP ≥ 1500
- GUT 902/902 pass
- sim 60-run baseline:
  - mean WR target 5-10% 범위 유지
  - card_coverage 증가 (T4/T5 등장 빈도↑)

## Next entry point

1. `scripts/analyze_card_cp.py` 작성 → 전체 카드 현황 덤프
2. 설계 목표 곡선 확정 (사용자 승인 필요)
3. YAML 카드별 comp 조정
4. codegen + 테스트 + sim 재측정
