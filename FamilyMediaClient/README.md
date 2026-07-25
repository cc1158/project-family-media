# FamilyMediaClient

家映 Apple 客户端工程，可同时连接 `family-media-server` 与 Jellyfin。当前包含通用 iPhone/iPadOS Target 和 tvOS Target，共享媒体来源、分页/时间线、播放解析、会上报及配置安全逻辑。

当前候选版为 `1.0.0-rc.2`，Apple 版本为 `1.0.0 (4)`。

## 当前结构

- `Shared/FamilyMediaCore`: 共享模型、网络客户端、媒体服务和可测试业务基础设施。
- `Shared/FamilyMediaAppleUI`: 两端共用的图片管线、主题和少量展示策略。
- `TV/FamilyMediaTV`: tvOS SwiftUI App 源码。
- `iOS/FamilyMediaiOS`: iOS SwiftUI App 源码。
- `docs/client_requirements.md`: 原始需求文档。
- `docs/architecture.md`: 当前工程架构说明。
- `docs/apple_installation.md`: iPhone 与 Apple TV 长期安装、签名和覆盖升级流程。
- `docs/release_checklist.md`: 长期安装版发布前验收清单。
- `project.yml`: XcodeGen 工程描述。

## 验证共享层

```bash
swift test
```

## 生成 Xcode 工程

当前仓库使用 XcodeGen 描述 Xcode 工程。安装完整 Xcode 和 XcodeGen 后运行：

```bash
xcodegen generate
open FamilyMediaClient.xcodeproj
```

准备真机安装前，先检查 iOS/tvOS 版本、Bundle ID、签名团队和 Info.plist 稳定性：

```bash
python3 scripts/validate_release_configuration.py
```

首次运行时可以在 App 的设置页修改服务端地址。默认地址来自对应 Target 的 `Info.plist`：

- `TV/FamilyMediaTV/Resources/Info.plist`
- `iOS/FamilyMediaiOS/Resources/Info.plist`

完整架构见 [architecture.md](docs/architecture.md)，统一发布流程见 [仓库发布文档](../docs/release_process.md)。
