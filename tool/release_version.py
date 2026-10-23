#!/usr/bin/env python3
"""Release version helpers for the automatic release workflow.

bump:   raise the patch and build number in pubspec.yaml, print the new version.
publish: point assets/version.json at a published release so installed apps
         offer the update. Run only after the GitHub Release exists.
"""
import argparse
import json
import re
from pathlib import Path

PUBSPEC = Path("pubspec.yaml")
VERSION_JSON = Path("assets/version.json")
_VERSION_RE = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.M)


def read_version():
    match = _VERSION_RE.search(PUBSPEC.read_text(encoding="utf-8"))
    if not match:
        raise SystemExit("pubspec.yaml has no major.minor.patch+build version")
    return tuple(int(part) for part in match.groups())


def bump():
    major, minor, patch, build = read_version()
    patch += 1
    build += 1
    text = PUBSPEC.read_text(encoding="utf-8")
    PUBSPEC.write_text(_VERSION_RE.sub(f"version: {major}.{minor}.{patch}+{build}", text, count=1), encoding="utf-8")
    print(f"{major}.{minor}.{patch}")


def publish(repository, tag, notes):
    major, minor, patch, build = read_version()
    version = f"{major}.{minor}.{patch}"
    fields = {
        "version": version,
        "build_number": build,
        "version_num": major * 100_000_000 + minor * 1_000_000 + patch * 10_000 + build,
        "version_desc": f"version: {version}\n版本更新：\n{notes.strip() or '- 修复部分bug'}",
        "prerelease": False,
        "download_url": f"https://github.com/{repository}/releases/tag/{tag}",
    }
    data = json.loads(VERSION_JSON.read_text(encoding="utf-8"))
    data.update(fields)
    for platform in (data.get("platforms") or {}).values():
        if isinstance(platform, dict):
            platform.update(fields)
    VERSION_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(version)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("bump")
    pub = sub.add_parser("publish")
    pub.add_argument("--repository", required=True)
    pub.add_argument("--tag", required=True)
    pub.add_argument("--notes", default="")
    args = parser.parse_args()
    if args.command == "bump":
        bump()
    else:
        publish(args.repository, args.tag, args.notes)


if __name__ == "__main__":
    main()
