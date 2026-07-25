#!/usr/bin/env python3
"""Validate the stable identity and release metadata of both Apple targets."""

from pathlib import Path
import plistlib
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
PROJECT_YAML = ROOT / "project.yml"
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


def main() -> None:
    project_text = PROJECT_YAML.read_text(encoding="utf-8")
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
    print("✅ Apple Developer Team 由本机 Xcode 选择，仓库不保存个人 Team ID")
    print(f"✅ iOS Bundle ID：{ios['PRODUCT_BUNDLE_IDENTIFIER']}")
    print(f"✅ tvOS Bundle ID：{tv['PRODUCT_BUNDLE_IDENTIFIER']}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"无法读取发布配置：{error}")
