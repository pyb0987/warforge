---
name: Layer 1 밸런스 고정 결정
description: Layer 1↔2 순환 의존 해소를 위해 게임 밸런스를 기본값에 고정하고 AI만 개선하는 전략
type: project
---

2026-04-13 Layer 1 autoresearch 중단, best_genome.json을 create_default() 값으로 고정.

**Why:** Layer 1↔2 순환 의존으로 "못하는 AI에 맞춘 왜곡된 밸런스"가 생김 (R12-15 CP 8.0, income 7/8/9). AI 승률 druid/steampunk 0%, 머지율 1.33. 파라미터 튜닝으로는 구조적 한계 탈출 불가.

**How to apply:**
- best_genome.json은 protect-files 훅으로 보호 중. Layer 2 연구 동안 수정 금지.
- AI가 기본 밸런스에서 합리적 승률(~50%)을 낼 때까지 Layer 1 재개하지 않음.
- Layer 1 재개 시 이 메모리와 traces/evolution/011 참조.
- 이전 best_genome (왜곡값): CP 2.129→8.0, income 7/8/9, Lv3=9g, boss hp_mult=1.46
