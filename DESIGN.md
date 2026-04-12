# Warforge — 트리거 체인 로그라이크 덱빌더 게임 기획

## Context
발라트로(조합 극대화 로그라이크) + 스타 선술집 전투(트리거 체인 군집 오토배틀) + 유희왕 OCG(연쇄 발동)의
핵심 재미를 결합한 PvE 로그라이크 덱빌더를 기획한다.

**핵심 판타지**: 불합리할 정도로 강한 적 앞에서, 내가 직접 키운 군대와 조합이 "사기"가 되어 작동하는 순간.

## 확정된 방향

| 항목 | 결정 | 비고 |
|------|------|------|
| 게임 루프 | 로그라이크 런 기반 | 매 런마다 새 빌드 |
| 전투 모델 | **리얼타임 자동 전투** + 성장 체인 | 전투는 절대 멈추지 않음. 성장 체인은 빌드 페이즈에서 군대를 키우는 주력 메카닉 |
| 전투 규모 | 대규모 군집 (20v20+) | 카드=부대, 소수 카드로 대규모 전장 |
| 카드 구조 | 카드 1장 = 부대 (유닛 N명) | 유닛 수 vs 효과 강도 트레이드오프 |
| 스탯 modifier | **카드 귀속 누적** | 강화(개량/성장 등)는 카드에 누적. 기본은 전 유닛 적용, 태그 지정 시 해당 태그 유닛만 적용. 이동 시 소실 |
| 시너지 핵심 | **성장 체인 중심** (2층 구조) | 성장 이벤트 3종 + 전투 이벤트 3종 + 키워드 이벤트 |
| 시너지 보조 | 태그 (패시브 보너스) | 카드 효과의 한 유형 (패시브 태그 참조) |
| 인접 위치 | 배치 위치가 트리거 조건에 포함 | "인접 카드가 ~했을 때" 등 |
| 루프 방지 | 부대(카드)별 발동 횟수 제한 | 라운드당 최대 N회 반응 상한 |
| 카드 업그레이드 | 합성 (같은 카드 3장 → ★ 상승) | 유닛 수 증가 + ★3에서 질적 변환 |
| 승리 조건 | **모든 라운드 생존** | 플레이어 HP=0 → 런 실패 |
| HP 구조 | **플레이어 HP만** (30) | 패배 시 적 생존 유닛 수 = 플레이어 데미지 |
| 적 구조 | 프리셋 풀 + 랜덤 업그레이드 | 라운드당 3~4개 프리셋 중 선택. 특성 보스. |
| 필드 제한 | **시작 6장** → 최대 8장 | 커맨더/부적/보스 보상으로만 증가 |
| 경제 | **오토배틀러식 2화폐** | 골드(카드) + 테라진(업그레이드). ★1 전액환급, ★2/★3 총 투자액-1g |
| 트리거 해결 순서 | **배치 순서 (왼→오)** | 인접 위치 시스템과 일관 |
| 세션 길이 | 28~35분 | 15 라운드 |
| 유닛 스탯 스케일 | **SC1 스타일** (ATK 1~20, HP 20~500, AS/Range/MS) | DEF 기본 0, 업그레이드로 부여 |
| 테마/세계관 | **4테마 + 중립** | 스팀펑크/드루이드/포식종/군대 + 중립(15장). 테마별 고유 키워드 |
| 카드 풀 | **55장, 고갈 메커니즘** | 중립15 / 스팀펑크10 / 드루이드10 / 포식종10 / 군대10. 복사본: T1=22/T2=18/T3=15/T4=13/T5=11. 구매 시 소모, 판매/리롤 시 반환 |
| 메타 진행 | 풍부 (로그라이트) | 영구 업그레이드, 컬렉션, 스토리 |

---

## 상세 문서 목차

