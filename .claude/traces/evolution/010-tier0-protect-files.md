---
iteration: 10
date: "2026-04-08"
type: additive
verdict: pending
files_changed:
  - godot/sim/rejection_history.md (NEW)
  - godot/sim/program.md (split + frozen-genome rule + chmod 444)
  - godot/sim/autoresearch.py (chmod 444)
  - godot/sim/baseline.json (chmod 444)
  - godot/sim/batch_runner.gd (chmod 444)
  - .claude/settings.local.json (PreToolUse Edit|Write|MultiEdit hook)
  - CLAUDE.md (Hooks 섹션에 Tier 0 protect-files 등록)
  - "(git) commit 6c3eb18 — godot/sim/ 37파일 트래킹 시작"
refs:
  - traces/failures/002-evaluator-win-rate-band-dead-zone.md
  - traces/failures/003-engine-bonus-bump-rejected.md
  - multi-review 2026-04-08 (Tier 0 파일 보호 제안 평가)
---

## Iteration 10: Tier 0 Fixed Evaluator 파일 보호 + git 트래킹 정상화

### Problem
- CLAUDE.md §Tier 0 규칙은 evaluator immutability를 명시하지만, 이를 강제하는 메커니즘이 없었다.
- failure 002가 정확히 그 결과: 30 iteration 동안 evaluator 자기 평가 dead zone exploit이 발생, weighted_score 0.4142→0.4945 "개선"이 실제 WR 0% 붕괴를 가렸다.
- 추가로 발견된 인접 결함: `godot/sim/` 디렉토리 전체가 git 미트래킹 (37개 파일). baseline_old/new/pre_board_fix.json 사이드 스냅샷이 존재 → 과거 baseline reset이 ad-hoc 파일명으로만 추적되던 증거.
- failure 003 시점에 ADOPT 결정이 0.5956 vs 0.5896 (델타 0.006) 단위로 내려지고 있음 → 어떤 baseline drift도 노이즈에 묻혀 silent하게 카드 밸런스 결정을 오염시킬 수 있음.

### Change (additive — 정책/제약/도구를 추가, 기존 평가 로직은 미변경)

1. **godot/sim/ git 트래킹** (commit 6c3eb18)
   - 37개 파일 전부 add — autoresearch.py, baseline.json, batch_runner.gd, evaluator.gd, ai_*.gd, default_genome.json, baseline_*.json 스냅샷, experiments.jsonl, program.md 등.
   - 후속 보호 메커니즘의 전제 조건: 비교 대상이 되는 git 이력이 먼저 존재해야 chmod/hook이 의미를 가진다.

2. **program.md 분리 + Tier 0 immutability 강제**
   - agent-writable 섹션 (`AI 행동 변경 이력`, `Genome 탐색 이력`)을 신규 파일 `godot/sim/rejection_history.md`로 이관.
   - program.md의 §금지 사항에 항목 7 추가: `default_genome.json`은 Phase 도중 수정 금지, Phase 종료 시에만 sha256 + 변경 사유 기록.
   - rejection_history.md에 `Phase 별 default_genome.json 스냅샷` 테이블 + `Rejection 로그` 섹션 추가.

3. **chmod 444 (defense layer 1 — OS-level)**
   - `autoresearch.py`, `baseline.json`, `batch_runner.gd`, `program.md` 4파일에 read-only.
   - Bash redirection (`cat >`, `tee`, `sed -i`, `python -c open(...,"w")`) 차단.
   - autoresearch.py의 subprocess 내부 file I/O는 영향 없음 (subprocess는 자기 권한으로 동작; chmod는 user write bit만 끔).

4. **PreToolUse Edit|Write|MultiEdit hook (defense layer 2 — semantic)**
   - settings.local.json에 신규 matcher 등록.
   - 차단형 (exit 1) + agent에게 *왜* 차단됐는지 + 우회 경로(rejection_history.md, chmod +w) 안내 메시지.
   - 단순 chmod만으론 EACCES만 받지만, 이 hook은 Tier 0 원칙 위반이라는 의미를 전달 → agent가 다른 우회를 시도하지 않고 사용자에게 에스컬레이션하도록 유도.

5. **CLAUDE.md §Harness/Hooks**에 신규 hook 등록 (문서화).

### 보호 대상 결정 근거 (multi-review)

| 파일 | 분류 | 이유 |
|------|------|------|
| autoresearch.py | MUST | 평가 로직 자체. 수정 = 자기 평가 오염. |
| baseline.json | MUST | weighted_score SSOT. 수정 = ADOPT 비교 위조. |
| batch_runner.gd | MUST | sim runner. 수정 = 게임 결과 위조. |
| program.md | MUST | 연구 목표/제약. 수정 = 골대 이동. (agent 갱신은 rejection_history.md로 분리.) |
| best_genome.json | SKIP | autoresearch.py가 subprocess open()으로 자동 갱신. agent 수동 차단의 실익이 없고 비상 롤백 시 오히려 방해 (Critic 3 권고). |
| default_genome.json | RULE-ONLY | mutation seed라 chmod 부적합 (autoresearch.py가 읽음). program.md §금지 사항 7로 phase 도중 수정 금지를 코드화. |
| evaluator.gd / ai_*.gd / 카드 데이터 | UNPROTECTED | genome 탐색 공간. agent가 자유롭게 수정해야 함. |

### 변경 전략 (additive 검증)
- 5개 변경을 한 iteration에 묶었으나, 각각이 서로 직교하고 평가 행동을 바꾸지 않는 인프라 수정 (CLAUDE.md harness-methodology §"건강도 일괄 수정" 예외 조항 적용).
- 평가 로직 (autoresearch.py 본문, evaluator 가중치, win_rate_band 함수) 일체 미변경 → autoresearch 결과의 직접 비교 가능성 보존.

### 검증 기대치
- 다음 autoresearch 실행에서 baseline.json / autoresearch.py / batch_runner.gd 수정 시도가 발생하면 차단되어야 함 (negative test).
- 다음 ADOPT 발생 시 best_genome.json은 정상 갱신되어야 함 (subprocess 경로 영향 없음 확인).
- rejection_history.md에 phase 종료 시 default_genome.json sha256이 정상 기록되는지 다음 phase 종료 시점에 검증.

### Open question
- 이 hook과 chmod 조합의 false-positive 빈도. 정당한 수정 (예: failure 002 같이 evaluator에 cliff function이 발견된 경우)이 매번 사용자 승인 절차를 거치는 것이 과도한 마찰인지 확인 필요. 마찰이 크면 "사용자 승인 토큰 파일" 같은 우회 메커니즘 도입 검토.
