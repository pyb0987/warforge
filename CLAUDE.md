# Chain Army — 트리거 체인 로그라이크 덱빌더

## Build

```bash
python3 sim/simulate.py              # 밸런스 시뮬레이터 (⚠ deprecated, 재작성 필요)
python3 sim/simulate.py -n 50 -v     # verbose 50 runs
```

## Architecture

문서 중심 프로젝트. 코드는 아직 없음.

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
```

문서 간 의존 방향: `DESIGN.md → docs/design/* → docs/episodes/*`
DESIGN.md의 "확정된 방향" 테이블이 최상위 진실 소스.

## Conventions

### 문서 수정 규칙
- DESIGN.md 확정 테이블 변경 시 반드시 사용자 확인
- 상세 문서 수정 시 DESIGN.md 목차/요약과 일관성 확인
- 수치 변경 시 관련 문서 교차 확인 (경제↔전투↔성장)
- 미결정 항목(backlog.md)은 결정 시 해당 상세 문서로 이관

### 카드 설계 규칙
- 카드 구성: 유닛 수, 스탯, 트리거 조건, 효과, 출력 이벤트, 발동 상한, 카드 태그
- 유닛 태그 ≠ 카드 태그 (혼동 금지)
- 키워드 독립 원칙: 제조 ≠ 번식 ≠ 부화 ≠ 징집 (결과 범주만 상위 반응)
- ⚔공격은 트리거 조건만 가능, 효과로 생성 불가

### 에피소드 기록
- 기존 확정 사항을 뒤집는 결정 시 `docs/episodes/YYYY-MM-DD-{topic}.md` 작성
- 변경 사유와 대안 비교 포함

## Domain

확정된 핵심 제약 (변경 시 사용자 확인 필수):
- 성장 체인이 주력, 전투 체인은 보조
- 2층 이벤트 구조 (Layer1 결과범주 + Layer2 테마키워드)
- 50장 카드 풀 (중립14 / 테마별9)
- SC1 스타일 스탯 (ATK 1~20, HP 20~500, AS/Range/MS)
- 2화폐 (골드+테라진), 판매 전액환급
- 배치 순서(왼→오) = 트리거 해결 순서
- 부대별 발동 횟수 상한으로 루프 방지
