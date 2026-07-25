# NAS Docker 部署指南

本文档说明如何把 `family-media-server` 部署到 NAS 的 Docker / Container Manager 中。

## 关键结论

你上次实际使用的是“Dockerfile 构建镜像，再导出 tar 给 NAS 导入”的方式。项目里已经有 Makefile 封装：

```bash
make docker-build
```

它会执行等价于下面的构建（并自动注入版本、提交号和构建时间）：

```bash
docker buildx build \
  --platform linux/amd64 \
  -f deployments/docker/Dockerfile \
  -t family-media-server:local \
  --load \
  .
```

这一步已经包含 Go 编译。Dockerfile 使用两阶段构建：

1. `golang:1.22-alpine` 阶段把源码复制到 `/src`，执行 `go build`。
2. `alpine:3.20` 阶段只复制编译后的二进制文件，并安装 `ffmpeg`、`tzdata` 和 `libheif-tools`。

所以部署到 NAS 的主流程里，不需要先在 Mac 上手动执行 `go build`。仓库里的 `bin/family-media-server` 只是本地手动编译产物，不是上次导入 NAS 的镜像来源。

如果只是想在 Mac 本地编译一个服务端二进制，用这个命令：

```bash
go build -o ./bin/family-media-server ./cmd/family-media-server
```

如果想在 Mac 上生成给 Linux x86_64 NAS 用、带版本信息和校验文件的独立程序，使用：

```bash
make nas-binary VERSION=1.0.0-rc.2
```

但正常部署仍推荐 Dockerfile 构建，因为镜像里还需要准备 Alpine Linux、`ffmpeg`、配置文件位置和启动命令。

## 1. 进入服务端目录

从仓库根目录进入服务端：

```bash
cd family-media-server
ls
```

后续命令都在 `family-media-server` 目录下执行。

## 2. 构建 Docker 镜像

准备 `1.0.0-rc.2` 基线交付时，优先使用统一命令：

```bash
make release VERSION=1.0.0-rc.2
```

它会生成版本化的 amd64 程序、Docker tar、配置模板和 SHA-256，并同时保留 `family-media-server:local` 与 `family-media-server:1.0.0-rc.2` 两个镜像标签。普通本地构建仍可使用下面的方式 A/B。

### 方式 A：复现你上次的构建方式，推荐

这一步会在 Docker builder 阶段自动执行类似下面的 Go 编译：

```bash
CGO_ENABLED=0 go build -o /out/family-media-server ./cmd/family-media-server
```

完整 Docker 镜像构建命令：

```bash
docker buildx build \
  --platform linux/amd64 \
  -f deployments/docker/Dockerfile \
  -t family-media-server:local \
  --load \
  .
```

这条命令的含义是：

- 在 Mac 上用 Dockerfile 构建镜像。
- `--platform linux/amd64` 指定产物给 x86_64 NAS 使用。
- Dockerfile 的 builder 阶段会在 Linux 环境里自动编译 Go 服务端。
- `--load` 会把构建好的镜像加载到 Mac 本机 Docker 里。
- 镜像标签是 `family-media-server:local`。

构建完成后查看镜像：

```bash
docker images
```

你应该能看到类似：

```text
family-media-server   local   ...
```

然后导出镜像：

```bash
docker save family-media-server:local -o family-media-server.tar
```

导出后建议记录文件大小和 SHA-256，上传到 NAS 后可再次计算校验值，确认大文件传输完整：

```bash
ls -lh family-media-server.tar
shasum -a 256 family-media-server.tar
```

tar 会生成在当前的 `family-media-server` 目录中。它是 Docker 映像包，不能直接解压后运行，应当从 NAS 的“映像 / Image”页面导入。

如果构建时从 `proxy.golang.org` 下载 Go 依赖持续出现 `EOF`，可以只为本次构建指定备用代理：

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f deployments/docker/Dockerfile \
  -t family-media-server:local \
  --load \
  .
