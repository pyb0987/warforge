---
iteration: 12
date: 2026-04-16
type: structural
verdict: pending
files_changed:
  - data/cards/military.yaml
  - docs/design/cards-military.md
refs:
  - ".claude/plans/vast-moseying-lollipop.md"
  - "harness-methodology.md § Additive Modification, P5"
---

## Problem

기존 군대 카드 R3/5/8 임계점 시스템이 세 가지 문제를 가짐:

1. **+1기 생산의 질적 변화 부재**: 임계점마다 "+1 유닛" 보상이 수량만 늘어날 뿐 효과가 질적으로 전환되지 않아 성장 체감이 약함.
2. **훈련 메커닉의 단조로움**: 훈련 효과가 훈련소/특수작전대/통합사령부/군사학교에만 있고, 다른 카드에서 훈련을 활용할 여지가 제한됨.
3. **카드 간 축 구분 부재**: ★ 축과 R(rank) 축의 의미가 각 카드마다 다르게 섞여 있어 설계 일관성 결여.

유저 피드백: 카드마다 두 축이 직교하게 구분되었으면 좋겠고, R4/R10을 엔드게임 milestone으로 재정의하고 싶음.

## Decision

R3/5/8 임계점 삭제 → **R4/R10 두 milestone**으로 압축. 각 카드에 **★ = 양적 스케일링 / R = 질적 전환** 두 축을 직교 적용.

| 공통 R 효과 | 내용 |
|---|---|
| R4 도달 | 이 카드 비(강화) 유닛 절반이 (강화)로 자동 변환 |
| R10 도달 | 이 카드 모든 유닛이 (강화)로 자동 변환 |

### 10장 카드 재설계 요약

| # | 카드 | ★ 축 | R 축 |
|---|---|---|---|
| 1 | 훈련소 | 훈련 수량 (self 가속) | 전파 범위 (오른쪽→양쪽→전체) |
| 2 | 징병국 (스왑 from 전진기지) | 징집 수량/범위 | 징집 풀 등급 (일반→강화→엘리트) |
| 3 | 전진기지 (스왑 from 징병국) | 반응 수량/강화 비율 | 증원 범위 (대상→대상+인접→전체) |
| 4 | 군사학교 | max_act/훈련량/enhance | 훈련 질적 전환 |
| 5 | 보급부대 | 골드 계수 | R4: 테라진+1 / R10: 테라진+2 + 골드+1 |
| 6 | 전술사령부 | rank_buff 계수 | R4: HP+3%/rank / R10: AS+15% |
| 7 | 돌격편대 (구조 B) | 바이커 생산 (1→2→4기) | R4: swarm_buff 해금 / R10: 라이프스틸 |
| 8 | 특수작전대 | 크리 배율 + 저격드론 생산 | 크리 확률 + 스플래시 |
| 9 | 군수공장 | counter→전군 ATK + Range | R4/R10 누적: 슬롯+할인 |
| 10 | 통합사령부 | 훈련량 + 부활 HP (25/50/100%) | 부활 범위 (자기강화→자기전체→인접 3장) |

## Change

### 1. `data/cards/military.yaml` 전체 재작성
- `rank_threshold` 필드 전체 제거
- 새 `r_conditional` 필드로 R4/R10 효과 선언
- 징병국↔전진기지 스왑 (tier, timing, comp, effects 모두 교환)
- 돌격편대 timing BS→RS 전환
- 새 action/field 선언 (구현은 별도 스프린트):
  - `crit_buff`, `crit_splash`
  - `revive_scope_override`
  - `upgrade_shop_bonus`
  - `rank_buff_hp`
  - `enhance_convert_card`, `enhance_convert_target`
  - `spawn_enhanced_random`
  - `conscript_pool_tier`
  - `global_military_atk_pct`, `global_military_range_bonus`
  - `lifesteal` (target: all_military)
  - `spawn_unit`
  - `grant_gold`, `grant_terazin`

