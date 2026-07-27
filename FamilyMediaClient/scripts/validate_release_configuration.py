#!/usr/bin/env python3
"""Validate the stable identity and release metadata of both Apple targets."""

from pathlib import Path
import plistlib
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = ROOT.parent
PROJECT_YAML = ROOT / "project.yml"
SIGNING_CONFIG = ROOT / "Config/Signing.xcconfig"
LOCAL_SIGNING_CONFIG = ROOT / "LocalSigning.xcconfig"
LOCAL_SIGNING_EXAMPLE = ROOT / "LocalSigning.xcconfig.example"
TARGETS = {
    "FamilyMediaiOS": ROOT / "iOS/FamilyMediaiOS/Resources/Info.plist",
    "FamilyMediaTV": ROOT / "TV/FamilyMediaTV/Resources/Info.plist",
}
PRIVACY_MANIFEST = ROOT / "Shared/FamilyMediaAppleUI/PrivacyInfo.xcprivacy"


def fail(message: str) -> None:
    print(f"❌ {message}")
    raise SystemExit(1)


def target_block(project_text: str, target: str) -> str:
    match = re.search(
        rf"^  {re.escape(target)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9]+:|^schemes:)",
        project_text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not match:
        fail(f"project.yml 缺少 Target：{target}")
    return match.group("body")


def setting(block: str, key: str) -> str:
    match = re.search(rf"^        {re.escape(key)}:\s*(.+?)\s*$", block, re.MULTILINE)
    if not match:
        fail(f"缺少发布配置：{key}")
    return match.group(1).strip().strip('"')


def validate_plist(target: str, path: Path) -> None:
    if not path.is_file():
        fail(f"{target} 缺少 Info.plist：{path.relative_to(ROOT)}")
    with path.open("rb") as handle:
        info = plistlib.load(handle)

    expected = {
        "CFBundleDisplayName": "家映",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            fail(f"{target} {key} 应为 {value!r}")

    if not info.get("NSLocalNetworkUsageDescription"):
        fail(f"{target} 缺少本地网络用途说明")
    if info.get("NSAppTransportSecurity", {}).get("NSAllowsLocalNetworking") is not True:
        fail(f"{target} 未允许家庭局域网访问")

    if target == "FamilyMediaiOS":
        orientations = set(info.get("UISupportedInterfaceOrientations", []))
        required = {
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        }
        if not required.issubset(orientations):
            fail("iPhone 必须同时支持竖屏和两个横屏方向")


def validate_privacy_manifest() -> None:
    if not PRIVACY_MANIFEST.is_file():
        fail("两个 App Target 缺少共享 PrivacyInfo.xcprivacy")

    with PRIVACY_MANIFEST.open("rb") as handle:
        manifest = plistlib.load(handle)

    if manifest.get("NSPrivacyTracking") is not False:
        fail("隐私清单必须明确声明不进行跟踪")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        fail("家映不应声明跟踪域名")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        fail("当前版本不应声明向开发者收集数据")

    accessed_types = manifest.get("NSPrivacyAccessedAPITypes", [])
    user_defaults = next(
        (
            entry
            for entry in accessed_types
            if entry.get("NSPrivacyAccessedAPIType")
            == "NSPrivacyAccessedAPICategoryUserDefaults"
        ),
        None,
    )
    if user_defaults is None or "CA92.1" not in user_defaults.get(
        "NSPrivacyAccessedAPITypeReasons", []
    ):
        fail("UserDefaults 必须声明 CA92.1 自有 App 配置用途")


def validate_signing_configuration(project_text: str) -> None:
    if not SIGNING_CONFIG.is_file():
        fail("缺少通用签名配置：Config/Signing.xcconfig")
    signing_text = SIGNING_CONFIG.read_text(encoding="utf-8")
    if not re.search(r"^CODE_SIGN_STYLE\s*=\s*Automatic\s*$", signing_text, re.MULTILINE):
        fail("通用签名配置必须使用 Automatic 签名")
    if not re.search(
        r'^#include\?\s+"\.\./LocalSigning\.xcconfig"\s*$',
        signing_text,
        re.MULTILINE,
    ):
        fail("通用签名配置必须可选加载 LocalSigning.xcconfig")

    expected_config_files = re.search(
        r"^configFiles:\n"
        r"  Debug:\s*Config/Signing\.xcconfig\s*\n"
        r"  Release:\s*Config/Signing\.xcconfig\s*$",
        project_text,
        re.MULTILINE,
    )
    if expected_config_files is None:
        fail("project.yml 的 Debug 与 Release 必须共用 Config/Signing.xcconfig")
    if "DEVELOPMENT_TEAM" in project_text:
        fail("project.yml 不得保存个人 Apple Developer Team ID")
    if "CODE_SIGN_STYLE" in project_text:
        fail("CODE_SIGN_STYLE 应只由通用 Signing.xcconfig 管理")

    if not LOCAL_SIGNING_EXAMPLE.is_file():
        fail("缺少 LocalSigning.xcconfig.example")
    example_text = LOCAL_SIGNING_EXAMPLE.read_text(encoding="utf-8")
    if not re.search(
        r"^DEVELOPMENT_TEAM\s*=\s*YOUR_TEAM_ID\s*$",
        example_text,
        re.MULTILINE,
    ):
        fail("本机签名示例必须使用 YOUR_TEAM_ID 占位符")

    tracked_local_config = subprocess.run(
        [
            "git",
            "ls-files",
            "--error-unmatch",
            "FamilyMediaClient/LocalSigning.xcconfig",
        ],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        check=False,
    )
    if tracked_local_config.returncode == 0:
        fail("LocalSigning.xcconfig 不得被 Git 跟踪")

    public_files = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        check=True,
    ).stdout.decode("utf-8").split("\0")
    team_pattern = re.compile(
        r"DEVELOPMENT_TEAM\s*[:=]\s*[\"']?[A-Z0-9]{10}[\"']?"
    )
    for relative_path in filter(None, public_files):
        path = REPOSITORY_ROOT / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if team_pattern.search(text):
            fail(f"跟踪文件包含个人 Apple Developer Team ID：{relative_path}")

    if LOCAL_SIGNING_CONFIG.exists():
        local_lines = [
            line.strip()
            for line in LOCAL_SIGNING_CONFIG.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("//")
        ]
        if len(local_lines) != 1 or not re.fullmatch(
            r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}",
            local_lines[0],
        ):
            fail("LocalSigning.xcconfig 只能包含一个有效的 DEVELOPMENT_TEAM")
        print("✅ 已检测到被 Git 忽略的本机 Apple Developer Team 配置")
    else:
        print("ℹ️ 未配置本机 Team；CI 无签名构建不受影响")