```

最后把 `family-media-server.tar` 上传到 NAS，在 NAS 的 Docker / Container Manager 里导入镜像。

### 方式 B：Makefile 简化命令

Makefile 默认同样构建 `linux/amd64` 镜像，因此 Apple Silicon Mac 也可以使用：

```bash
make docker-export
docker images
```

该命令会同时生成 `family-media-server.tar` 和 `family-media-server.tar.sha256`。

当前基线只交付 x86_64 NAS 的 `linux/amd64` 产物。未来需要支持 ARM64 时，可使用：

```bash
docker buildx build \
  --platform linux/arm64 \
  -f deployments/docker/Dockerfile \
  -t family-media-server:local \
  --load \
  .
```

判断 NAS 架构的方法是在 NAS 上执行：

```bash
uname -m
```

常见对应关系：

- `x86_64` -> `linux/amd64`
- `aarch64` / `arm64` -> `linux/arm64`

## 3. 上传镜像包到 NAS

把新生成的 `family-media-server.tar` 上传到 NAS。后续如果只是改 NAS 上映射出来的 `config.yaml`，不需要重新构建镜像；只有服务端代码或 Dockerfile 改了，才需要重新执行构建和导出。

### 从旧版服务端升级到当前版本

当前 Apple 客户端的家庭媒体目录浏览依赖 `/api/v1/browse`，因此旧版服务端需要和客户端一起升级。新版镜像支持把 Go 服务端程序放在 NAS 持久化目录中；以后只需替换这个小程序并重启原容器，不必重复上传完整 Docker tar。

如果容器日志出现 `Option autorotate ... cannot be applied`，说明正在运行方向修复过程中的有缺陷过渡版本。该版本生成的独立程序、校验文件和 Docker tar 都不能继续使用，必须换成重新验证后的同一批产物，不能混用新旧程序与校验文件。

推荐按以下顺序操作：

1. 在 NAS 的容器详情中记录现有端口、目录映射、环境变量和重启策略。
2. 停止并删除旧的 `family-media-server` 容器。删除容器不会删除 NAS 上映射的媒体目录、`/data` 或 `config.yaml`。
3. 在“映像 / Image”中删除旧的 `family-media-server:local` 映像，避免 NAS 继续使用没有版本标签的旧映像层。
4. 上传并导入新生成的 `family-media-server.tar`，确认映像名称和标签为 `family-media-server:local`。
5. 在 NAS 创建 `/volume1/docker/family-media/bin`，把独立程序上传为 `/volume1/docker/family-media/bin/family-media-server`。
6. 使用原来的端口和目录映射重新创建容器，特别要保持 `/data` 映射不变，并新增程序目录映射。
7. 启动容器，先检查 `/healthz` 中的 `build.source` 是否为 `external`，再从客户端执行一次“扫描媒体”。
8. 等待扫描完成后，检查目录层级、缩略图、照片显示和视频播放。

如果希望完全重新建立索引和封面，可以在客户端设置中选择“清理媒体数据”→“清理并重新扫描”。该操作只清理服务生成的索引、封面缓存和转码临时文件，不会删除 NAS 中的原始照片和视频。

## 4. 准备 NAS 配置文件

在 NAS 上准备一个持久化配置文件，例如：

```text
/volume1/docker/family-media/config.yaml
```

内容从 `configs/config.nas.example.yaml` 复制后修改：

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  publicBaseURL: "http://你的NAS局域网IP:8080"

media:
  rootDir: "/media/library"

index:
  enabled: true
  dbPath: "/data/media-index.db"

thumbnail:
  enabled: true
  cacheDir: "/data/thumbnails"
  maxSide: 480
  batchSize: 100

scan:
  intervalSeconds: 600

transcode:
  enabled: false
  workDir: "/data/transcode"
```

说明：

- `publicBaseURL` 必须是 Apple TV 能访问到的 NAS 地址，不要写 `localhost`。
- 客户端的“清理媒体数据”只会清空 SQLite 中的媒体索引、`thumbnail.cacheDir` 和 `transcode.workDir` 内容。为防止误删，这两个目录不能与 `media.rootDir` 重叠，也不能包含 `index.dbPath`。
- `media.rootDir` 是容器内路径，保持 `/media/library`。
- `/media/library` 后面映射到 NAS 的真实媒体目录。
- `/data` 用来保存 SQLite 索引、缩略图缓存、转码临时文件。

