#!/usr/bin/env python3
"""Lint: 카드 생성/배치는 GameState.spawn_card / add_clone 단일 진입점만 허용.

검사 대상:
  1. CardInstance.create(...) 직접 호출
  2. bench[..] = / board[..] = 형태 카드 대입

화이트리스트:
  - godot/core/game_state.gd  (spawn_card / add_clone funnel)
  - godot/tests/              (테스트 셋업)

라인 단위 opt-out:
  - 라인에 "# lint:allow card-create" 주석 → 해당 라인 제외 (시각 미리보기 등)
  - 라인에 "# lint:allow zone-assign" 주석 → 해당 라인 제외 (스왑/이동 등)

회귀 검증: SS-009 (search-set 등재).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

WHITELIST_PATHS = (
    "godot/core/game_state.gd",
    "godot/tests/",
)

ALLOW_CREATE = "lint:allow card-create"
ALLOW_ZONE = "lint:allow zone-assign"

CREATE_RE = re.compile(r"\bCardInstance\.create\s*\(")
# bench[X] = Y 또는 board[X] = Y. 비교(`==`)는 제외.
ZONE_RE = re.compile(r"\b(bench|board)\s*\[[^\]]*\]\s*=(?!=)")


def is_whitelisted(rel_path: str) -> bool:
    return any(rel_path == p or rel_path.startswith(p) for p in WHITELIST_PATHS)


def scan_file(path: Path) -> list[str]:
    rel = path.relative_to(REPO_ROOT).as_posix()
    if is_whitelisted(rel):
        return []
    violations: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("##"):
            continue
        # 라인 단위 opt-out
        if CREATE_RE.search(line) and ALLOW_CREATE not in line:
            violations.append(
                f"{rel}:{line_no}: CardInstance.create — "
                f"GameState.spawn_card 또는 add_clone 사용. "
                f"의도된 비-spawn (시각 미리보기 등) 시 '# {ALLOW_CREATE}' 주석.\n"
                f"  > {stripped}"
            )
        if ZONE_RE.search(line) and ALLOW_ZONE not in line:
            violations.append(
                f"{rel}:{line_no}: bench/board 직접 대입 — "
                f"GameState.add_to_bench 사용 또는 spawn_card 경유. "
                f"스왑/이동 등 의도된 사용 시 '# {ALLOW_ZONE}' 주석.\n"
                f"  > {stripped}"
            )
    return violations


def main() -> int:
    targets: list[Path] = []
    if len(sys.argv) > 1:
        # pre-commit hook이 staged 파일 전달
        for arg in sys.argv[1:]:
            p = (REPO_ROOT / arg).resolve()
            if p.suffix == ".gd" and p.is_file():
                targets.append(p)
    else:
        # 단독 실행: godot/ 전체 .gd 파일 스캔
        for p in (REPO_ROOT / "godot").rglob("*.gd"):
            targets.append(p)

    all_violations: list[str] = []
    for path in targets:
        all_violations.extend(scan_file(path))

    if all_violations:
        print("[lint_card_spawn] 위반 발견:")
        for v in all_violations:
            print(f"  {v}")
        print(
            f"\n총 {len(all_violations)}건. "
            "GameState.spawn_card (구매/보스 보상/부적/카드효과로 새 카드 생성) "
            "또는 add_clone (auto-merge 없이 시스템 카드 추가)을 사용하세요.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
