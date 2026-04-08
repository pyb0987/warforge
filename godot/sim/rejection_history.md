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
| (TBD)     | (TBD)                     | initial baseline |

## Rejection 로그
ADOPT/REJECT 결정 중 특이사항이 있는 경우 여기에 raw context를 보존한다.
(failures/ trace 기록 트리거에 해당하지 않는 noise-level reject는 생략)
