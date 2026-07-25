# 家映

家映是一套面向家庭 NAS 的私有多媒体系统，由 Go 服务端和原生 Apple 客户端组成。它可以同时连接自建家庭媒体服务与 Jellyfin，在 iPhone、iPad 和 Apple TV 上浏览、查看照片并播放视频。

当前基线：`1.0.0-rc.2`。本阶段以稳定、可部署和可维护为主，不继续扩张功能范围。

> [!WARNING]
> 家庭媒体服务当前没有公网身份认证。它只能部署在可信家庭局域网或受控 VPN 内，不得直接映射到互联网。媒体原文件和管理接口会对能够访问服务端口的设备开放。

## 已支持能力

- 家庭媒体与 Jellyfin 双来源同时配置、互不影响。
- 家庭媒体目录浏览、分页、排序、年份/月度时间线与缩略图自愈。
- Jellyfin 登录、媒体库/文件夹浏览、Direct Play、HLS 转码和播放会上报。
- 照片查看、缩放、滑动切换、自动轮播暂停和媒体信息。
- 视频进度拖动、连续切集、iPhone/iPad 默认静音和 Apple TV 遥控器控制。
- iPhone、iPad 自适应布局与 tvOS 焦点界面。
- NAS Docker 首次部署、外置 Go 程序快速更新及生成数据安全清理。

## 仓库结构

- `family-media-server`：Go NAS 服务端、SQLite 索引、扫描和缩略图生成。
- `FamilyMediaClient`：共享 Core、iOS/iPadOS 与 tvOS 原生 SwiftUI 客户端。
- `docs`：统一发布流程和真机验收清单。
- `AGENTS.md`：后续开发和自动化代理必须遵守的工程约定。

## 快速验证

```bash
cd family-media-server
go test ./...
go vet ./...

cd ../FamilyMediaClient
swift test
python3 scripts/validate_release_configuration.py
```

完整 Xcode 构建、NAS 交付和实机验收见：

- [基线发布流程](docs/release_process.md)
- [真机验收清单](docs/manual_acceptance.md)
- [NAS 部署指南](family-media-server/docs/nas_deployment.md)
- [Apple 设备安装指南](FamilyMediaClient/docs/apple_installation.md)
- [客户端架构](FamilyMediaClient/docs/architecture.md)
- [服务端 API](family-media-server/docs/client_api.md)
- [安全策略](SECURITY.md)

## 版本边界

`1.0.0-rc.2` 不包含断点续播、Live Photo、搜索、收藏、人物识别和多用户权限。该候选版已完成 NAS、iPhone/iPad 和 Apple TV 基础验收；后续功能在此基线上继续迭代。

## 使用许可

当前公开版本保留全部权利，仅供源码审阅。未经许可不得复制、修改、分发或用于商业用途；详见 [LICENSE](LICENSE)。如果未来决定正式开源，再单独选择开放源代码许可证。