### 2. `docs/design/cards-military.md` 전면 재작성
- 계급 시스템 섹션 재작성 (R4/R10 중심)
- ★/R 매트릭스 요약 표 추가
- 각 카드 상세 설명 업데이트
- 타임라인(정예형/물량형) 재작성
- 구현 필요 항목 리스트 추가 (placeholder → 구현 스프린트)

## 변경 전략

**Structural + Additive** — 한 번에 하나의 변경 원칙을 일부 위반하지만, 10장 카드가 상호의존적이므로 일괄 설계 변경이 불가피.

완화책:
- **YAML + 설계 문서 변경 (Step 1)**: 이번 커밋 범위
- **codegen + 기존 테스트 임시 조정 (Step 2)**: 별도 커밋
- **새 메커닉 구현 (Step 3+)**: 개별 카드/메커닉별 개별 커밋으로 분리

## 검증 기대치

### Step 1 검증 (이번 범위)
- [ ] YAML schema 유효성: codegen 실행 시 파싱 에러 없음
- [ ] 설계 문서와 YAML의 수치 일치 (맞대조)
- [ ] DESIGN.md 변경 영향 맵 확인 (cards-military.md만 해당)

### Step 2 검증 (후속)
- [ ] `codegen_card_db.py` 실행 → `card_db.gd` 재생성
- [ ] 기존 GUT 테스트 중 rank_threshold 관련 삭제/스킵
- [ ] `godot --headless --path godot/ -s addons/gut/gut_cmdln.gd` 통과

### Step 3+ 검증 (후속 스프린트)
- [ ] 각 새 메커닉 구현 후 단위 테스트 추가
- [ ] 시뮬 승률 측정 (정예형 vs 물량형, 기존 baseline 대비)
- [ ] 훈련 가속 보정 (훈련소 R10 전체 군대 전파 + 통합사령부 ★3 전군 +2 복리 확인)

## Multi-review 결과

사전 multi-review 수행 (4 critic):

| Critic | Score | Verdict | 주요 지적 |
|---|---|---|---|
| 밸런스 엔지니어 (opus) | 4 | VETO | 통합사령부 ★3+R10 과강, 훈련 가속 리스크, 빌드 비대칭, 특수작전대 과강, 군수공장 R10 슬롯 원칙 파괴 |
| 판타지 내러티브 | 8 | pass | ★/R 축 분리 직관적, 이름-효과 일치 우수 |
| 시스템 일관성 | 7 | concern | 군수공장 R10 대체 패턴 비일관 (이후 누적으로 수정) |
| 구현 실현 가능성 | 5 | concern | revive/upgrade_shop_bonus/슬롯 증대 등 HARD 항목 다수 |

Critic 1 VETO에 대응하여 다음 하향 반영:
- 통합사령부 ★ 부활 HP 50/75/100% → **25/50/100%**
- 통합사령부 ★3 on_revive 버프 (shield+20%, ATK+20%) **제거**
- 통합사령부 R10 전체 군대 → **인접 양쪽 카드로 제한**
- 특수작전대 ★3 배율 8.0 → **6.0**
- 군수공장 R10 카드 슬롯 +1 **제거** (5슬롯 통일 원칙 유지), R4와 누적형으로 변경
- 보급부대 R10 커먼 업그레이드 자동 부착 **제거** (상점 채널 원칙 유지), 대신 테라진 +2 + 골드 +1

## Risks

1. **훈련 가속 복리**: 훈련소 R10 + 통합사령부 ★3 조합이 여전히 강력. 시뮬 필요.
2. **구현 부담**: 8~10개의 placeholder 효과가 별도 구현 스프린트 필요. Step 2에서 일부 기존 테스트 실패 예상.
3. **시뮬 baseline 리셋**: 기존 군대 밸런스 데이터 무효화. AI 승률 재측정 필요.

## Rollback 조건

- Step 2 codegen 실패 시 → Step 1 커밋 revert
- Step 3+ 시뮬 결과 군대 승률 극단치(>70% or <30%) 2주 연속 → 수치 재조정 (구조는 유지)
