# Multi-Review: 코어 메카닉 완성도

- Date: 2026-03-23
- Decision: Growth Chain 설계(BFS queue + 2-layer event + 3-layer stat modifier)가 50카드 풀 설계를 시작하기에 충분히 완성되었는가?
- Verdict: **PASS (경계선)** (평균 7.0, 최저 7, veto 없음 — 3 Critic 모두 정확히 7)

## Critic Results

### C1: Systems Designer (Score: 7/10, concern)

- **retrigger 재귀가 safety cap 우회**: chain.py:149-153에서 _execute_effects 직접 재귀 호출. BFS safety counter(MAX_EVENTS=100)에 포함되지 않음. 인접한 두 retrigger 카드(sp_overload_s2 2장)가 무한 재귀 → Python stack overflow 가능
- **MAX_EVENTS=100 한계**: 8장 풀가동 시 (sp_factory_s2 all_allies 8이벤트 × ON_EVENT max_act 4 × 2차 cascade) 이론적 최대 ~100+. 50카드 고체인 조합에서 safety cap 조기 절단 가능
- **max_activations 강제 없음**: types.py:104에서 max_activations: int | None = None (기본 무제한). ON_EVENT 카드가 max_act 없이 생성되면 A-B-A 핑퐁 루프를 safety cap만으로 방어. 현재 14장은 모두 설정했으나 코드 레벨 강제 없음

**선행 수정 권장**:
1. retrigger에 depth 파라미터 추가 (depth > 3이면 skip) 또는 BFS 큐 경유로 구조 변경
2. MAX_EVENTS 동적 조정 (board_size × 25) + cap 도달 시 경고
3. ON_EVENT 카드에 max_activations 필수 검증 (CardTemplate 생성 시)

### C2: Archetype Builder (Score: 7/10, concern)

- **크로스 테마 시너지 경로 부족**: 14장 중 크로스 테마 브릿지는 떠돌이 무리(Layer1.UNIT_ADDED 반응) 1장뿐. 나머지 중립 카드는 자기 완결형. 2테마 하이브리드 빌드에 테마 내 최소 1장의 Layer 1 반응 카드 필요
- **미설계 3테마의 ★2 빌드 분기 불확실**: 드루이드(나무 토큰), 포식종(변태), 군대(계급 임계점)에서 ★2 "같은 일을 더 잘한다" 원칙이 흥미로운 빌드 분기를 만들 수 있는지 미검증. 포식종 변태의 ★2가 "소모 수 감소" vs "결과물 강화"에 따라 완전히 다른 빌드
- **배치 전략 불균등**: 스팀펑크는 6/8장이 타 카드 대상(right_adj, event_target, all_allies)으로 배치 순서가 전략적. 드루이드/포식종은 대부분 self-targeting이라 배치 순서가 형식에 머물 위험

### C3: Economy Analyst (Score: 7/10, concern)

- **파워 곡선 단조 감소**: strong 빌드가 R1부터 CP 비율 1.5-2.1×로 시작해 R15까지 감소만. 설계 목표("R9-R11에서 적이 더 강하다가 풀빌드로 역전")와 불일치. "시종 우세→끝에 밀림" 곡선
- **★2 지배 전략 가능성**: weak_s2 R10 CP 1.51×(★1의 1.09×에서 도약), strong_s2 R8 이후 2.5-2.9×. ★2가 "무조건 추구해야 하는 것"이 되어 경제적 텐션 약화
- **골드 경제는 건전**: 총 ~109g 중 카드(21g)+레벨업(31g)+★2(20g)=72g, 여유 37g의 배분이 결정의 핵심. 단, sim이 골드 지출을 모델링하지 않아 실제 텐션 미검증

## Synthesis

50카드 설계 시작 가능하나, 선행 조치 권장:

### 기술적 (C1)
1. retrigger 재귀 깊이 제한 추가
2. MAX_EVENTS 동적 조정
3. ON_EVENT max_activations 필수 검증

### 설계적 (C2 + C3)
4. 첫 번째 비스팀펑크 테마(드루이드) 9장 설계로 크로스 테마 시너지 검증
5. 적 파워 곡선을 비선형으로 변경 (R9-R11 스파이크) — "약→강" 아크 형성
6. ★2 비용 상향 또는 접근 조건 추가로 "무조건 추구" 방지