| 문서 | 내용 |
|------|------|
| [themes.md](docs/design/themes.md) | 테마 & 카드 풀 구성, 키워드 Layer 구조, 빌드 아키타입 |
| [architecture.md](docs/design/architecture.md) | 2층 유닛/카드 아키텍처, 유닛 풀, 태그 체계, 카드 구성 요소, **카드 레벨 스탯 modifier** |
| [units-steampunk.md](docs/design/units-steampunk.md) | 스팀펑크 유닛 풀 10종 (#기계, 균형) |
| [units-druid.md](docs/design/units-druid.md) | 드루이드 유닛 풀 10종 (#생체, 소수 정예) |
| [units-predator.md](docs/design/units-predator.md) | 포식종 유닛 풀 10종 (#생체, 물량) |
| [units-military.md](docs/design/units-military.md) | 군대 유닛 풀 10종 (#생체+#기계 혼합, 미래전) |
| [units-neutral.md](docs/design/units-neutral.md) | 중립 유닛 풀 10종 (#기계/#생체 50:50, 방랑자/야생) |
| [cards-steampunk.md](docs/design/cards-steampunk.md) | 스팀펑크 카드 풀 10장 |
| [cards-druid.md](docs/design/cards-druid.md) | 드루이드 카드 풀 10장 (나무 시스템) |
| [cards-military.md](docs/design/cards-military.md) | 군대 카드 풀 10장 (계급 임계점 시스템) |
| [cards-neutral.md](docs/design/cards-neutral.md) | 중립 카드 풀 6장 (1차 검증용) |
| [design-space.md](docs/design/design-space.md) | 카드 설계 공간: 트리거/효과/대상 풀, 발라트로식 효과, 시스템 간 강도 |
| [game-loop.md](docs/design/game-loop.md) | 핵심 게임 루프, 런 구조, 보스 보상 유형별 설계 원칙 |
| [growth-chain.md](docs/design/growth-chain.md) | 성장 체인 시스템, 이벤트 2층 구조, 발동 모델, 이벤트 흐름 규칙 |
| [combat.md](docs/design/combat.md) | 전투 시스템, 적 파워 곡선, 적 프리셋 프레임워크, 보스 설계 |
| [upgrade.md](docs/design/upgrade.md) | 업그레이드 시스템, 경제 시스템, 상점, ★합성, 2화폐 구조 |
| [upgrades-items.md](docs/design/upgrades-items.md) | 업그레이드 아이템 풀 26종 (커먼11/레어9/에픽6) |
| [replay.md](docs/design/replay.md) | 리플레이 시스템: 커맨더 7종, 부적 12종, 난이도 8단계, 해금 |
| [talismans.md](docs/design/talismans.md) | 부적 12종 상세: 효과, 시너지, 밸런스 파라미터, 해금 |
| [card-design-method.md](docs/design/card-design-method.md) | 카드 설계 접근법, 안티패턴 |
| [card-codegen-schema.md](docs/design/card-codegen-schema.md) | YAML → GDScript 코드젠 파이프라인, 카드 DSL, 테마별 효과, codegen 설계 |
| [card-pool-review-criteria.md](docs/design/card-pool-review-criteria.md) | 테마 카드 풀 multi-review 평가 기준 (4개 축) |
| [boss-rewards.md](docs/design/boss-rewards.md) | 보스 보상 풀 27종 (R4/R8/R12, 유형별 설계 원칙) |
| [backlog.md](docs/design/backlog.md) | 미결정 항목 |

### 기술 문서

| 문서 | 내용 |
|------|------|
| [docs/tech/rendering.md](docs/tech/rendering.md) | 렌더링 & 전투 엔진 기술 설계, 최적화 전략 |

**엔진**: Godot 4 (GDScript). 사유: [에피소드 기록](docs/episodes/2026-03-26-tech-stack-godot.md)

**Godot Autoloads**: `Enums`, `CardDB` (55장), `UnitDB`, `UpgradeDB`

**CardDB API** (주요 메서드):
- `get_template(id)` → 기본 ★1 템플릿 dict 반환
- `get_star_template(base_id, star_level)` → base + star_overrides 병합된 ★N 템플릿 반환
- `get_theme_effects(card_id, star_level)` → theme_system 카드의 per-star DSL effect 배열 반환 (`{theme}_system.gd`에서 소비)
- `get_all_ids()` → 전체 card_id 배열
- `get_ids_by_theme(theme)` → 테마별 card_id 배열

### 의사결정 기록

| 문서 | 내용 |
|------|------|
| [docs/episodes/](docs/episodes/) | 설계 의사결정 에피소드 기록 |

---

## 변경 영향 맵

DESIGN.md의 확정 사항을 수정할 때 함께 업데이트해야 하는 상세 문서 목록.
Sprint Contract "문서 변경" 완료 기준: **이 표에 명시된 문서가 모두 동기화됐는가?**

| 확정 영역 | 함께 업데이트할 문서 |
|-----------|---------------------|
| 경제 시스템 (골드/테라진/상점/판매/이자) | docs/design/upgrade.md |
| 업그레이드 시스템 (슬롯/★합성/획득경로) | docs/design/upgrade.md, docs/design/upgrades-items.md |
| 카드 풀 구성 (테마/중립/장수) | docs/design/themes.md |
| 유닛/카드 아키텍처 (태그/modifier/구조) | docs/design/architecture.md |
| 성장 체인 (이벤트/Layer 구조/발동 모델) | docs/design/growth-chain.md |
| 전투 시스템 (스탯 스케일/적/보스/HP) | docs/design/combat.md |
| 게임 루프 (라운드/필드 슬롯/세션 길이) | docs/design/game-loop.md |
| 리플레이 (커맨더/부적/난이도) | docs/design/replay.md, docs/design/talismans.md |
| 카드 설계 방법론 | docs/design/card-design-method.md |
| 카드 수치/효과 변경 (YAML DSL) | data/cards/*.yaml → card_db.gd (자동생성), {theme}_system.gd |

> 새 상세 문서 추가 시 이 표에 등록 필수.
