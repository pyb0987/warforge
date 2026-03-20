# 체인 아미 (Chain Army)

트리거 체인 로그라이크 덱빌더 — 발라트로 × 스타 선술집 × 유희왕 OCG의 핵심 재미를 결합한 PvE 로그라이크.

> **WIP** — 게임 기획 단계입니다. 코드 구현은 아직 시작하지 않았습니다.

## Core Fantasy

불합리할 정도로 강한 적 앞에서, 내가 직접 키운 군대와 조합이 "사기"가 되어 작동하는 순간.

## Features

- **성장 체인** — 빌드 페이즈에서 카드 트리거가 연쇄 발동하여 군대를 키우는 핵심 메카닉
- **2층 유닛/카드 구조** — 유닛(공유 DB) + 카드(유닛 조합 + 트리거 효과) 분리 아키텍처
- **4테마 + 중립** — 스팀펑크/드루이드/충군/군대, 테마별 고유 키워드와 크로스 테마 시너지
- **리얼타임 대규모 전투** — 20v20+ 군집 오토배틀, SC1 스타일 스탯 체계
- **로그라이크 런** — 15라운드, 28~35분 세션, 매 런마다 새 빌드

## Tech Stack

- **Language**: Python 3 (밸런스 시뮬레이터)
- **Game Engine**: 미정

## Setup

```bash
# 밸런스 시뮬레이터 실행 (⚠ deprecated)
python3 sim/simulate.py
python3 sim/simulate.py -n 50 -v    # verbose 50 runs
python3 sim/simulate.py --seed 42   # reproducible
```

## Project Structure

```
DESIGN.md              마스터 기획 문서
docs/design/           상세 설계 11편
docs/episodes/         의사결정 에피소드 기록
sim/                   밸런스 시뮬레이터
```

## License

MIT
