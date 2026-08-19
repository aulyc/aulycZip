import importlib.util
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "aulyczip_release_tool", PROJECT_ROOT / "scripts" / "release_tool.py"
)
release_tool = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(release_tool)


class ReleaseToolTests(unittest.TestCase):
    def test_standards_check_requires_explicit_dependency_root(self):
        environment = os.environ.copy()
        environment.pop("STANDARDS_ROOT", None)
        result = subprocess.run(
            ["bash", str(PROJECT_ROOT / "scripts" / "standards-check.sh")],
            cwd=PROJECT_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 64)
        self.assertIn("STANDARDS_ROOT is required", result.stderr)

    def test_standards_check_rejects_incomplete_dependency_root(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = os.environ.copy()
            environment["STANDARDS_ROOT"] = directory
            result = subprocess.run(
                ["bash", str(PROJECT_ROOT / "scripts" / "standards-check.sh")],
                cwd=PROJECT_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 66)
        self.assertIn("central standards dependency is missing", result.stderr)

    def test_version_source_is_current_project_plist(self):
        with (PROJECT_ROOT / "Config" / "Info.plist").open("rb") as handle:
            plist = plistlib.load(handle)
        expected = (
            plist["CFBundleShortVersionString"],
            int(plist["CFBundleVersion"]),
        )
        self.assertEqual(release_tool.version_identity(), expected)

    def test_stable_version_parser_rejects_prerelease(self):
        self.assertEqual(release_tool.version_tuple("1.2.3"), (1, 2, 3))
        with self.assertRaises(release_tool.ReleaseError):
            release_tool.version_tuple("1.2.3-beta.1")

    def test_changelog_preparation_preserves_unreleased_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "CHANGELOG.md"
            path.write_text(
                "# Changelog\n\n## [Unreleased]\n\n- New feature\n\n"
                "## [0.1.0] - 2026-08-01\n\n- Previous\n",
                encoding="utf-8",
            )
            result = release_tool.prepared_changelog(path, "1.0.0")
            self.assertIn("## [1.0.0] - ", result)
            self.assertIn("- New feature", result)
            self.assertIn("## [0.1.0] - 2026-08-01", result)

    def test_final_provenance_requires_complete_remote_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            provenance = self.make_provenance(root)
            value, artifact = release_tool.validate_provenance(
                provenance, require_remote=True
            )
            self.assertEqual(value["sourceRemoteCommit"], "a" * 40)
            self.assertTrue(artifact.is_file())

            broken = json.loads(provenance.read_text(encoding="utf-8"))
            broken.pop("sourceRemoteVerifiedAt")
            provenance.write_text(json.dumps(broken), encoding="utf-8")
            with self.assertRaises(release_tool.ReleaseError):
                release_tool.validate_provenance(provenance, require_remote=False)

    def test_publication_orders_source_push_before_mirrors(self):
        script = (PROJECT_ROOT / "scripts" / "publish-release.sh").read_text(
            encoding="utf-8"
        )
        self.assertLess(
            script.index("standards_check.py"),
            script.index("formal_release_git.py\" push"),
        )
        self.assertLess(
            script.index("formal_release_git.py\" push"),
            script.index("publish-update-mirrors.sh"),
        )
        formal = (PROJECT_ROOT / "scripts" / "formal-release.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("git worktree add --detach", formal)
        self.assertIn("xcrun notarytool submit", formal)
        self.assertIn("xcrun stapler validate", formal)

    def test_dual_mirror_wrapper_scopes_project_argument(self):
        script = (PROJECT_ROOT / "scripts" / "dual-mirror-release.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("prepare|gitee-auth-check)", script)
        self.assertIn('python3 "$TOOL" "$PHASE" --project aulyczip "$@"', script)
        self.assertIn("preflight|publish|verify)", script)
        self.assertIn('python3 "$TOOL" "$PHASE" "$@"', script)

    def make_provenance(self, root: Path) -> Path:
        artifact_name = "aulycZip-1.0.0-build.2-formal-macos-arm64.dmg"
        artifact = root / artifact_name
        artifact.write_bytes(b"verified formal artifact fixture")
        commit = "a" * 40
        value = {
            "$schema": "urn:aulyc:release-provenance:1",
            "project": "aulycZip",
            "releaseProfile": "macos-arm64-app",
            "releaseChannel": "formal",
            "version": "1.0.0",
            "buildNumber": 2,
            "tag": "1.0.0",
            "commit": commit,
            "dirty": False,
            "builtAt": "2026-08-18T00:00:00Z",
            "artifacts": [
                {"file": artifact_name, "sha256": release_tool.sha256(artifact)}
            ],
            "architecture": "arm64",
            "bundleIdentifier": "com.aulyc.aulyczip",
            "bundleName": "aulycZip",
            "executableName": "aulycZip",
            "minimumSystemVersion": "14.0",
            "signatureType": "developer-id",
            "teamIdentifier": "M9M7M2ARFD",
            "hardenedRuntime": True,
            "entitlements": {},
            "notarized": True,
            "notarizationSubmissionId": "00000000-0000-0000-0000-000000000000",
            "appExecutableSha256": "1" * 64,
            "infoPlistSha256": "2" * 64,
            "sourceRepository": "aulyc/aulycZip",
            "sourceBranch": "main",
            "sourceRemoteCommit": commit,
            "sourceRemoteTagCommit": commit,
            "sourceRemoteVerifiedAt": "2026-08-18T00:05:00Z",
        }
        path = root / "release-provenance.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path


if __name__ == "__main__":
    unittest.main()
