#!/usr/bin/env python3
"""Fail closed on incomplete native execution; export bounded, payload-free evidence."""
import argparse
from collections import Counter
import html
import json
from pathlib import Path
import xml.etree.ElementTree as ET

PREFIX = "io.github.natri3.assistant.security."
EXPECTED = tuple((PREFIX + cls, method) for cls, methods in (
    ("DeviceSecurityTest", ("manifestDisablesBackup", "realAuthRequiredKeysAndDedicatedRevokeBeforeDestruction")),
    ("DomainCacheSecurityTest", ("realAuthenticatedAtomicDomainRoundtripWrongAadAndSessionIsolation",)),
    ("NativeLifecycleVaultTest", ("expiredAuthenticationDeniesBothKeysUntilNativePrompt", "pauseAndRecreateFenceSessionAndEpoch", "cancelNativePromptLeavesProtectedCallsLocked", "interruptedAtomicWritePreservesCommittedVaultAndDestroyRemovesSidecars")),
) for method in methods)


def check(directory, started_at=0):
    observed = []
    problems = set()
    paths = sorted(directory.glob("**/TEST-*.xml")) if directory.is_dir() else []
    if not paths:
        problems.add("NO_RESULTS")
    if len(paths) > 16:
        problems.add("EXCESS_RESULTS")
        paths = paths[:16]
    for path in paths:
        if path.stat().st_mtime < started_at:
            problems.add("STALE_RESULTS")
        if path.stat().st_size > 1024 * 1024:
            problems.add("OVERSIZE_XML")
            continue
        try:
            root = ET.parse(path).getroot()
            if root.tag not in ("testsuite", "testsuites"):
                raise ValueError()
            for suite in root.iter("testsuite"):
                if suite.find("failure") is not None or suite.find("error") is not None:
                    problems.add("SUITE_FAILURE")
                for key in ("failures", "errors", "skipped", "disabled"):
                    if int(suite.get(key, "0")) != 0:
                        problems.add("SUITE_" + key.upper())
                if "tests" in suite.attrib and int(suite.get("tests")) != len(list(suite.iter("testcase"))):
                    problems.add("INCOMPLETE_SUITE")
            for case in root.iter("testcase"):
                identity = (case.get("classname", ""), case.get("name", ""))
                state = "FAIL" if case.find("failure") is not None or case.find("error") is not None else "SKIPPED" if case.find("skipped") is not None else "PASS"
                observed.append((identity, state))
        except (ET.ParseError, ValueError, OSError):
            problems.add("INVALID_XML")
    counts = Counter(identity for identity, _ in observed)
    if any(identity not in EXPECTED for identity in counts):
        problems.add("UNEXPECTED_TEST")
    scenarios = []
    for identity in EXPECTED:
        count = counts[identity]
        state = "MISSING" if count == 0 else "DUPLICATE" if count != 1 else next(state for key, state in observed if key == identity)
        if state != "PASS":
            problems.add(state)
        scenarios.append({"class": identity[0], "method": identity[1], "status": state})
    return {"status": "FAIL" if problems else "PASS", "problems": sorted(problems), "observed_tests": len(observed), "scenarios": scenarios}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--started-at", type=float, default=0)
    args = parser.parse_args()
    summary = check(args.results, args.started_at)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "scenarios.json").write_text(json.dumps(summary, indent=2) + "\n")
    # Never copy runner failure messages, stdout, UI trees or data into artifacts.
    suite = ET.Element("testsuite", name="AS91-native", tests="7", failures=str(sum(s["status"] != "PASS" for s in summary["scenarios"])))
    if summary["problems"]:
        suite.set("errors", "1")
        ET.SubElement(suite, "error", message=",".join(summary["problems"]))
    for scenario in summary["scenarios"]:
        case = ET.SubElement(suite, "testcase", classname=scenario["class"], name=scenario["method"])
        if scenario["status"] != "PASS":
            ET.SubElement(case, "failure", message=scenario["status"])
    ET.ElementTree(suite).write(args.output / "instrumentation.xml", encoding="utf-8", xml_declaration=True)
    rows = "".join("<tr><td>" + html.escape(s["method"]) + "</td><td>" + s["status"] + "</td></tr>" for s in summary["scenarios"])
    (args.output / "instrumentation.html").write_text("<!doctype html><meta charset=utf-8><title>AS91 native execution</title><h1>" + summary["status"] + "</h1><p>Sanitized scenario accounting. See receipt for raw Gradle status and run identity.</p><table>" + rows + "</table>")
    print(json.dumps({"status": summary["status"], "problems": summary["problems"]}))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
