# Warforge — 트리거 체인 로그라이크 덱빌더

## Build

```bash
python3 sim/simulate.py -v                  # verbose 1 run (basic preset)
python3 sim/simulate.py -p factory -v       # factory preset
python3 sim/simulate.py --chain-only -v     # chain only (no combat)
python3 sim/simulate.py --combat-only -v    # combat only (no chain)
python3 sim/simulate.py -n 50 --seed 42    # batch 50 runs

# GDScript 단위 테스트 (GUT v9.6.0)
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/ -glog=1 -gexit
```

## Architecture

DESIGN.md = 마스터 문서 (확정 사항 + 상세 문서 목차). 최상위 진실 소스.

### Godot 프로젝트 (godot/)
```
godot/core/types/enums.gd    — 글로벌 enum/상수 (Autoload)
godot/core/data/card_db.gd   — 54장 카드 템플릿 (Autoload)
godot/core/data/unit_db.gd   — 유닛 DB (Autoload)
godot/core/chain_engine.gd   — BFS 체인 엔진
godot/core/combat_engine.gd  — 전투 시뮬레이션
godot/scripts/                — UI/씬 스크립트
```

## Conventions

### 백프레셔 (자기 검증)
- 수치/카드 변경 후: `python3 sim/simulate.py -v` 로 시뮬 검증 필수
- 밸런스 관련 변경 후: `python3 sim/simulate.py -n 50 --seed 42` 배치 확인

### 밸런싱 원칙
- **1차 기준: 전투 시뮬 승률**. 빌드 간 밸런스는 승률로 판단.
- **2차 참고: CP**. 승률 원인 분석 시 참고. CP는 Range/MS를 미반영하므로 빌드 간 직접 비교 부적합.
- ❌ "CP가 낮으니 버프" → ✅ "승률이 낮으니 버프, CP를 보니 원인은 X"

### 완료 기준 (Sprint Contract)
작업 유형별 "완료"의 정의. 이 조건을 모두 통과해야 완료 선언 가능:
- **카드/수치 변경**: sim -v 에러 없음 + sim -n 50 --seed 42 배치 정상 = 완료
- **신규 카드 설계**: card-pool-review-criteria.md Evaluator 서브에이전트 체크 통과 = 완료
- **★2/★3 설계**: feedback_star2_design.md Evaluator 서브에이전트 체크 전항 통과 = 완료
- **문서 변경**: DESIGN.md 변경 영향 맵에서 해당 영역 확인 → 명시된 문서 전부 업데이트 완료 = 완료
- **시뮬레이터 코드 변경**: 4개 프리셋 모두 에러 없음 = 완료
  - `sim -v` + `sim -p factory -v` + `sim --chain-only -v` + `sim --combat-only -v`
- **Godot 카드 데이터 변경**: 변경 카드의 설계 문서 대조 필수 (timing, effects, 수치, output_layer)

### 문서 수정 규칙

**단일 진실 소스 원칙 (DB 정규화)**
- DESIGN.md = 유일한 진실 소스. 확정 사항은 여기에만 기록.
- 상세 문서(docs/design/) = DESIGN.md의 확장. DESIGN.md와 모순 불허.
- 메모리(project_*.md) = 포인터 + 판단 맥락만. 사실 복사 금지.
  - 포맷: `상세: DESIGN.md § 섹션 | docs/design/파일.md` + `**How to apply:** 판단 맥락`
- 새 상세 문서 추가 시: DESIGN.md 목차 + 변경 영향 맵에 등록 필수

**수정 절차**
- DESIGN.md 확정 테이블 변경 시 반드시 사용자 확인
- 변경 후 DESIGN.md 변경 영향 맵에서 영향 범위 확인 → 해당 문서 동기화
- 미결정 항목(backlog.md)은 결정 시 해당 상세 문서로 이관

### Godot 코드 ↔ 설계 문서 정합성 (필수)
카드/수치/효과 코드 작성 시 **반드시 해당 설계 문서를 Read로 확인** 후 작성.
기억·요약·컨텍스트 내 정보로 코드를 작성하면 안 됨.

체크 항목:
- trigger_timing (RS/OE/BS/PC/PERSISTENT 등)
- listen_layer1/layer2 값
- effects의 action, target, 수치 (atk_pct, spawn_count 등)
- max_activations
- output_layer (이벤트 방출 여부)
- 상수 (리롤 비용, 골드, 테라진 등) — DESIGN.md 원본 대조

구현이 복잡하면:
- effects=[]로 비우고 주석에 "X_system에서 구현 예정" 표시
- ❌ 임의로 단순화한 플레이스홀더 효과를 넣지 않음

### 에피소드 기록
- 기존 확정 사항을 뒤집는 결정 시 `docs/episodes/YYYY-MM-DD-{topic}.md` 작성
- 변경 사유와 대안 비교 포함

## Agent Team

크로스 도메인 작업(설계+시뮬+엔진 2개+ 동시 변경) 시 에이전트 팀으로 실행.
단일 도메인 작업에는 직접 수행.

- **팀 구성**: `.claude/agents/` (designer, balancer, engineer, qa)
- **오케스트레이션**: `.claude/skills/warforge-orchestrator/SKILL.md`
- **아키텍처**: Fan-out/Fan-in (병렬 구현) + Producer-Reviewer (카드 설계)
- **작업 위임**: `.claude/agents/delegation-protocol.md` — 판단은 자신이, 실행·검증은 경량 모델에 위임
- **모델 배정**: designer/balancer=opus, engineer/qa=sonnet, 실행·대조·체크리스트=haiku 위임
- **검증 강도**: Tier 1(체크리스트) → Tier 2(Evaluator 서브에이전트) → Tier 3(/multi-review)
- **규칙 진화**: qa 에이전트가 실패 분류(정보 부족/제약 미비/도구 부재) → 2회+ 반복 시 규칙화
- **드리프트 방지**: qa 에이전트가 코드-문서 괴리 감지 → 불필요 규칙 제거 제안

## Domain

확정된 핵심 제약 (변경 시 사용자 확인 필수):
- 성장 체인이 주력, 전투 체인은 보조
- 2층 이벤트 구조 (Layer1 결과범주 + Layer2 테마키워드)
- 54장 카드 풀 (중립14 / 테마별10). 테마: 스팀펑크/드루이드/포식종/군대
- SC1 스타일 스탯 (ATK 1~20, HP 20~500, AS/Range/MS)
- 2화폐 (골드+테라진), 판매 전액환급
- 배치 순서(왼→오) = 트리거 해결 순서
- 부대별 발동 횟수 상한으로 루프 방지
