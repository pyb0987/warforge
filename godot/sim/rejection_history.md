# Autoresearch — 탐색 이력 (Agent-writable)

이 파일은 autoresearch agent가 갱신하는 append-only 로그다.
연구 목표 / Genome 변수 정의 / 평가 시스템 등 immutable한 항목은 `program.md`를 본다 (보호됨).

---

## AI 행동 변경 이력 (genome과 무관)
- **v1**: 기본 구매 로직 (off-theme -15)
- **v2 (현재)**: off-theme -20, foundation reroll +5, _count_theme_cards 헬퍼 추가
- best_genome은 반드시 현재 AI 버전에 맞게 재탐색해야 함 (v1 genome은 v2에 부적합)

## Genome 탐색 이력
- **v2 Phase 1**: 0.3661→0.5662 (CP curve + economy). CP curve가 dominant lever.
- **v2 Phase 4**: 0.5662→0.5777 (activation_caps + boss_scaling). 미약.
- **v2 Phase 2**: 소진 (shop_tiers 0 ADOPT/5).
- **v2 Phase 3**: 소진 (enemy_comp 0 ADOPT/5, 매우 불안정).
- **v2 Phase 1 fine**: 0.5777→0.5929 (economy 미세조정).
- **결론**: genome 공간 ceiling ~0.59. DR/ST/AG 0% 문제는 AI 행동(build path) 개선 필요.

## Phase 별 default_genome.json 스냅샷
`default_genome.json`은 mutation seed이자 phase 간 reproducibility anchor. Phase 종료 시 이 섹션에 SHA-256과 변경 사유를 기록한다. Phase 도중 수정 금지.

| Phase 종료 | default_genome.json sha256 | 변경 사유 |
|-----------|---------------------------|----------|
| Phase 1 시작 (2026-04-18) | 60dec1fbfd8ad67f202d7f2d79ac876aea0b2c09e186ee1c59832ba4c4fe4bc3 | initial baseline. baseline.json v2 재촬영 완료 (weighted_score 0.4458, mean WR 67.9%). AI drift 수정 8건 반영: has_bench_space(bd897f1), position_solver 확장(260a93c), adaptive R1 가드(fb8263c), 군대 strict_anti(0649f10) + cross-chain(05dd53e), 군대 재설계 반영 4건, 드루이드 drift(5807f83). |
| Phase 1 재시작 (2026-04-18 v3) | 60dec1fbfd8ad67f202d7f2d79ac876aea0b2c09e186ee1c59832ba4c4fe4bc3 | evaluator WIN_RATE_SIGMA 0.05→0.25 교정. failures/002 2회 재발: v2 Phase 1 iter1 배치에서 CP +40% 변이에도 win_rate_band=0 불변. 관측 WR 76%이 타겟 7.5%에서 68.9%p 떨어져 exp(−94.9)≈1e−41 → 실질 cliff. σ 확대로 gradient 복원 (관측 span 커버 원칙). baseline v3 weighted_score 0.4560, win_rate_band 0.0131. iter1 ADOPTed CP curve는 best_genome.json에 유지 (비목표 축 개선도 실효적). |

## Rejection 로그
ADOPT/REJECT 결정 중 특이사항이 있는 경우 여기에 raw context를 보존한다.
(failures/ trace 기록 트리거에 해당하지 않는 noise-level reject는 생략)
