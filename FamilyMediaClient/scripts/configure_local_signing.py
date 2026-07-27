#!/usr/bin/env python3
"""Create the ignored local Apple Developer Team configuration."""

from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "LocalSigning.xcconfig"
TEAM_ID_PATTERN = re.compile(r"^[A-Z0-9]{10}$")


def fail(message: str) -> None:
    print(f"❌ {message}")
    raise SystemExit(1)


def ensure_output_is_ignored() -> None:
    result = subprocess.run(
        ["git", "check-ignore", "--no-index", "--quiet", OUTPUT.name],
        cwd=ROOT,
        check=False,
    )
    if result.returncode != 0:
        fail("LocalSigning.xcconfig 未被 Git 忽略，已停止写入")


def main() -> None:
    if len(sys.argv) != 2:
        fail("用法：python3 scripts/configure_local_signing.py YOUR_TEAM_ID")

    team_id = sys.argv[1].strip().upper()
    if not TEAM_ID_PATTERN.fullmatch(team_id):
        fail("Apple Developer Team ID 应为 10 位大写字母或数字")

    ensure_output_is_ignored()
    OUTPUT.write_text(
        "// Local-only Apple signing identity. This file is ignored by Git.\n"
        f"DEVELOPMENT_TEAM = {team_id}\n",
        encoding="utf-8",
    )
    OUTPUT.chmod(0o600)
    print("✅ 已生成 LocalSigning.xcconfig")
    print("✅ iOS、iPadOS、tvOS 和测试 Target 将共用该 Team")


if __name__ == "__main__":
    main()
