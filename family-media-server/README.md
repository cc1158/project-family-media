# family-media-server

家庭局域网媒体服务端，用于给 Apple TV 客户端提供 NAS 视频和照片列表，以及 HTTP 静态文件访问。

## 当前能力

- 健康检查与客户端兼容性声明：`GET /healthz`
- 混合媒体列表：`GET /api/v1/media`
- 视频列表：`GET /api/v1/videos`
- 照片列表：`GET /api/v1/photos`
- 按 NAS 目录递归浏览：`GET /api/v1/browse`
- 年份/月度时间线索引：`GET /api/v1/timeline/index`
- 手动扫描、扫描状态和单项缩略图重建
- 原媒体访问：`GET /media/original/{path}`
- 缩略图访问：`GET /media/thumbnails/{path}`
- 支持 HEIC/HEIF/WebP 照片和 MOV 视频的缩略图生成
- 缩略图缓存丢失后可在下次扫描时自动修复
- 安全清理服务生成的索引、缩略图和转码临时文件：`POST /api/v1/admin/data/clear`
- 配置文件驱动媒体目录、端口和公开访问地址
- 支持 Docker 构建和部署
- 后台扫描随服务生命周期安全取消和等待，日志使用不包含家庭隐私的稳定事件码

## 本地运行

先安装 Go 1.22 或更新版本。

```bash
make run
```

默认配置使用仓库内的样例目录：

- `sample-media/library`

把测试视频或照片放进去后访问：

```bash
curl http://localhost:8080/healthz
curl http://localhost:8080/api/v1/media
curl http://localhost:8080/api/v1/browse
curl http://localhost:8080/api/v1/videos
curl http://localhost:8080/api/v1/photos
```

## NAS 配置

复制示例配置并按真实路径修改：

```bash
cp configs/config.example.yaml configs/config.yaml
```

关键字段：

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  publicBaseURL: "http://nas-ip:8080"

media:
  rootDir: "/media/library"

index:
  enabled: true
  dbPath: "/data/media-index.db"

scan:
  intervalSeconds: 600

thumbnail:
  enabled: true
  cacheDir: "/data/thumbnails"
  maxSide: 480
  batchSize: 100

transcode:
  enabled: false
  workDir: "/data/transcode"
```

`publicBaseURL` 应该填写 Apple TV 能访问到的服务地址。

## Docker

完整 NAS Docker 部署步骤见 [nas_deployment.md](docs/nas_deployment.md)。

常规构建会在 Docker builder 阶段自动编译 Go 服务端，并在运行镜像中安装 FFmpeg、IANA 时区数据和 HEIC/HEIF 转换工具：

```bash
make docker-build
docker run --rm -p 8080:8080 \
  -v /volume1/family-media:/media/library:ro \
  -v family-media-data:/data \
  -v ./configs/config.nas.example.yaml:/app/config.yaml:ro \
  family-media-server:local
```

如果 Mac 和 NAS CPU 架构不同，请在构建时使用 `docker buildx build --platform linux/amd64` 或 `linux/arm64`。

## 测试

```bash
make test
```

为 x86_64 NAS 生成可独立替换的服务端程序和 SHA-256：

```bash
make nas-binary
```

首次部署或运行环境升级仍使用完整 Docker 镜像；配置好 `/opt/family-media/bin` 映射后，后续服务端迭代只需替换 NAS 上的独立程序并重启原容器。完整步骤见 `docs/nas_deployment.md`。

当前仓库已包含配置加载、目录扫描、URL 生成的基础测试。

## 架构

项目按正式服务分层组织：

- `internal/domain`: 领域模型和接口
- `internal/application`: 应用用例
- `internal/infrastructure`: 文件系统、数据库、外部命令等基础设施实现
- `internal/interfaces`: HTTP 等对外入口
- `internal/platform`: 配置、日志等平台能力
- `internal/bootstrap`: 依赖组装

SQLite 作为嵌入式索引数据库使用，不需要单独部署数据库服务。
媒体索引属于可重新生成的数据。服务启动时如果发现 SQLite 表结构与当前代码不一致，会直接重建媒体索引表；原始媒体和缩略图文件不受影响。升级后执行一次“扫描媒体”即可重新建立索引，也可以使用现有清理接口进行完整重建。

更多工程约定见 [development.md](docs/development.md)，迭代路线见 [roadmap.md](docs/roadmap.md)。

iOS / tvOS 客户端对接见 [client_api.md](docs/client_api.md)。
