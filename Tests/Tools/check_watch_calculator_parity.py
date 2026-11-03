#!/usr/bin/env python3
"""Verify the phone port preserves the vetted watch's calculation verbatim.

Run from any directory with Python 3. The baseline digests identify the functions
at def433d9b4fa200fefe583e2eef33c4431d9b3ff, before the calculator feature.
This source check complements the Swift fixture tests; it is not an app build.
"""

import hashlib
from pathlib import Path
import re
import textwrap


ROOT = Path(__file__).resolve().parents[2]
BASELINE = {
    "updateRecommendedBolus": "85e31023410af549d58baf429991a45733a23e54f1afcd66097de0cc804f002a",
    "lookupScheduleValue": "8907721a4744b714a51ec0b78e853f9e34d3e0264704c53079b93a090c10b6e7",
}


def function(source, name):
    match = re.search(r"\bfunc " + re.escape(name) + r"\s*\(", source)
    if match is None:
        raise AssertionError(f"Missing function: {name}")
    start = match.start()
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise AssertionError(f"Unclosed function: {name}")
    return "\n".join(
        line.rstrip()
        for line in textwrap.dedent(source[start:end]).strip().splitlines()
    )


def main():
    watch = (ROOT / "LoopFollowWatch/BGFetcher.swift").read_text()
    phone = (
        ROOT / "LoopFollow/Remote/BolusCalculator/PhoneMealBolusCalculator.swift"
    ).read_text()
    for name, expected in BASELINE.items():
        watch_function = function(watch, name)
        actual = hashlib.sha256(watch_function.encode()).hexdigest()
        assert actual == expected, f"Watch baseline changed: {name}"
        assert function(phone, name) == watch_function, f"Phone differs from watch: {name}"
        print(f"PASS: {name} matches the unchanged watch baseline")


if __name__ == "__main__":
    main()
