# Chain Army — 트리거 체인 로그라이크 덱빌더

## Build

```bash
python3 sim/simulate.py -v                  # verbose 1 run (basic preset)
python3 sim/simulate.py -p factory -v       # factory preset
python3 sim/simulate.py --chain-only -v     # chain only (no combat)
python3 sim/simulate.py --combat-only -v    # combat only (no chain)
python3 sim/simulate.py -n 50 --seed 42    # batch 50 runs
```

## Architecture

```
DESIGN.md                  ← 마스터 문서 (확정 사항 + 목차)
docs/design/               ← 상세 설계 11편 (정규 문서)
  architecture.md           유닛/카드 2층 구조
  themes.md                 4테마+중립, 키워드 Layer 구조
  growth-chain.md           성장 체인 이벤트 시스템
  cards-steampunk.md        스팀펑크 카드 풀 9장
  cards-example.md          초기 예시 10장 (임시)
  design-space.md           카드 설계 공간 (트리거/효과/대상)
  game-loop.md              런 구조, 보스 보상
  combat.md                 전투, 적 파워 곡선
  upgrade.md                업그레이드, 경제, 상점
  replay.md                 커맨더, 부적, 난이도
  backlog.md                미결정 항목
docs/episodes/             ← 의사결정 에피소드 (변경 사유 기록)
docs/growth-chain-math.md  ← 수학 검증 (참고용)
docs/balance-methodology.md← 밸런스 방법론 (참고용)
sim/                       ← 시뮬레이션 코드
  engine/                    types, units, cards, chain, combat, game
  data/                      unit_pool(20종), card_pool(14장), enemies
  simulate.py                CLI 엔트리포인트
```

문서 간 의존 방향: `DESIGN.md → docs/design/* → docs/episodes/*`
DESIGN.md의 "확정된 방향" 테이블이 최상위 진실 소스.

## Conventions

### 문서 수정 규칙
- DESIGN.md 확정 테이블 변경 시 반드시 사용자 확인
- 상세 문서 수정 시 DESIGN.md 목차/요약과 일관성 확인
- 수치 변경 시 관련 문서 교차 확인 (경제↔전투↔성장)
- 미결정 항목(backlog.md)은 결정 시 해당 상세 문서로 이관

### 카드 설계 기조
- 카드 구성: 유닛 조합 + 트리거 조건 + 효과 + 발동 상한 + 카드 태그(1~3)
- 유닛 태그 ≠ 카드 태그 (혼동 금지)
- 키워드 독립 원칙: 제조 ≠ 번식 ≠ 부화 ≠ 징집 (결과 범주만 상위 반응)
- ⚔공격은 트리거 조건만 가능, 효과로 생성 불가

**발동 모델:**
- 1이벤트 = 1발동. "발동 N회" = 라운드당 반응 상한
- 라운드 시작 카드: 1회 발동. ★ 진화 = 효과 품질 향상 (횟수 아님)
- 자기 루프 방지: "다른 카드의 [키워드] 효과 발동 시" (주체=효과 발동 카드, source 기준)
- 트리거 표현에서 주체 명확화: "제조 시" ✗ → "다른 카드의 제조 효과 발동 시" ✓

**★2 설계:**
- 발동 상한 증가 ✗ → 발동당 효과 강화 ✓ (시뮬 검증)
- 양 2배(1기→2기) / 범위 확대(→양쪽) / 태그 확대 / 수치 강화 / 효과 추가 중 1개
- 무료 레어 업그레이드: 해당 카드 스탯 ×1.30
- 총 파워 예산: 해당 카드 기여 ×1.5~1.8

**성장 & 스탯:**
- 카드 효과의 성장(개량/성장 등): 드문 효과 (테마 9장 중 2~3장). 기본 5%, 조건부 8%
- 스탯 성장의 주 축 = 업그레이드 (테라진 경제)
- 카드 효과 = 1회성. 영구 규칙 = 업그레이드/보스 보상의 영역
- 강화 수치: 기본 %(원래 스탯 기준), 곱연산(명시), 고정값(드문)

**⚡충전:**
- 대폭 감소. 체인 연결자가 아닌 드문 강력 효과로 취급
- 체인은 제조↔개량 등 Layer2 이벤트로 직접 연결
- 자기 충전(자신 ⚡충전) = 무한 루프 위험 → 사용 금지

**효과 다양성 (설계 공간 활용):**
- 모든 카드가 체인 이벤트 반응일 필요 없음
- 경제(골드/리롤), 전투(버프/패배보상), 시간(체류), 임계점, 대가형 등 다양한 트리거 사용
- 저티어 카드 일부에 골드 경제 효과 포함
- 유닛 이름은 시각화 가능한 개체 (부품/재료 이름 금지)

### 에피소드 기록
- 기존 확정 사항을 뒤집는 결정 시 `docs/episodes/YYYY-MM-DD-{topic}.md` 작성
- 변경 사유와 대안 비교 포함

## Domain

확정된 핵심 제약 (변경 시 사용자 확인 필수):
- 성장 체인이 주력, 전투 체인은 보조
- 2층 이벤트 구조 (Layer1 결과범주 + Layer2 테마키워드)
- 50장 카드 풀 (중립14 / 테마별9). 테마: 스팀펑크/드루이드/포식종/군대
- SC1 스타일 스탯 (ATK 1~20, HP 20~500, AS/Range/MS)
- 2화폐 (골드+테라진), 판매 전액환급
- 배치 순서(왼→오) = 트리거 해결 순서
- 부대별 발동 횟수 상한으로 루프 방지
