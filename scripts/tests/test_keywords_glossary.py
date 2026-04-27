"""Tests for data/keywords.yaml glossary integrity + desc_gen drift detection.

Run:  python3 -m unittest scripts.tests.test_keywords_glossary

Background — failures/011-new-card-desc-codegen-pattern-violation.md:
  신규 13장 desc 핸들러가 키워드 한글 표기를 하드코딩 (예: "신병 추가" / "비-중립 대상").
  P5 사다리 3단계: 사전 단일 진실 소스 + drift 차단 validator.

Validator 책임:
  T1. keywords.yaml 스키마 무결성 (모든 layer1/layer2/filter 항목이 'name' 또는 'text' 보유)
  T2. card_desc_gen.py 가 glossary keyword 한글 표기를 raw 문자열로 하드코딩하지 않음
       — _kw() / _kw_filter() / _kw_reaction() 또는 정상 OE_PREFIX 경유 만 허용
  T3. 신규 desc 핸들러 작성 시 사전 우회 시도하면 fail
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

try:
    import yaml
except ImportError:
    print("PyYAML 필요 — pip install pyyaml", file=sys.stderr)
    raise


def _load_glossary() -> dict:
    return yaml.safe_load((ROOT / "data/keywords.yaml").read_text(encoding="utf-8"))


def _read_desc_gen() -> str:
    return (ROOT / "scripts/card_desc_gen.py").read_text(encoding="utf-8")


# desc_gen.py 내부에서 raw 문자열 하드코딩이 허용되는 위치 — 사전 정의 자체.
# 라인 번호 기반 whitelist 는 fragile; 대신 함수 이름으로 화이트리스트.
ALLOWED_FUNCTIONS = {
    "_load_keywords", "_kw", "_kw_reaction", "_kw_filter",
    "_KEYWORDS_CACHE",
}


class TestKeywordsGlossarySchema(unittest.TestCase):
    """T1: keywords.yaml 스키마 무결성."""

    def setUp(self):
        self.g = _load_glossary()

    def test_layer1_entries_have_required_fields(self):
        for code, entry in self.g.get("layer1", {}).items():
            self.assertIn("name", entry, f"layer1.{code} missing 'name'")
            self.assertIn("reaction_prefix", entry,
                          f"layer1.{code} missing 'reaction_prefix'")

    def test_layer2_entries_have_required_fields(self):
        for code, entry in self.g.get("layer2", {}).items():
            self.assertIn("name", entry, f"layer2.{code} missing 'name'")
            self.assertIn("reaction_prefix", entry,
                          f"layer2.{code} missing 'reaction_prefix'")

    def test_target_filters_have_text(self):
        for code, entry in self.g.get("target_filters", {}).items():
            self.assertIn("text", entry,
                          f"target_filters.{code} missing 'text'")

    def test_reaction_origin_keys(self):
        ro = self.g.get("reaction_origin", {})
        self.assertIn("any", ro)
        self.assertIn("other_only", ro)


class TestDescGenNoReactionPrefixHardcoding(unittest.TestCase):
    """T2: '[반응] {keyword}' 형태 raw 문자열 차단.

    이 패턴은 반드시 _kw_reaction() 또는 NON_GLOSSARY_OE_PREFIX dict 를 통해야 함.
    failures/011 의 직접 원인이었던 drift 범주.

    합법 등장 (whitelist):
      - NON_GLOSSARY_OE_PREFIX dict literal 안 (★합성/리롤/판매 — glossary 외)
      - _kw_reaction 내부에서 동적 조립한 fallback ('[반응] {src_label} {body}')
    """

    def test_no_hardcoded_reaction_prefix(self):
        src = _read_desc_gen()
        violations: list[str] = []
        # 합법 함수 (string.replace 의 1번/2번 인자 등 인프라 코드).
        # 함수 영역 추적: 'def NAME(' 라인부터 다음 'def ' 라인까지.
        ALLOWED_FUNCS = {"get_oe_prefix", "_kw_reaction"}
        in_allowed = False
        cur_func: str | None = None
        for i, line in enumerate(src.split("\n"), start=1):
            stripped = line.strip()
            m = re.match(r"def\s+(\w+)\s*\(", stripped)
            if m:
                cur_func = m.group(1)
                in_allowed = cur_func in ALLOWED_FUNCS
            if stripped.startswith("#"):
                continue
            if in_allowed:
                continue
            # raw "[반응] ..." literal 검출
            for m2 in re.finditer(r'"\[반응\][^"]*"', line):
                val = m2.group(0)
                # f-string 내 변수 보간 ({...}) 이 있으면 동적 조립 — 허용
                if "{" in val and "}" in val:
                    continue
                # NON_GLOSSARY_OE_PREFIX 합법 항목 (★합성/리롤/판매)
                if "MERGE" in line or "REROLL" in line or "SELL" in line:
                    continue
                violations.append(f"line {i}: raw reaction prefix → {val}")
        violations = sorted(set(violations))
        self.assertEqual(violations, [], "\n".join(violations))


class TestDescGenNoFilterHardcoding(unittest.TestCase):
    """T3: 필터 텍스트 하드코딩 차단 (비-중립 / 비-드루이드 / 비-스팀펑크).

    target_filters glossary 의 'text' head 어절이 raw 문자열로 등장하면 fail.
    합법: _kw_filter() 호출 결과를 변수로 받아 사용하는 것.
    """

    def test_no_hardcoded_filter_text(self):
        g = _load_glossary()
        src = _read_desc_gen()
        violations: list[str] = []
        keyword_fragments = []
        for entry in g.get("target_filters", {}).values():
            t = entry["text"]
            head = t.split(" ")[0]
            if head and head.startswith("비-"):
                keyword_fragments.append(head)
        for i, line in enumerate(src.split("\n"), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            # docstring 안의 fragment 는 무시 (큰따옴표 셋으로 시작/끝)
            if stripped.startswith('"""') or stripped.startswith("'''"):
                continue
            for frag in keyword_fragments:
                pattern = rf'"[^"]*{re.escape(frag)}[^"]*"'
                if re.search(pattern, line):
                    violations.append(
                        f"line {i}: hardcoded filter '{frag}' "
                        f"in {stripped[:80]}"
                    )
        violations = sorted(set(violations))
        self.assertEqual(violations, [], "\n".join(violations))


if __name__ == "__main__":
    unittest.main()