配置项影响：

| 配置 | NAS 基线值 | 修改后的操作 |
|---|---|---|
| `server.host` | `0.0.0.0` | 重启容器；通常不修改。 |
| `server.port` | `8080` | 同步修改容器端口映射并重启。 |
| `server.publicBaseURL` | `http://NAS_LAN_IP:8080` | NAS IP/端口变化后修改并重启；已有索引无需重建。 |
| `media.rootDir` | `/media/library` | 保持容器路径不变，改 NAS 映射；随后重新扫描。 |
| `index.dbPath` | `/data/media-index.db` | 修改后重启并重新扫描。 |
| `scan.intervalSeconds` | `600` | 修改后重启；不影响已有索引。 |
| `thumbnail.cacheDir` | `/data/thumbnails` | 修改后重启并扫描以重建缺失缩略图。 |
| `thumbnail.maxSide` | `480` | 修改后重启；要应用到历史文件需清理缩略图并重新扫描。 |
| `thumbnail.batchSize` | `100` | 修改后重启；不影响已生成缩略图。 |
| `transcode.workDir` | `/data/transcode` | 修改后重启；不得与媒体、索引或缩略图目录重叠。 |

## 5. 在 NAS 导入镜像

如果使用 NAS 图形界面：

1. 打开 Docker / Container Manager。
2. 进入“映像 / Image”。
3. 选择“导入 / Import”。
4. 选择 `family-media-server.tar`。
5. 导入后确认镜像名是 `family-media-server:local`。

注意：这里要在“映像 / Image”里导入镜像包，不是导入容器配置。

## 6. 创建容器

端口映射：

```text
NAS 8080 -> 容器 8080
```

目录映射示例：

```text
/volume1/family-media                  -> /media/library    只读
/volume1/docker/family-media/data      -> /data             可读写
/volume1/docker/family-media/config.yaml -> /app/config.yaml 只读
/volume1/docker/family-media/bin       -> /opt/family-media/bin 只读
```

`/data` 同时保存 SQLite 索引和缩略图缓存，必须映射到持久化目录。更换媒体目录映射不会要求移动缩略图；如果 `/data/thumbnails` 被删除或更换，服务端会在下次媒体扫描中发现缺失文件并重新生成。

客户端的目录结构来自 `/media/library` 下的相对路径，会保留多级目录。直接放在媒体根目录的文件会显示在虚拟的“未分类”目录中，服务端不会移动或重命名 NAS 上的原文件。

容器启动命令使用镜像默认值即可。镜像启动脚本会优先读取 `/opt/family-media/bin/family-media-server`；文件存在时复制到容器临时目录并执行，不要求 NAS 上的源文件预先带有执行权限。外部文件缺失时才会运行镜像内置版本。

如果外部文件存在但已损坏、上传不完整或 CPU 架构错误，容器会明确启动失败，不会静默运行旧版本。此时应检查文件 SHA-256 和 NAS 架构。

镜像传入服务端的参数仍然是：

```bash
-config /app/config.yaml
```

启动脚本会把它交给 `/tmp/family-media-server`（外置模式）或 `/app/family-media-server`（内置回退模式）。

重启策略建议：

```text
unless-stopped
```

## 7. 命令行创建容器示例

如果你在 NAS 上用命令行：

```bash
docker run -d \
  --name family-media-server \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /volume1/family-media:/media/library:ro \
  -v /volume1/docker/family-media/data:/data \
  -v /volume1/docker/family-media/config.yaml:/app/config.yaml:ro \
  -v /volume1/docker/family-media/bin:/opt/family-media/bin:ro \
  family-media-server:local
```

## 8. 后续只更新服务端程序

在 Mac 的 `family-media-server` 目录执行：

