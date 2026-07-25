# family-media-server 架构

服务端是部署在家庭 NAS 上的轻量 Go HTTP 服务。它负责索引和浏览原始媒体、生成缩略图并向 Apple 客户端提供静态文件；不承担 Jellyfin 登录或播放转码。

## 当前能力

- `/healthz`：运行依赖、扫描状态、客户端 capability 和构建信息。
- `/api/v1/browse`：目录、过滤、全局排序、递归月份和 cursor 分页。
- `/api/v1/timeline/index`：按客户端 IANA 时区统计年份和月份。
- `/api/v1/media|videos|photos`：保留的扁平分页接口。
- `/api/v1/admin/*`：扫描、状态、生成数据清理和单项缩略图重建。
- `/media/original/*` 与 `/media/thumbnails/*`：只读媒体输出。
- SQLite 嵌入式索引、JPEG EXIF 方向、HEIC/HEIF 转换和 FFmpeg 视频帧。

## 分层与依赖

```text
cmd -> bootstrap -> interfaces/http -> application -> domain
                  -> infrastructure -> domain/application interfaces
                  -> platform
```

- `cmd/family-media-server`：参数、信号和进程生命周期。
- `internal/bootstrap`：唯一的具体依赖组装位置。
- `internal/domain`：媒体模型、查询、错误和仓储接口，不依赖外层。
- `internal/application`：目录、时间线、扫描、缩略图、健康和清理用例。
- `internal/infrastructure`：SQLite、文件系统、图片解码、HEIF 和 FFmpeg。
- `internal/interfaces`：HTTP 参数/响应、路由、中间件和静态文件。
- `internal/platform`：配置、日志与构建信息。

HTTP 错误、URL 参数和 JSON 不进入领域层；SQLite 和外部命令细节不进入应用层。扫描管理器负责后台任务生命周期，HTTP 请求只触发或查询任务。

## 后台任务生命周期

- `jobs.Group` 由进程生命周期 Context 启动，并在关闭时等待 Runner 退出。
- `ScanManager` 是扫描状态与互斥关系的唯一所有者；定时扫描、手动扫描和清理后的重新扫描使用同一个生命周期。
- HTTP 请求只发出触发信号，客户端停止轮询不会取消已经接受的扫描；服务进程退出则会取消扫描和外部工具。
- 扫描与生成数据清理互斥，并发扫描触发复用当前任务，不启动第二个索引或缩略图工作流。
- 对外扫描状态仍为 `idle/running/completed/failed`，内部使用强类型状态，避免任意字符串进入状态机。

## 缩略图管线

缩略图应用服务只负责查询待处理项、写入状态和重试。基础设施 Pipeline 按以下顺序处理格式：

1. 视频直接调用 FFmpeg，并在首选时间点失败时回退首个可解码帧。
2. HEIC/HEIF 先调用 `heif-convert` 生成临时图片，再用原生图片生成器缩放；失败时最后尝试 FFmpeg。
3. JPEG、PNG 等照片优先使用原生解码和 EXIF 方向处理，失败时回退 FFmpeg。

临时文件由 Pipeline 统一清理，Context 取消会终止后续步骤。单项失败只保存稳定错误码，不把文件名、路径或外部命令完整输出写入索引、健康接口或日志。

## HTTP 与诊断日志

- 目录能力和时间线能力由 Bootstrap 显式注入 Handler，不使用运行时类型推断。
- 已知领域错误统一映射为原有 HTTP 状态码和错误码，接口结构保持稳定。
- 每个 HTTP 请求具有仅用于本次运行的操作 ID，访问日志记录事件码、模块、结果、方法、状态类别和耗时。
- 日志不记录请求 URL、查询参数、IP、Token、用户名、设备 ID、媒体 ID、文件名或媒体路径。
- panic、扫描失败和缩略图失败只记录稳定事件码；日志保持 `slog` 文本格式，便于直接在 NAS 容器控制台查看。

## 数据生命周期

- 原始媒体只读，服务端永不移动或删除。
- SQLite 索引、缩略图和转码临时目录均为可重建数据。
- 当前仍在开发阶段，表结构不匹配时允许重建索引，不增加历史 schema 兼容层。
- 列表分页和时间线月份查询下推 SQLite；客户端把 cursor 视为不透明值。
- 时间线优先使用拍摄时间，缺失时回退文件修改时间；年月边界由服务端按请求时区计算。

## 播放边界

家庭媒体返回原文件 URL，由 Apple 客户端直接播放兼容格式。Jellyfin 的 Direct Play、HLS 转码和播放会上报由客户端直接连接 Jellyfin 完成。服务端的 `transcode.workDir` 目前只作为生成数据边界保留，不提供家庭媒体播放转码 API。

架构决策见 [ADR 0001](adr/0001-layered-architecture.md)，接口契约见 [client_api.md](client_api.md)。
