#!/usr/bin/env python3
"""Release metadata, artifact, and provenance helpers for aulycZip."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
INFO_PLIST = ROOT / "Config" / "Info.plist"
CHANGELOG = ROOT / "CHANGELOG.md"
CHANGELOG_ZH_CN = ROOT / "CHANGELOG.zh-CN.md"
ADOPTION = ROOT / ".codex" / "standards.json"
STABLE_SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
REMOTE_FIELDS = {
    "sourceRepository",
    "sourceBranch",
    "sourceRemoteCommit",
    "sourceRemoteTagCommit",
    "sourceRemoteVerifiedAt",
}
BASE_PROVENANCE_FIELDS = {
    "$schema",
    "project",
    "releaseProfile",
    "releaseChannel",
    "version",
    "buildNumber",
    "tag",
    "commit",
    "dirty",
    "builtAt",
    "artifacts",
    "architecture",
    "bundleIdentifier",
    "bundleName",
    "executableName",
    "minimumSystemVersion",
    "signatureType",
    "teamIdentifier",
    "hardenedRuntime",
    "entitlements",
    "notarized",
    "notarizationSubmissionId",
    "appExecutableSha256",
    "infoPlistSha256",
}


class ReleaseError(Exception):
    pass


def run(command: list[str], cwd: Path | None = None, combine: bool = False) -> str:
    completed = subprocess.run(
        command,
        cwd=str(cwd or ROOT),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT if combine else subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        detail = (completed.stdout or completed.stderr or "").strip()
        raise ReleaseError(f"{command[0]} failed: {detail}")
    return completed.stdout.strip()


def git(root: Path, *arguments: str) -> str:
    return run(["git", "-C", str(root), *arguments], cwd=root)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_plist(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise ReleaseError(f"invalid plist {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReleaseError(f"plist root must be a dictionary: {path}")
    return value


def write_plist(path: Path, value: dict) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            plistlib.dump(value, handle, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def load_json(path: Path, description: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReleaseError(f"invalid {description}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReleaseError(f"{description} must be a JSON object")
    return value


def atomic_write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}-", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def version_identity(require_stable: bool = False) -> tuple[str, int]:
    plist = read_plist(INFO_PLIST)
    version = plist.get("CFBundleShortVersionString")
    raw_build = plist.get("CFBundleVersion")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        raise ReleaseError("CFBundleShortVersionString must be SemVer")
    if require_stable and not STABLE_SEMVER.fullmatch(version):
        raise ReleaseError("formal release version must be stable SemVer")
    try:
        build = int(raw_build)
    except (TypeError, ValueError) as exc:
        raise ReleaseError("CFBundleVersion must be a positive integer") from exc
    if build <= 0 or str(build) != str(raw_build):
        raise ReleaseError("CFBundleVersion must be a canonical positive integer")
    expected = {
        "CFBundleIdentifier": "com.aulyc.aulyczip",
        "CFBundleName": "aulycZip",
        "CFBundleExecutable": "aulycZip",
        "LSMinimumSystemVersion": "14.0",
    }
    for field, value in expected.items():
        if plist.get(field) != value:
            raise ReleaseError(f"unexpected {field}")
    return version, build


def changelog_has_release(path: Path, version: str) -> bool:
    text = path.read_text(encoding="utf-8")
    return re.search(
        rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", text, re.M
    ) is not None


def version_tuple(value: str) -> tuple[int, int, int]:
    match = STABLE_SEMVER.fullmatch(value)
    if match is None:
        raise ReleaseError("target version must be stable SemVer")
    return tuple(int(part) for part in match.groups())


def prepared_changelog(path: Path, target_version: str) -> str:
    text = path.read_text(encoding="utf-8")
    marker = "## [Unreleased]"
    if not text.startswith("# ") or marker not in text:
        raise ReleaseError(f"{path.name} has no Unreleased heading")
    marker_end = text.index(marker) + len(marker)
    body = text[marker_end:].lstrip("\n")
    first_heading = re.search(r"^## \[", body, re.M)
    unreleased_body = body[: first_heading.start()] if first_heading else body
    if not unreleased_body.strip():
        raise ReleaseError(f"{path.name} Unreleased section is empty")
    date = dt.date.today().isoformat()
    return text[:marker_end] + f"\n\n## [{target_version}] - {date}\n\n" + body


def command_version_check(args: argparse.Namespace) -> None:
    version, build = version_identity(require_stable=args.release)
    if args.release:
        for path in (CHANGELOG, CHANGELOG_ZH_CN):
            if not changelog_has_release(path, version):
                raise ReleaseError(f"{path.name} has no dated heading for {version}")
    print(f"version identity valid: {version} build {build}")


def command_prepare(args: argparse.Namespace) -> None:
    current_version, current_build = version_identity()
    if version_tuple(args.version) <= version_tuple(current_version):
        raise ReleaseError("target version must be greater than current version")
    if args.build <= current_build:
        raise ReleaseError("target build must be greater than current build")
    updated_english = prepared_changelog(CHANGELOG, args.version)
    updated_chinese = prepared_changelog(CHANGELOG_ZH_CN, args.version)
    plist = read_plist(INFO_PLIST)
    plist["CFBundleShortVersionString"] = args.version
    plist["CFBundleVersion"] = str(args.build)
    write_plist(INFO_PLIST, plist)
    CHANGELOG.write_text(updated_english, encoding="utf-8")
    CHANGELOG_ZH_CN.write_text(updated_chinese, encoding="utf-8")
    print(f"prepared release metadata: {args.version} build {args.build}")


def codesign_identity(app: Path) -> tuple[str, str, bool]:
    output = run(["codesign", "-dv", "--verbose=4", str(app)], combine=True)
    team_match = re.search(r"^TeamIdentifier=(.+)$", output, re.M)
    authority_match = re.search(r"^Authority=(.+)$", output, re.M)
    runtime = re.search(r"^CodeDirectory .*\bflags=.*\(runtime\)", output, re.M) is not None
    if team_match is None or authority_match is None:
        raise ReleaseError("Developer ID signature identity is incomplete")
    authority = authority_match.group(1).strip()
    if not authority.startswith("Developer ID Application:"):
        raise ReleaseError("application is not Developer ID signed")
    return team_match.group(1).strip(), authority, runtime


def app_identity(app: Path, verify_source_resources: bool = False) -> dict:
    info_path = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / "aulycZip"
    resources = {
        ROOT / "Resources" / "AppIcon.icns": app / "Contents" / "Resources" / "AppIcon.icns",
        ROOT / "design" / "menuBarIcon.svg": app / "Contents" / "Resources" / "MenuBarIcon.svg",
    }
    if not info_path.is_file() or not executable.is_file():
        raise ReleaseError("application bundle is incomplete")
    if verify_source_resources:
        for source, bundled in resources.items():
            if not bundled.is_file() or sha256(source) != sha256(bundled):
                raise ReleaseError(f"runtime resource mismatch: {bundled}")
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], combine=True)
    architectures = run(["lipo", "-archs", str(executable)]).split()
    if architectures != ["arm64"]:
        raise ReleaseError(f"unexpected application architectures: {architectures}")
    team, authority, runtime = codesign_identity(app)
    if team != "M9M7M2ARFD" or not runtime:
        raise ReleaseError("unexpected signing team or missing Hardened Runtime")
    entitlements = run(["codesign", "-d", "--entitlements", ":-", str(app)], combine=True)
    if "<key>" in entitlements:
        raise ReleaseError("formal app has unexpected entitlements")
    info = read_plist(info_path)
    return {
        "version": str(info.get("CFBundleShortVersionString")),
        "build": int(info.get("CFBundleVersion")),
        "bundleIdentifier": info.get("CFBundleIdentifier"),
        "bundleName": info.get("CFBundleName"),
        "executableName": info.get("CFBundleExecutable"),
        "minimumSystemVersion": info.get("LSMinimumSystemVersion"),
        "commit": info.get("AulycZipGitCommit"),
        "releaseChannel": info.get("AulycZipReleaseChannel"),
        "tag": info.get("AulycZipReleaseTag"),
        "dirty": info.get("AulycZipBuildDirty"),
        "teamIdentifier": team,
        "signatureAuthority": authority,
        "hardenedRuntime": True,
        "appExecutableSha256": sha256(executable),
        "infoPlistSha256": sha256(info_path),
    }


def verify_dmg(dmg: Path) -> None:
    run(["codesign", "--verify", "--verbose=2", str(dmg)], combine=True)
    run(["xcrun", "stapler", "validate", str(dmg)], combine=True)
    run(
        [
            "spctl", "-a", "-vvv", "-t", "open", "--context",
            "context:primary-signature", str(dmg),
        ],
        combine=True,
    )


def exact_tag_identity(source_root: Path, tag: str) -> str:
    if git(source_root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise ReleaseError("exact-tag source is dirty")
    commit = git(source_root, "rev-parse", "HEAD")
    git(source_root, "rev-parse", "--verify", f"refs/tags/{tag}^{{tag}}")
    if git(source_root, "rev-list", "-n", "1", f"refs/tags/{tag}") != commit:
        raise ReleaseError("annotated tag does not point to exact source commit")
    return commit


def notary_submission_id(path: Path) -> str:
    value = load_json(path, "notarytool result")
    if value.get("status") != "Accepted":
        raise ReleaseError("notarization status is not Accepted")
    submission_id = value.get("id")
    if not isinstance(submission_id, str) or not submission_id:
        raise ReleaseError("notarization submission ID is missing")
    return submission_id


def command_verify_candidate(args: argparse.Namespace) -> None:
    version, build = version_identity(require_stable=True)
    identity = app_identity(args.app.resolve(), verify_source_resources=True)
    expected_commit = git(ROOT, "rev-parse", "HEAD")
    expected = {
        "version": version,
        "build": build,
        "bundleIdentifier": "com.aulyc.aulyczip",
        "minimumSystemVersion": "14.0",
        "commit": expected_commit,
        "releaseChannel": "candidate",
        "tag": version,
        "dirty": False,
        "teamIdentifier": "M9M7M2ARFD",
        "hardenedRuntime": True,
    }
    for field, value in expected.items():
        if identity.get(field) != value:
            raise ReleaseError(f"candidate field {field} is invalid")
    print(f"release candidate valid: {version} build {build}")


def command_write_provenance(args: argparse.Namespace) -> None:
    source_root = args.source_root.resolve()
    app = args.app.resolve()
    dmg = args.dmg.resolve()
    output = args.output.resolve()
    if not app.is_dir() or not dmg.is_file():
        raise ReleaseError("formal App or DMG is missing")
    if not STABLE_SEMVER.fullmatch(args.tag):
        raise ReleaseError("formal tag must be stable SemVer")
    commit = exact_tag_identity(source_root, args.tag)
    identity = app_identity(app, verify_source_resources=True)
    expected = {
        "version": args.tag,
        "bundleIdentifier": "com.aulyc.aulyczip",
        "bundleName": "aulycZip",
        "executableName": "aulycZip",
        "minimumSystemVersion": "14.0",
        "commit": commit,
        "releaseChannel": "formal",
        "tag": args.tag,
        "dirty": False,
        "teamIdentifier": "M9M7M2ARFD",
        "hardenedRuntime": True,
    }
    for field, value in expected.items():
        if identity.get(field) != value:
            raise ReleaseError(f"formal App field {field} is invalid")
    verify_dmg(dmg)
    provenance = {
        "$schema": "urn:aulyc:release-provenance:1",
        "project": "aulycZip",
        "releaseProfile": "macos-arm64-app",
        "releaseChannel": "formal",
        "version": identity["version"],
        "buildNumber": identity["build"],
        "tag": args.tag,
        "commit": commit,
        "dirty": False,
        "builtAt": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "artifacts": [{"file": dmg.name, "sha256": sha256(dmg)}],
        "architecture": "arm64",
        "bundleIdentifier": identity["bundleIdentifier"],
        "bundleName": identity["bundleName"],
        "executableName": identity["executableName"],
        "minimumSystemVersion": identity["minimumSystemVersion"],
        "signatureType": "developer-id",
        "teamIdentifier": identity["teamIdentifier"],
        "hardenedRuntime": True,
        "entitlements": {},
        "notarized": True,
        "notarizationSubmissionId": notary_submission_id(args.notary_result.resolve()),
        "appExecutableSha256": identity["appExecutableSha256"],
        "infoPlistSha256": identity["infoPlistSha256"],
    }
    atomic_write_json(output, provenance)
    print(output)


def validate_provenance(path: Path, require_remote: bool) -> tuple[dict, Path]:
    value = load_json(path, "release provenance")
    present_remote = REMOTE_FIELDS.intersection(value)
    if present_remote and present_remote != REMOTE_FIELDS:
        raise ReleaseError("release provenance has incomplete remote identity")
    if require_remote and present_remote != REMOTE_FIELDS:
        raise ReleaseError("release provenance remote identity is not finalized")
    expected_fields = BASE_PROVENANCE_FIELDS | present_remote
    if set(value) != expected_fields:
        raise ReleaseError("release provenance fields do not match the project contract")
    required = {
        "$schema": "urn:aulyc:release-provenance:1",
        "project": "aulycZip",
        "releaseProfile": "macos-arm64-app",
        "releaseChannel": "formal",
        "dirty": False,
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
    }
    for field, expected in required.items():
        if value.get(field) != expected:
            raise ReleaseError(f"release provenance field {field} is invalid")
    version = value.get("version")
    if not isinstance(version, str) or not STABLE_SEMVER.fullmatch(version):
        raise ReleaseError("release provenance version is invalid")
    if value.get("tag") != version:
        raise ReleaseError("release provenance tag does not match version")
    if not isinstance(value.get("buildNumber"), int) or value["buildNumber"] <= 0:
        raise ReleaseError("release provenance build number is invalid")
    commit = value.get("commit")
    if not isinstance(commit, str) or re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        raise ReleaseError("release provenance commit is invalid")
    if not isinstance(value.get("builtAt"), str) or not value["builtAt"].endswith("Z"):
        raise ReleaseError("release provenance build time is invalid")
    if not isinstance(value.get("notarizationSubmissionId"), str):
        raise ReleaseError("release provenance notarization ID is invalid")
    for field in ("appExecutableSha256", "infoPlistSha256"):
        if not isinstance(value.get(field), str) or re.fullmatch(r"[0-9a-f]{64}", value[field]) is None:
            raise ReleaseError(f"release provenance {field} is invalid")
    artifacts = value.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 1:
        raise ReleaseError("release provenance must contain one DMG")
    artifact = artifacts[0]
    expected_name = (
        f"aulycZip-{version}-build.{value['buildNumber']}-formal-macos-arm64.dmg"
    )
    if not isinstance(artifact, dict) or set(artifact) != {"file", "sha256"}:
        raise ReleaseError("release provenance artifact record is invalid")
    if artifact.get("file") != expected_name:
        raise ReleaseError("release provenance artifact name is invalid")
    dmg = path.parent / expected_name
    if not dmg.is_file() or sha256(dmg) != artifact.get("sha256"):
        raise ReleaseError("DMG SHA-256 does not match release provenance")
    if present_remote:
        remote_expected = {
            "sourceRepository": "aulyc/aulycZip",
            "sourceBranch": "main",
            "sourceRemoteCommit": commit,
            "sourceRemoteTagCommit": commit,
        }
        for field, expected in remote_expected.items():
            if value.get(field) != expected:
                raise ReleaseError(f"release provenance field {field} is invalid")
        verified_at = value.get("sourceRemoteVerifiedAt")
        if not isinstance(verified_at, str) or not verified_at.endswith("Z"):
            raise ReleaseError("sourceRemoteVerifiedAt is invalid")
    return value, dmg


def mounted_app(dmg: Path):
    class MountedApp:
        def __enter__(self):
            self.temp = tempfile.TemporaryDirectory(prefix="aulycZip-verify-")
            self.mount = Path(self.temp.name) / "mount"
            self.mount.mkdir()
            run(
                [
                    "hdiutil", "attach", str(dmg), "-nobrowse", "-readonly",
                    "-mountpoint", str(self.mount),
                ]
            )
            self.attached = True
            app = self.mount / "aulycZip.app"
            if not app.is_dir():
                raise ReleaseError("DMG does not contain aulycZip.app")
            return app

        def __exit__(self, exc_type, exc, traceback):
            if getattr(self, "attached", False):
                try:
                    run(["hdiutil", "detach", str(self.mount)])
                except ReleaseError:
                    if exc is None:
                        raise
            self.temp.cleanup()

    return MountedApp()


def compare_app_to_provenance(app: Path, provenance: dict) -> None:
    identity = app_identity(app)
    expected = {
        "version": provenance["version"],
        "build": provenance["buildNumber"],
        "bundleIdentifier": provenance["bundleIdentifier"],
        "bundleName": provenance["bundleName"],
        "executableName": provenance["executableName"],
        "minimumSystemVersion": provenance["minimumSystemVersion"],
        "commit": provenance["commit"],
        "releaseChannel": "formal",
        "tag": provenance["tag"],
        "dirty": False,
        "teamIdentifier": provenance["teamIdentifier"],
        "hardenedRuntime": True,
        "appExecutableSha256": provenance["appExecutableSha256"],
        "infoPlistSha256": provenance["infoPlistSha256"],
    }
    for field, value in expected.items():
        if identity.get(field) != value:
            raise ReleaseError(f"application field {field} does not match provenance")
    run(["spctl", "-a", "-vvv", "-t", "exec", str(app)], combine=True)


def command_verify_provenance(args: argparse.Namespace) -> None:
    path = args.provenance.resolve()
    provenance, dmg = validate_provenance(path, require_remote=args.require_remote)
    verify_dmg(dmg)
    with mounted_app(dmg) as app:
        compare_app_to_provenance(app, provenance)
    print(
        f"release provenance valid: {provenance['version']} "
        f"build {provenance['buildNumber']} {dmg.name}"
    )


def command_verify_app(args: argparse.Namespace) -> None:
    provenance, _ = validate_provenance(
        args.provenance.resolve(), require_remote=args.require_remote
    )
    compare_app_to_provenance(args.app.resolve(), provenance)
    print(
        f"application identity valid: {args.app} "
        f"{provenance['version']} build {provenance['buildNumber']}"
    )


def extract_release_notes(path: Path, version: str) -> str:
    text = path.read_text(encoding="utf-8")
    start = re.search(
        rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}\n", text, re.M
    )
    if start is None:
        raise ReleaseError(f"{path.name} release heading is missing")
    remainder = text[start.end() :]
    end = re.search(r"^## \[", remainder, re.M)
    return (remainder[: end.start()] if end else remainder).strip() + "\n"


def command_release_notes(args: argparse.Namespace) -> None:
    source = CHANGELOG_ZH_CN if args.language == "zh-CN" else CHANGELOG
    notes = extract_release_notes(source, args.version)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(notes, encoding="utf-8")
    print(args.output)


def command_refresh_standards(_: argparse.Namespace) -> None:
    adoption = load_json(ADOPTION, "standards adoption")
    tracked = adoption.get("trackedFiles")
    if not isinstance(tracked, list):
        raise ReleaseError("trackedFiles is missing from standards adoption")
    for item in tracked:
        relative = item.get("path") if isinstance(item, dict) else None
        target = ROOT / str(relative)
        if not isinstance(relative, str) or not target.is_file():
            raise ReleaseError(f"tracked release file is missing: {relative}")
        item["sha256"] = sha256(target)
    atomic_write_json(ADOPTION, adoption)
    print(f"refreshed {len(tracked)} standards hashes")


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    version_check = subparsers.add_parser("version-check")
    version_check.add_argument("--release", action="store_true")
    version_check.set_defaults(func=command_version_check)

    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("--version", required=True)
    prepare.add_argument("--build", required=True, type=int)
    prepare.set_defaults(func=command_prepare)

    candidate = subparsers.add_parser("verify-candidate")
    candidate.add_argument("--app", required=True, type=Path)
    candidate.set_defaults(func=command_verify_candidate)

    write_provenance = subparsers.add_parser("write-provenance")
    write_provenance.add_argument("--source-root", required=True, type=Path)
    write_provenance.add_argument("--app", required=True, type=Path)
    write_provenance.add_argument("--dmg", required=True, type=Path)
    write_provenance.add_argument("--output", required=True, type=Path)
    write_provenance.add_argument("--tag", required=True)
    write_provenance.add_argument("--notary-result", required=True, type=Path)
    write_provenance.set_defaults(func=command_write_provenance)

    verify = subparsers.add_parser("verify-provenance")
    verify.add_argument("--provenance", required=True, type=Path)
    verify.add_argument("--require-remote", action="store_true")
    verify.set_defaults(func=command_verify_provenance)

    verify_app = subparsers.add_parser("verify-app")
    verify_app.add_argument("--provenance", required=True, type=Path)
    verify_app.add_argument("--app", required=True, type=Path)
    verify_app.add_argument("--require-remote", action="store_true")
    verify_app.set_defaults(func=command_verify_app)

    notes = subparsers.add_parser("release-notes")
    notes.add_argument("--version", required=True)
    notes.add_argument("--language", choices=("zh-CN", "en"), required=True)
    notes.add_argument("--output", required=True, type=Path)
    notes.set_defaults(func=command_release_notes)

    refresh = subparsers.add_parser("refresh-standards")
    refresh.set_defaults(func=command_refresh_standards)
    return parser


def main() -> int:
    args = make_parser().parse_args()
    try:
        args.func(args)
        return 0
    except (ReleaseError, OSError, ValueError) as exc:
        print(f"release error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
