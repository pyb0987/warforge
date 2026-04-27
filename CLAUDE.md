# Warforge — 트리거 체인 로그라이크 덱빌더

## Build

```bash
# GDScript 단위 테스트 (GUT v9.6.0) — 디렉토리 전체
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=1 -gexit

# 단일 파일
godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_X.gd -glog=1 -gexit

# Fresh worktree / CI 첫 실행 또는 새 class_name 추가 후: cache 재빌드 필수
# (생략 시 stale class_cache로 ~149개 false-positive 카스케이드 실패 발생.
#  근거: traces/failures/010-stale-class-cache-cascade.md, search-set SS-008)
rm -f godot/.godot/global_script_class_cache.cfg
godot --headless --path godot/ --import
```

## Architecture

DESIGN.md = 마스터 문서 (확정 사항 + 상세 문서 목차). 최상위 진실 소스.
Godot Autoloads: Enums, CardDB(54장), UnitDB, UpgradeDB. Core: chain_engine(BFS), combat_engine.

## Conventions

### 밸런싱 원칙
- **1차 기준: 전투 시뮬 승률**. 빌드 간 밸런스는 승률로 판단.
- **2차 참고: CP**. 승률 원인 분석 시 참고. CP는 Range/MS를 미반영하므로 빌드 간 직접 비교 부적합.
- ❌ "CP가 낮으니 버프" → ✅ "승률이 낮으니 버프, CP를 보니 원인은 X"

### 완료 기준 (Sprint Contract)
작업 유형별 "완료"의 정의. 이 조건을 모두 통과해야 완료 선언 가능:
- **카드/수치 변경**: GUT 테스트 전체 통과 = 완료
- **신규 카드 설계**: card-pool-review-criteria.md Evaluator 서브에이전트 체크 통과 = 완료
- **★2/★3 설계**: feedback_star2_design.md Evaluator 서브에이전트 체크 전항 통과 = 완료
- **문서 변경**: DESIGN.md 변경 영향 맵에서 해당 영역 확인 → 명시된 문서 전부 업데이트 완료 = 완료
- **Godot 카드 데이터 변경**: 변경 카드의 설계 문서 대조 필수 (timing, effects, 수치, output_layer)
- **신규 구현 (기본값 TDD)**: Plan → Test (RED) → Implement (GREEN) → Refactor
  - 인터페이스 불명확 시: Plan → Spike(버림) → Test → Implement

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

## Harness (자율 피드백 루프)
- **Hooks**:
  - git commit guard (PreToolUse, **차단형** exit 2) — 카드 파일 커밋 시 Sprint Contract 미완료면 차단
  - .gd edit warning (PostToolUse, **경고형**) — 설계 문서 대조 리마인더. 프로그래밍적 검증 불가이므로 soft reminder
  - **Tier 0 protect-files** (PreToolUse Edit/Write/MultiEdit, **차단형** exit 2) — `godot/sim/{autoresearch.py, baseline.json, batch_runner.gd, program.md}` 수정 차단. 추가로 chmod 444가 걸려 Bash redirection도 막힘 (defense in depth). 정당한 사유로 수정해야 한다면 사용자 승인 후 `chmod +w`로 명시적 잠금 해제. agent-writable 탐색 로그는 `godot/sim/rejection_history.md` 사용.
  - **codegen protect** (PreToolUse Edit/Write/MultiEdit + Bash, **차단형** exit 2) — `card_db.gd` 직접 수정 차단 (Edit/Write + sed/cp/mv 등 Bash 명령 모두). chmod 444 defense-in-depth. codegen 실행이 유일한 쓰기 경로.
  - **YAML→codegen drift** (PostToolUse Edit/Write, **경고형**) — `data/cards/*.yaml` 수정 후 `codegen --check` 자동 실행. 불일치 시 codegen 실행 안내.
  - **r_conditional ★ parity validator** (codegen 내장, **차단형** exit 2) — 같은 카드의 `r_conditional`은 ★1/★2/★3에서 구조적으로 동일해야 함. 의도된 ★ 스케일링은 카드 top-level `star_scalable_actions: [action, ...]`로 명시. 근거: 훈련소/보급부대/군수공장 drift 3건 (commit 77e0a78, 18e7cb2). 회귀 테스트: `python3 -m unittest scripts.tests.test_r_conditional_validator`.
- **Skills**: `card-designer` (도메인 스킬), `btw` (유틸리티)
- **Trace Filesystem**: `.claude/traces/` — 진화(evolution/), 실패(failures/), 실험(experiments/)
- **변경 전략**: Additive first → Subtractive → Structural (한 번에 하나, 교란 변수 격리)
- **규칙 진화**: 실패 반복 시 harness-engineer로 진단 → 규칙/훅 추가
- **Failure escalation 루프**: `traces/failures/*.md`의 `resolved: true` 는 다음 중 하나가 충족돼야 함 — (a) `escalated_to` 가 비어있지 않음(CLAUDE.md / hook / 도구 등으로 흡수), (b) 동일 패턴의 active search-set 회귀 검증이 존재. 둘 다 부재하면 resolved 로 못 박지 않는다.

### Tier 0 Evaluator 설계 규칙
- 모든 평가 축은 **gradient 연속성** 필수. cliff function (특정 구간에서 gradient = 0) 금지. Gaussian / sigmoid / smooth piecewise 사용.
- 근거: failures/002-evaluator-win-rate-band-dead-zone.md — cliff clamp 가 optimizer 의 dead zone exploit 을 유발.
- 회귀 검증: search-set SS-002.

## Domain

확정된 핵심 제약 (변경 시 사용자 확인 필수):
- 성장 체인이 주력, 전투 체인은 보조
- 2층 이벤트 구조 (Layer1 결과범주 + Layer2 테마키워드)
- 55장 카드 풀 (중립15 / 테마별10). 테마: 스팀펑크/드루이드/포식종/군대
- SC1 스타일 스탯 (ATK 1~20, HP 20~500, AS/Range/MS)
- 2화폐 (골드+테라진). 판매: ★1 전액환급, ★2/★3 총 투자액-1골드 (합성 비용 회수 방지)
- 무료 리롤은 모두 이번 라운드 한정 (pending_free_rerolls)
- 배치 순서(왼→오) = 트리거 해결 순서
- 부대별 발동 횟수 상한으로 루프 방지
