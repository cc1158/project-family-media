# family-media-server 需求说明与技术架构文档

> 历史说明：本文记录最初 MVP 需求，不代表 `1.0.0-rc.1` 当前能力。当前实现以 `architecture.md`、`client_api.md` 和根目录 README 为准。

## 1. 项目名称

`family-media-server`

## 2. 项目背景

本项目用于家庭局域网内的媒体服务。

当前家庭中的儿童视频和照片存储在 NAS 上，Apple TV 与 NAS 位于同一个局域网。计划开发一个 Apple TV 客户端，用于浏览和播放 NAS 上的视频、照片。

为了避免 Apple TV 客户端直接访问 SMB / NFS，也为了降低 tvOS 端开发复杂度，需要在 NAS 上部署一个轻量级 HTTP 服务端。

该服务端负责：

- 扫描 NAS 上的视频目录
- 扫描 NAS 上的照片目录
- 向 Apple TV 客户端返回媒体列表 JSON
- 通过 HTTP 提供视频和照片文件访问
- 后续可扩展缩略图、转码、媒体索引等功能

MVP 阶段重点是简单、稳定、可运行，不追求复杂功能。

---

## 3. 项目目标

### 3.1 MVP 目标

MVP 阶段实现以下能力：

- 启动一个 HTTP 服务
- 提供健康检查接口
- 扫描指定视频目录
- 扫描指定照片目录
- 支持扫描一个混合存放照片和视频的统一媒体目录
- 返回视频列表 JSON
- 返回照片列表 JSON
- 提供视频静态文件访问
- 提供照片静态文件访问
- 支持通过配置文件指定媒体目录、服务端口、访问地址
- 服务端可以部署在 NAS / Linux 小主机 / Docker 中

### 3.2 非目标

MVP 阶段不实现以下功能：

- 用户登录
- 权限管理
- 数据库存储
- 视频转码
- HLS 切片
- 视频缩略图生成
- 照片缩略图生成
- 媒体元数据解析
- 播放历史
- 收藏
- 搜索
- 外网访问
- 多用户
- Web 管理后台

---

## 4. 技术选型

### 4.1 开发语言

使用：

```text
Go
```

---

## 5. 当前实现规划

MVP 服务端采用 Go 标准库实现，先不引入 Web 框架和数据库，保持部署简单。

项目结构按正式服务拆分：

- `cmd/family-media-server`: 服务入口
- `internal/bootstrap`: 依赖组装
- `internal/domain/media`: 媒体领域模型与仓储接口
- `internal/application/media`: 媒体目录应用用例
- `internal/application/jobs`: 后台任务入口
- `internal/application/indexing`: 媒体索引迭代入口
- `internal/application/thumbnail`: 缩略图迭代入口
- `internal/application/transcode`: 转码迭代入口
- `internal/infrastructure/media/sqlite`: SQLite 媒体索引仓储
- `internal/interfaces/http`: HTTP API、静态文件服务、中间件
- `internal/platform/config`: 配置加载
- `configs`: 配置文件
- `deployments/docker`: Docker 部署

接口规划：

- `GET /healthz`
- `GET /api/v1/media`
- `GET /api/v1/videos`
- `GET /api/v1/photos`
- `POST /api/v1/admin/scan`
- `GET /api/v1/admin/scan/status`
- `GET /media/original/{path}`
- `GET /media/thumbnails/{path}`
