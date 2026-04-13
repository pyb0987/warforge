## Status: paused
## Last completed: 카드 효과 텍스트 전면 재작성 완료 (Phase 1~3)
## Current state:
- 기획문서 5개 (55장 × 3★ = 165개) ★별 독립 형식 재작성 완료
- 보스 보상 텍스트 27개 재작성 완료
- card_descs.gd 165개 전면 재작성 완료
- OBS-039 해결: ne_merchant star_overrides 추가 (card_db.gd)
- OBS-045 해결: card_tooltip.gd — card_descs 우선 + ★별 template 반영
- OBS-041 해결: keyword_glossary.gd 생성 (14키워드) + tooltip 호버 연동
- GUT 825/825 통과
- OBS 해결: 006, 010, 012, 015, 016, 018, 027, 028, 030, 031, 032, 037, 038, 039, 041, 043, 044, 045, 046
- 취소: OBS-001, 003, 004, 005, 007, 008, 014, 023, 036

## Remaining:

### 버그/검증 필요
- [ ] OBS-047 (S5-R14): ★3 캐스케이드 머지 시 중간 레어 업그레이드 미지급 의심 — GUT 테스트로 검증
- [x] OBS-049 (S5-R15): 카드 풀 고갈 메커니즘 구현 완료 (CardPool + ShopPicker 통합, T1=22/T2=18/T3=15/T4=13/T5=11)

### 밸런스/설계 결정 (플레이 데이터 축적 필요)
- [ ] OBS-013 (S1-R9): 드루이드 ★ 합성 시 유닛 상한 도달 패널티
- [ ] OBS-022 (S2-R8): 군대 ★2 도달 속도 < 게임 진행 속도
- [ ] OBS-029 (S3-R12): R11→R12 CP 점프 +42% 과도
- [ ] OBS-033 (S4-R2~R3): HP=30 초반 2패 → hp=15, 전략 여지 제한
- [ ] OBS-034 (S4-R6): 고티어 CP/gold ≈ 저티어 → 용병 가치 부재
- [ ] OBS-035 (S4-R7~R11): ★2 후 5연속 전멸 무풍지대
- [ ] OBS-042 (S5-R5): 보스 보상 밸런스 (영구 >> 즉시)
- [x] OBS-046 (S5-R12): "합성 보너스 2배" 텍스트 → boss-rewards.md에 구체적 수치 명시 (2026-04-11)
- [ ] OBS-048 (S5-R14): 세계수 ≤30 조건이 ★합성을 패널티화

### 게임 설계 (별도 설계 세션 필요)
- [x] OBS-017 (S2-R2): 🟢 방향 확정 — 자유 이동 유지 + 포지셔닝 퍼즐 심화 (인접 시너지 다양화·환경 효과). multi-review ×2회 (2026-04-11)
- [ ] OBS-025 (S2-R11): 후반 빌드 페이즈 빈 턴 반복 — 성장 체인이 잘 작동하면 문제 감소. 밸런싱 + 빌드 페이즈 자동 단축으로 접근 (2026-04-11 논의)

### AI 관련
- [ ] ai_build_path.gd → ai_agent.gd 연결 (plan: piped-jumping-unicorn.md)
- [ ] AI v3 (build path 연결) 후 genome 재탐색
- [ ] Tier B multiplicative 파라미터 — 비군대 CP 격차 해소
- [ ] starting_resources mutator 구현

## Next entry point: OBS-047 GUT 테스트 검증 또는 밸런스/설계 결정 세션

## OBS 검색
```bash
grep -n '🔴 open' docs/playtests/2026-04-*-session-analysis.md
```

## 참고 파일
- docs/playtests/2026-04-{08,09,10,11}-session-analysis.md — S1~S5 분석
- .claude/plans/card-desc-rewrite.md — 카드 텍스트 재작성 계획
- .claude/plans/piped-jumping-unicorn.md — AI build path 연결 계획
- godot/core/data/card_descs.gd — 현재 카드 설명 (165개)
- godot/scripts/ui/card_tooltip.gd — 툴팁 렌더링 (effects[] vs card_descs 분기)
