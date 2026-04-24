---
date: "2026-04-23"
classification: "제약 미비"
escalated_to: "memory/feedback_no_op_lines.md"
search_set_id: null
resolved: true
resolved_date: "2026-04-23"
escalation_date: "2026-04-23"
promoted_to_feedback: "feedback_no_op_lines.md"
---

## Failure: 테스트 setup에 결과 불변인 라인을 넣고 주석으로 "무시됨" 선언

### Observation

ml_factory scaling 기준을 target_rank → factory_rank로 전환할 때, 테스트를 factory-rank 의미로 재작성.
이 과정에서 다음 패턴 반복 삽입:

```gdscript
var target: CardInstance = CardInstance.create("ml_barracks")
target.theme_state["rank"] = 7  # target rank은 무관 (무시되어야 함)
```

- 라인 존재 여부가 assertion 결과에 **영향을 주지 않음** (factory-rank 기반 로직으로 전환됨)
- 그럼에도 라인을 두고 주석으로 "무시됨"을 선언
- 동일 패턴 6개소 발견: 신규 편집 2개 + 기존 leftover 3개 + 의미 전환된 테스트 1개

사용자 직접 지적 (2026-04-23):
> "target.theme_state["rank"] = 7  # target rank은 무관 (무시되어야 함) <- 이런 종류의 코드는 왜 있어야합니까?"
> "있거나 없어도 무관한 종류의 코드가 추가되는 이유가 무엇인가요?"

### Root Cause

세 가지 실패가 겹침:

1. **Pattern mimicry**: 기존 테스트가 `factory + target + 양쪽 rank 설정` shape이었고, 로직 재작성 시 shape을 답습함 (뇌가 "신규 작성"이 아닌 "기존 수정" 모드로 작동)
2. **방어적 주석**: 라인이 쓸모없음을 알면서도 지우지 않고 "무시됨" 주석으로 변명. 주석이 "왜 있어?"에 답하는 순간 그 라인은 지울 후보였음
3. **Diff 자체 검증 누락**: 편집 후 assertion 값이 맞는지만 확인, **각 setup 라인이 assertion에 기여하는가**는 묻지 않음

글로벌 CLAUDE.md 원칙 위반:
> 변경 후 diff 자체 검증: 모든 수정 라인이 사용자 요청에 직접 추적 가능한가? 아니면 제거. (Karpathy Surgical Changes)

### Fix

1. 직접 지적된 2개 라인: `target.theme_state["rank"] = X` + "무시됨" 주석 함께 제거
2. 기존 leftover 3개 라인 (`test_factory_pc_r3_no_hp_buff`, `test_factory_pc_resets_collection_after_apply`, `test_factory_pc_r9_no_as_buff`): 로직 전환으로 사실상 무의미해진 target rank setup 정리
3. `test_factory_pc_rank_zero_no_enhance`: 의미 전환(target→factory)을 이름/주석에 반영
4. **새 invariance 검증 테스트 추가**: `test_factory_pc_ignores_target_rank` — target rank 0 vs 12 두 값으로 실행해 결과 동일함을 **비교 검증**. 단일 값 + "무시됨" 주석으로는 불변성을 증명할 수 없으므로 정석 방식.

결과: 906 → 907 tests, 6304 → 6305 asserts, all pass.

### Escalation Rule

자문 루틴화:
- 테스트 setup 각 라인: "**지우면 테스트 결과/의미가 달라지나?**" No → 제거
- 프로덕션 코드도 동일: "지우면 행동이 달라지나?" No → 제거
- 주석이 "이 코드 왜 있어?"에 답하는 모양이면 그 코드는 지울 후보
- 불변성을 증명하려면 **두 값 이상으로 비교 테스트**, 단일 값+주석 금지

이 규칙을 feedback_no_op_lines.md로 승격하여 다른 세션에서도 적용 가능하게 함.