```bash
make nas-binary VERSION=1.0.0-rc.2
```

会生成：

```text
dist/family-media-server
dist/family-media-server.sha256
```

更新 NAS 时：

1. 停止现有容器，不删除容器。
2. 把新程序先上传为 `/volume1/docker/family-media/bin/family-media-server.new`。
3. 同时上传 `.sha256` 文件，并在程序目录检查上传完整性：

   ```bash
   cd /volume1/docker/family-media/bin
   sha256sum -c family-media-server.sha256
   ```

   校验文件中的目标名是 `family-media-server`。如果此时仍保留 `.new` 后缀，可先用 `sha256sum family-media-server.new` 与校验文件中的哈希值人工比对。
4. 将 `.new` 重命名为 `family-media-server`。
5. 启动原容器。
6. 查看 `/healthz`，确认 `build.commit` 已变化且 `build.source` 为 `external`。

不要直接覆盖仍在运行的程序文件，也不要把程序目录映射为可写。外部程序只负责方便更新；FFmpeg 和内置回退程序仍由基础镜像提供。

如果本次更新同时修复镜像内置回退程序，应在独立程序验证通过后再导入新的 Docker tar，并用相同四个目录映射重建一次容器。这样临时移走外置程序时，`source: bundled` 对应的也会是已修复版本；完成这次运行环境更新后，普通业务迭代才只需要替换独立程序。

时间线时区数据已经编入独立程序，只替换程序即可修复 `invalid_time_zone`。HEIC/HEIF 缩略图依赖基础镜像中的 `heif-convert`，首次加入该能力时仍需重新导入 Docker tar 并重建容器；之后普通 Go 业务更新继续只替换外置程序。

目录与年月分页性能优化只涉及 Go 程序和 SQLite 索引结构，不依赖新的镜像软件包。媒体索引是可重新生成的数据：替换外置程序并重启后，如果服务发现旧表结构与当前代码不一致，会直接重建媒体索引表，不执行版本迁移或历史字段回填。原始媒体和已生成的缩略图文件不会被删除，但需要执行一次“扫描媒体”重新建立索引。也可以使用现有“清理媒体数据”或“清理并重新扫描”操作手动完整重建。

## 9. 验证服务

健康检查：

```bash
curl http://你的NAS局域网IP:8080/healthz
```

最新服务端的响应应包含 `"apiVersion":2`，以及 `folder_browse`、`generated_data_clear`、`browse_sort`、`timeline_index` 和 `timeline_browse` 能力。如果只有 `{"status":"ok"}`，说明 NAS 上仍是旧镜像。

响应中的 `build` 用来确认真正运行的程序，例如：

```json
{
  "build": {
    "version": "1.0.0-rc.2",
    "commit": "提交号",
    "builtAt": "2026-07-19T06:30:00Z",
    "source": "external"
  }
}
```

- `external`：正在运行 NAS 映射目录中的独立程序。
- `bundled`：外部程序不存在，正在运行镜像内置回退版本。
- `development`：通过 `go run` 或本地方式运行。

`checks.ffmpeg` 和 `checks.heif` 都应为 `ok`。`heif` 为 `warning` 时，目录和播放仍可用，但 HEIC/HEIF 缩略图无法生成，需要导入包含 `libheif-tools` 的最新基础镜像。

容器日志现在使用稳定事件字段，例如 `event`、`module`、`result`、`errorCode` 和 `operationID`。日志不会输出家庭媒体文件名、路径、NAS 地址或请求参数；排障时应优先记录事件码、错误码、数量和 `/healthz` 构建信息。

也可以直接检查目录浏览接口：

```bash
curl 'http://你的NAS局域网IP:8080/api/v1/browse?limit=20'
```

正常情况下会返回 `items`、`nextCursor` 和 `hasMore`。媒体根目录中的文件会归入虚拟“未分类”目录，NAS 上原有的多级文件夹会按层级展示。

媒体列表：

```bash
curl http://你的NAS局域网IP:8080/api/v1/media
```

触发扫描：