def main() -> None:
    project_text = PROJECT_YAML.read_text(encoding="utf-8")
    validate_signing_configuration(project_text)
    validate_privacy_manifest()
    values: dict[str, dict[str, str]] = {}
    for target, plist_path in TARGETS.items():
        block = target_block(project_text, target)
        values[target] = {
            key: setting(block, key)
            for key in (
                "PRODUCT_BUNDLE_IDENTIFIER",
                "MARKETING_VERSION",
                "CURRENT_PROJECT_VERSION",
                "INFOPLIST_FILE",
            )
        }
        if "- path: Shared/FamilyMediaAppleUI" not in block:
            fail(f"{target} 未包含共享 Apple UI 资源，隐私清单不会打包")
        validate_plist(target, plist_path)

    ios = values["FamilyMediaiOS"]
    tv = values["FamilyMediaTV"]
    if ios["PRODUCT_BUNDLE_IDENTIFIER"] == tv["PRODUCT_BUNDLE_IDENTIFIER"]:
        fail("iOS 与 tvOS 必须使用不同 Bundle ID")
    if ios["MARKETING_VERSION"] != tv["MARKETING_VERSION"]:
        fail("iOS 与 tvOS MARKETING_VERSION 不一致")
    if ios["CURRENT_PROJECT_VERSION"] != tv["CURRENT_PROJECT_VERSION"]:
        fail("iOS 与 tvOS CURRENT_PROJECT_VERSION 不一致")
    if not re.fullmatch(r"\d+\.\d+\.\d+", ios["MARKETING_VERSION"]):
        fail("MARKETING_VERSION 应使用 x.y.z 格式")
    if not ios["CURRENT_PROJECT_VERSION"].isdigit() or int(ios["CURRENT_PROJECT_VERSION"]) < 1:
        fail("CURRENT_PROJECT_VERSION 必须是正整数")

    expected_plists = {
        "FamilyMediaiOS": "iOS/FamilyMediaiOS/Resources/Info.plist",
        "FamilyMediaTV": "TV/FamilyMediaTV/Resources/Info.plist",
    }
    for target, expected_path in expected_plists.items():
        if values[target]["INFOPLIST_FILE"] != expected_path:
            fail(f"{target} INFOPLIST_FILE 意外变更")

    print(
        "✅ 发布配置正常："
        f"家映 {ios['MARKETING_VERSION']} ({ios['CURRENT_PROJECT_VERSION']})"
    )
    print("✅ Apple Developer Team 通过被忽略的 LocalSigning.xcconfig 隔离")
    print(f"✅ iOS Bundle ID：{ios['PRODUCT_BUNDLE_IDENTIFIER']}")
    print(f"✅ tvOS Bundle ID：{tv['PRODUCT_BUNDLE_IDENTIFIER']}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        fail(f"无法读取发布配置：{error}")
