"""Exercise result accounting against incomplete, skipped, duplicated and crashed runs."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

CASES = {
    "DeviceSecurityTest": ["manifestDisablesBackup", "realAuthRequiredKeysAndDedicatedRevokeBeforeDestruction"],
    "DomainCacheSecurityTest": ["realAuthenticatedAtomicDomainRoundtripWrongAadAndSessionIsolation"],
    "NativeLifecycleVaultTest": ["expiredAuthenticationDeniesBothKeysUntilNativePrompt", "pauseAndRecreateFenceSessionAndEpoch", "cancelNativePromptLeavesProtectedCallsLocked", "interruptedAtomicWritePreservesCommittedVaultAndDestroyRemovesSidecars"],
}


class ResultAccountingTest(unittest.TestCase):
    def run_fixture(self, change=lambda suite: None, stale=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            results = root / "results"
            results.mkdir()
            suite = ET.Element("testsuite", tests="7", failures="0", errors="0", skipped="0")
            for cls, names in CASES.items():
                for name in names:
                    ET.SubElement(suite, "testcase", classname="io.github.natri3.assistant.security." + cls, name=name, time="0.1")
            change(suite)
            ET.ElementTree(suite).write(results / "TEST-native.xml")
            command = [sys.executable, str(Path(__file__).with_name("check_instrumentation_results.py")), str(results), "--output", str(root / "evidence")]
            if stale:
                command += ["--started-at", "9999999999"]
            result = subprocess.run(command, capture_output=True, text=True)
            summary_path = root / "evidence" / "scenarios.json"
            summary = json.loads(summary_path.read_text()) if summary_path.exists() else None
            return result.returncode, summary

    def test_exact_seven_pass_and_export_small_evidence(self):
        code, summary = self.run_fixture()
        self.assertEqual(0, code)
        self.assertEqual("PASS", summary["status"])
        self.assertEqual(7, len(summary["scenarios"]))

    def test_skip_is_not_native_authentication_evidence(self):
        code, summary = self.run_fixture(lambda s: ET.SubElement(s[1], "skipped"))
        self.assertNotEqual(0, code)
        self.assertIsNotNone(summary, "accounting must emit scenario evidence even on failure")
        self.assertEqual("SKIPPED", summary["scenarios"][1]["status"])

    def test_backup_only_missing_failure_duplicate_and_crash_are_rejected(self):
        mutations = [lambda s: [s.remove(c) for c in list(s)[1:]],
                     lambda s: ET.SubElement(s[0], "failure", message="SENSITIVE PAYLOAD"),
                     lambda s: s.append(ET.fromstring(ET.tostring(s[0]))),
                     lambda s: ET.SubElement(s, "error", message="crash")]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                code, summary = self.run_fixture(mutation)
                self.assertNotEqual(0, code)
                self.assertIsNotNone(summary, "accounting must emit scenario evidence even on failure")
                self.assertEqual("FAIL", summary["status"])
                self.assertNotIn("SENSITIVE", json.dumps(summary))

    def test_stale_xml_rejected(self):
        self.assertNotEqual(0, self.run_fixture(stale=True)[0])

    def test_missing_output_directory_is_pending_not_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("check_instrumentation_results.py")), directory + "/absent", "--output", directory + "/evidence"], capture_output=True)
            self.assertNotEqual(0, result.returncode)


if __name__ == "__main__":
    unittest.main()