```bash
curl -X POST http://你的NAS局域网IP:8080/api/v1/admin/scan
```

查看扫描状态：

```bash
curl http://你的NAS局域网IP:8080/api/v1/admin/scan/status
```

## 10. Apple TV 客户端配置

客户端服务端地址填写：

```text
http://你的NAS局域网IP:8080
```

进入设置页后：

1. 检查连接。
2. 触发扫描。
3. 等扫描完成。
4. 回媒体列表查看视频和照片。

## 11. 手动编译 Go 的备选方式

如果你不想让 Dockerfile 编译，也可以手动交叉编译 Linux 二进制：

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o dist/family-media-server ./cmd/family-media-server
```

ARM64 NAS 使用：

```bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o dist/family-media-server ./cmd/family-media-server
```

但当前项目推荐 Dockerfile 自动编译，因为它会一起准备 Linux 运行环境和 `ffmpeg`。如果走手动编译，就还要另外维护一个 Dockerfile 或运行环境，反而更容易出错。

## 12. 常见问题

缩略图状态中的常见安全错误码：

- `ffmpeg_thumbnail_failed`：视频帧或图片最终 FFmpeg 回退失败。先确认 `checks.ffmpeg`，修复环境或文件后执行普通扫描重试。
- `heif_conversion_failed`：HEIC/HEIF 专用转换和最终回退均失败。先确认 `checks.heif`，必要时升级基础镜像，再执行普通扫描。
- `thumbnail_generation_failed`：生成器返回了未分类失败。检查 `/data` 写权限和健康检查后重试扫描。
- `thumbnail_batch_failed`：读取或更新缩略图队列失败，属于系统级失败；修复存储或 SQLite 状态后重新扫描。

普通失败重试不需要清理 `/data`。只有已经生成但方向、尺寸或内容错误的历史缩略图需要单项“重新生成封面”，或执行“清理媒体数据”→“清理并重新扫描”。服务端更新本身不会删除原始媒体。

- Apple TV 连不上：检查客户端地址、NAS IP、端口映射、防火墙。
- 媒体列表为空：检查 `/media/library` 是否映射到正确的 NAS 媒体目录。
- 缩略图失败：检查 `/data` 是否可写，`/healthz` 中 `ffmpeg` 和 `heif` 是否正常。HEIC 历史失败在部署新镜像并重启后执行一次普通扫描即可重试，无需清空 `/data`。
- `publicBaseURL` 错误：媒体 URL 会指向错误地址，Apple TV 可能无法播放或加载缩略图。
- 导入后出现一个 `<none>` 映像：通常是正在运行的旧容器仍引用旧映像层。先确认新容器使用 `family-media-server:local`；旧容器删除后，未使用的 `<none>` 映像可以清理。
- 新客户端能连接但不能进入家庭媒体：检查 `/healthz` 是否包含 `"apiVersion":2`、`folder_browse`、`generated_data_clear` 和 `browse_sort`，否则实际运行的仍是旧服务端；缺少时间线能力只会隐藏年月模式。
- 外部程序更新后版本没变化：检查新增目录是否映射到 `/opt/family-media/bin`，以及健康接口的 `build.source` 是否为 `external`。
- 竖拍照片仍然侧转：部署包含方向修复的新程序后，执行“清理媒体数据”→“清理并重新扫描”，已有的错误缩略图不会仅因程序更新而自动覆盖。
- 日志反复出现 `Option autorotate`：正在运行有缺陷的过渡程序。停止容器，替换为最新独立程序并核对 SHA-256；随后重新导入最新 Docker tar，确保内置回退版本也已修复。
- 时间线请求返回 `invalid_time_zone`：替换包含内置 IANA 时区数据的最新独立程序；新程序不依赖容器的系统时区文件。
- HEIC 日志出现 `moov atom not found`：旧环境正在让 FFmpeg 直接猜测 HEIC 格式。导入包含 `libheif-tools` 的最新镜像，并确认 `/healthz` 的 `checks.heif.status` 为 `ok`。
