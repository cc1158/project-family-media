# 家映 1.0 RC 发布流程

本文是服务端和 Apple 客户端的统一发布入口。当前候选版为 `1.0.0-rc.2`，目标 NAS 平台为 `linux/amd64`。

## 1. 发布前检查

1. 工作区必须只包含本次基线修改，不得包含真实 NAS 配置、媒体文件或凭据。
2. Apple 客户端版本应为 `1.0.0 (4)`。
3. 运行自动验证：

```bash
cd family-media-server
go test ./...
go vet ./...

cd ../FamilyMediaClient
swift test
python3 scripts/validate_release_configuration.py
xcodegen generate
xcodebuild -project FamilyMediaClient.xcodeproj -scheme FamilyMediaiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FamilyMediaClient.xcodeproj -scheme FamilyMediaTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build

cd ..
git diff --check
```

## 2. 构建服务端交付物

从干净的基线提交构建，确保 `/healthz` 中的提交号不带 `-dirty`：

```bash
cd family-media-server
make release VERSION=1.0.0-rc.2
```

输出目录：

```text
dist/releases/1.0.0-rc.2/
  family-media-server-linux-amd64
  family-media-server-linux-amd64.sha256
  family-media-server-1.0.0-rc.2-linux-amd64.tar
  family-media-server-1.0.0-rc.2-linux-amd64.tar.sha256
  config.nas.example.yaml
```

构建同时保留 `family-media-server:local`，并创建可追溯镜像标签 `family-media-server:1.0.0-rc.2`。产物位于 Git 忽略目录，不提交仓库。

## 3. 校验交付物

```bash
cd family-media-server/dist/releases/1.0.0-rc.2
shasum -a 256 -c family-media-server-linux-amd64.sha256
shasum -a 256 -c family-media-server-1.0.0-rc.2-linux-amd64.tar.sha256
file family-media-server-linux-amd64
docker image inspect family-media-server:1.0.0-rc.2 \
  --format '{{.Os}}/{{.Architecture}}'
```

二进制必须是 Linux x86-64 ELF，镜像必须是 `linux/amd64`。

## 4. 部署方式

- 首次部署或 FFmpeg、HEIC、时区工具等运行环境升级：导入 Docker tar，按 NAS 部署文档重建容器，保留 `/data`。
- 普通 Go 业务更新：停止原容器，校验并替换外置程序，再启动同一容器。
- 四个固定映射为媒体目录、`/data`、配置文件和 `/opt/family-media/bin`。详细步骤见服务端 NAS 部署文档。
- 任何更新都不得删除原始媒体。索引不兼容时使用管理清理操作重建生成数据。

## 5. 候选版确认

部署后检查 `/healthz`：

- `build.version` 为 `1.0.0-rc.2`。
- `build.commit` 与基线提交一致且不含 `-dirty`。
- 外置程序模式下 `build.source` 为 `external`。
- `ffmpeg`、`heif`、媒体目录、索引和缩略图检查均正常。

完成[真机验收清单](manual_acceptance.md)后，才创建标签：

```bash
git tag -a v1.0.0-rc.2 -m "家映 1.0.0-rc.2"
```

存在崩溃、配置丢失、Token 泄漏、无提示黑屏、遗留转码任务或原始媒体受影响时不得打标签。
