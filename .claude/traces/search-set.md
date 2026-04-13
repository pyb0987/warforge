---
description: "하네스 변경의 효과를 검증하는 과거 실패 사례 모음. 변경 후 이 사례들이 재발하지 않는지 확인한다."
last_updated: "2026-04-12"
---

# Harness Search Set

하네스 변경 후 이 목록의 active 사례로 효과를 검증한다.
항목 추가/제거 시 last_updated를 갱신한다.

운영 정책: Active 가 0건이 되면 Archived 항목의 verify 명령을 회귀 검증용으로 active 로 다시 끌어올린다 (회귀 안전망 유지).

## Active

### SS-001: hook dead reference 재발 방지
- **증상**: hook 이 삭제된 파일 경로(sim/simulate.py 등)를 참조하여 항상 실패하지만 에이전트가 무시
- **verify**: `grep -rE 'sim/simulate\.py|card_pool\.py|unit_pool\.py' /Users/fainders/personal/chain-army/.claude/settings.local.json && echo 'FAIL: dead reference found' || echo 'PASS: no dead reference'`
- **ref**: traces/failures/001-sim-hook-dead-reference.md
- **status**: regression guard (2026-04-07 reactivated from archived)

### SS-002: evaluator gradient cliff 재유입 방지
- **증상**: Tier 0 evaluator 축이 cliff function 으로 설계되어 optimizer 가 gradient 없는 구간에서 exploit
- **verify**: `python3 -c "import re,sys; t=open('/Users/fainders/personal/chain-army/godot/sim/evaluator.gd').read(); m=re.findall(r'clamp\(1\s*-\s*[^,]+,\s*0\s*,\s*1\)', t); print('FAIL: cliff clamp detected:', m) if m else print('PASS: no cliff clamp')"`
- **ref**: traces/failures/002-evaluator-win-rate-band-dead-zone.md
- **status**: regression guard (2026-04-07 reactivated from archived)

### SS-006: max_activations 설계↔코드 불일치 검증
- **증상**: 설계 문서에 상한(1~3회)이 명시된 카드가 코드에서 -1(무제한)로 등록
- **verify**: `cd /Users/fainders/personal/chain-army && python3 -c "import re; t=open('godot/core/data/card_db.gd').read(); checks=[('pr_molt',2),('pr_harvest',3),('pr_carapace',2),('ml_academy',2),('ml_conscript',1)]; fails=[c for c,v in checks if not re.search(c+r'.*max_activations.*'+str(v), t, re.DOTALL)]; print('FAIL: max_act mismatch:', fails) if fails else print('PASS: all max_activations correct')"`
- **ref**: traces/failures/006-card-design-code-audit.md
- **status**: active (2026-04-12)

## Archived

(없음 — SS-001/SS-002 는 회귀 방지를 위해 Active 로 유지)
