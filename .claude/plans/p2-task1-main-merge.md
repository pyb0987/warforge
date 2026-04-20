# Task 1 — main에 Phase 2 merge (Option A 선행 단계)

**상태**: 대기 (이 Task가 Task 2~4의 선행 의존)
**작성일**: 2026-04-20
**난이도**: 중 (git 조작 + 검증)

## 배경

Phase 2 (v2 block 구조) 가 `claude/beautiful-cerf-9498a9` 브랜치에 완료됐으나 **main에 merge 안 됨**. main은 여전히 v1 flat YAML + v1 codegen 상태이고, 사용자가 별도로 추가한 기술부채 Stage 1-3 커밋(b12e6f4, 0c55b9d, 58aaf2a)은 v1 기반 위에 쌓였음.

두 갈래 상태:
- **main**: v1 base (4d219cd) + Stage 1-3 validators
- **beautiful-cerf-9498a9**: v1 base (4d219cd) + pr_parasite fix(7047e26) + Phase 2 전체(ff2fdb3 ~ d18d1ce)

사용자 결정: **v2 구조로 일원화** (Option A). Stage 1-3 의 validator 개선점은 v2 코드에 재적용 (Task 2-4).

## 목표

main 브랜치를 v2 구조로 전환. `claude/beautiful-cerf-9498a9` 를 main 에 선형으로 적용.

## 작업 순서

### 1) 현 상태 확인
```bash
cd /Users/fainders/personal/chain-army  # main repo
git checkout main
git log --oneline main -10
git log --oneline claude/beautiful-cerf-9498a9 -10
```

예상 결과:
- main: `58aaf2a` Stage 3 → `0c55b9d` → `b12e6f4` → `4d219cd`
- beautiful-cerf-9498a9: `d18d1ce` → `8faa52e` → ... → `ff2fdb3` → `7047e26` → `4d219cd`

### 2) Stage 1-3 revert (main의 Stage 커밋 되돌리기)
사용자 허락됨 ("main에 푸시된 사항을 revert해도 좋습니다"). 안전하게 revert commit 방식:

```bash
git checkout main
git revert 58aaf2a 0c55b9d b12e6f4 --no-edit
```

또는 원격 push 전이면 간단히:
```bash
git reset --hard 4d219cd  # local 만, 주의: push 후면 force 필요
```

**권고**: 원격 push 여부 확인 — `git log origin/main..main` 으로 local-only commit 확인. 원격에 push 됐으면 revert 사용. 안 됐으면 reset 가능.

### 3) beautiful-cerf-9498a9 merge
```bash
git merge claude/beautiful-cerf-9498a9
```

이 시점 main base = 4d219cd (또는 revert 커밋 포함), merge 대상 = beautiful-cerf-9498a9 head.
conflict 가능 범위:
- 4d219cd 이후 main-only 커밋이 없다면 fast-forward
- revert commit 있으면 merge commit 생성

### 4) 검증
```bash
python3 scripts/codegen_card_db.py --check
# 예상: ✅ card_db.gd + card_descs.gd match YAML (55 cards)

godot --headless --path godot/ -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -glog=0 -gexit
# 예상: Tests 907, Passing 907

python3 -m unittest scripts.tests.test_r_conditional_validator
# 예상: Ran 11 tests OK
```

### 5) 확인할 파일
- `data/cards/*.yaml` — v2 block 포맷 (trigger_timing inside effects)
- `scripts/codegen_card_db.py` — v2 codegen (load_cards, 1000+ 줄, block 출력)
- `godot/core/data/card_db.gd` — v2 block 구조 (effects 는 block 리스트)
- `godot/core/chain_engine.gd` — `_find_block` 헬퍼 존재
- `.claude/handoff.md` — Phase 2 완료 상태

## 검증 기준 (Sprint Contract Done)

- [ ] main HEAD = beautiful-cerf-9498a9 HEAD (d18d1ce) 또는 그 후속
- [ ] `data/cards/` 에 v2 block YAML 5개 + RULES.md
- [ ] `python3 scripts/codegen_card_db.py --check` exit 0
- [ ] GUT 907/907 pass
- [ ] Stage 1-3 의 validator 들은 **이 시점에서 없는 상태** (다음 Task에서 재적용)

## 주의

- **Stage 1-3 의 validator 는 v1 기반**이라 v2 YAML 과 호환 안 됨. Revert 후 필수.
- 이 Task 이후 **Task 2-4 가 Stage 1-3 의 정수를 v2 코드에 재구현**.
- 만약 main 에 ff2fdb3~d18d1ce 일부만 선별해서 cherry-pick 하는 복잡한 전략은 **불필요**. fast-forward or clean merge 가 기본 경로.

## 완료 후 다음 Task

병렬 가능 (독립 세션에서):
- **Task 2** (p2-task2-stage1-validators.md) — Stage 1 의 defensive validators 를 v2 codegen 에 추가
- **Task 3** (p2-task3-stage2-guards.md) — PC conditional 순회 + theme_system base class guard 검증/추가
- **Task 4** (p2-task4-stage3-max-act-override.md) — sim template mutation 완전 제거 + max_activation_override 도입
