# FamilyMedia Jellyfin 接入设计稿

状态：历史设计记录；核心方案已经实现，当前行为以 `architecture.md` 和代码为准
目标平台：tvOS、iOS  
当前能力：在不影响家庭媒体服务的前提下登录 Jellyfin、浏览媒体库，并通过 PlaybackInfo 执行 Direct Play 或 HLS 转码及播放会上报。

## 1. 设计结论

客户端同时连接并保存两个独立服务。二者不是互斥选项，也不存在“启用一个就停用另一个”的全局当前来源：

```text
                         ┌─ family-media-server（现有 Go 服务）
tvOS / iOS → 数据源选择 ─┤
                         └─ Jellyfin Server（NAS 上已有服务）
```

不让 `family-media-server` 代理 Jellyfin，原因如下：

- 自研服务继续保持无登录、轻量部署，不承担 Jellyfin 凭据管理。
- Jellyfin 的权限、用户媒体库和播放策略直接生效。
- 少一层媒体转发，避免 NAS 内重复占用连接和带宽。
- Jellyfin 升级产生的接口适配集中在 Apple 客户端的独立适配器中。

客户端内部使用统一的媒体浏览模型。现有服务和 Jellyfin 分别负责把自己的响应转换为该模型，网格和播放器不关心数据来自哪里。

两个连接状态独立持久化：

```text
家庭媒体服务：地址 + 无登录连接状态
Jellyfin：地址 + 用户会话 Token
```

- App 启动后两个来源同时可用。
- 浏览 Jellyfin 不会断开家庭媒体服务。
- 浏览家庭媒体服务不会注销 Jellyfin。
- 首页的来源入口只是导航入口，不是单选开关。
- 只有用户在 Jellyfin 设置中明确点击“退出登录”，才会删除 Jellyfin 会话。

## 2. 首期范围

### 包含

- 同时配置一个家庭媒体服务和一个 Jellyfin 服务。
- Jellyfin 地址、用户名和密码登录。
- 登录后保存访问令牌，重新打开 App 不必再次输入密码。
- 显示 Jellyfin 用户可访问的媒体库。
- 进入媒体库后分页浏览视频和照片。
- 加载 Jellyfin 封面或缩略图。
- 使用现有全屏查看器显示照片。
- 使用 AVPlayer 直接播放 Apple 设备支持的视频流。
- Jellyfin 连接检查、登录状态、退出登录。
- tvOS 与 iOS 使用同一套 Core 实现。

### 当前仍不包含

- 断点续播、播放进度同步和“继续观看”。
- 剧集层级、季、演员、类型等完整 Jellyfin 元数据体验。
- 搜索、收藏、字幕和多音轨选择。
- Quick Connect、服务器自动发现和多 Jellyfin 服务器。
- 将两个来源的媒体混合成同一个列表。

这些能力可以后续逐项增加，不应阻塞稳定的首期接入。

## 3. 用户体验设计

### 3.1 tvOS

建议把当前首页改为两个并存的数据源入口：

```text
FamilyMedia

┌────────────────────┐  ┌────────────────────┐  ┌──────────────┐
│ 家庭媒体            │  │ Jellyfin           │  │ 设置         │
│ 自研服务中的照片视频 │  │ NAS 媒体库          │  │              │
└────────────────────┘  └────────────────────┘  └──────────────┘
```

进入“家庭媒体”后保持当前三个入口：全部媒体、视频、照片。

进入“Jellyfin”后的推荐结构：

```text
Jellyfin
├── 家庭视频
├── 电影
├── 电视剧
└── 照片
```

- 未登录时，Jellyfin 卡片显示“请先在设置中登录”。点击后进入 Jellyfin 设置。
- 已登录时，先显示该用户有权限访问的媒体库。
- 进入一个媒体库后显示媒体网格。
- 第一版将可直接播放的 `Video`、`Movie`、`Episode` 映射为视频；`Photo` 映射为照片。
- 普通文件夹、剧集、季、电影合集、照片相册和播放列表等容器继续进入下一级，不把容器伪装成可播放媒体。

### 3.2 iOS

现有四个 Tab 不适合再平铺一组 Jellyfin Tab。建议改为：

```text
Tab 1：媒体
  ├── 家庭媒体
  └── Jellyfin

Tab 2：设置
```

“媒体”页同时显示两个已配置来源，再进入所选来源的分类或媒体库。这里的选择只代表本次导航到哪个页面，不改变登录状态。这样 tvOS 和 iOS 的信息结构一致，也为以后增加其他来源留出空间。

不采用在设置中选择“当前媒体来源”的单选方案，因为它会造成两个来源互斥的体验，也无法快速并存浏览。

### 3.3 设置页

设置页分为三个区域：

```text
家庭媒体服务
  服务地址
  保存 / 检查连接
  扫描媒体库 / 刷新扫描状态

Jellyfin
  服务地址
  用户名
  密码（仅登录时输入，不持久化）
  登录并检查 / 退出登录
  登录状态、服务器名称、当前用户

播放
  连续自动播放数量
  照片停留时间
```

家庭媒体服务的扫描操作不会出现在 Jellyfin 区域。Jellyfin 媒体扫描仍由 Jellyfin 管理界面负责。

## 4. Core 架构设计

### 4.1 不继续扩大现有 `MediaServicing`

现有协议同时包含浏览和自研服务器管理：

```swift
fetchMedia
checkHealth
triggerScan
fetchScanStatus
regenerateThumbnail
```

Jellyfin 没有与这些操作完全相同的客户端语义。建议拆成小协议：

```swift
public protocol MediaCatalogServicing: Sendable {
    func fetchMedia(
        containerID: String?,
        filter: MediaFilter,
        request: MediaPageRequest
    ) async throws -> MediaPage
}

public protocol MediaSourceHealthChecking: Sendable {
    func checkConnection() async throws -> MediaSourceStatus
}

public protocol FamilyMediaAdminServicing: Sendable {
    func triggerScan() async throws -> ScanTriggerResponse
    func fetchScanStatus() async throws -> ScanStatus
    func regenerateThumbnail(...) async throws -> ThumbnailRegenerationResponse
}
```

为控制改动，现有 `MediaServicing` 可在迁移期组合上述协议，原测试继续有效。Jellyfin 只实现它实际具备的协议。

### 4.2 数据源模型

新增稳定的数据源身份：

```swift
public enum MediaSourceID: String, Codable, Sendable {
    case familyMedia
    case jellyfin
}
```

媒体 ID 必须包含来源，避免两个服务返回相同 ID：

```text
familyMedia:<server-media-id>
jellyfin:<jellyfin-item-id>
```

`MediaItem` 建议增加：

```swift
sourceID: MediaSourceID
containerID: String?
isContainer: Bool
```

播放 URL 和图片 URL 仍由适配器生成后交给现有 UI。封面与照片由共享图片管线加载，Token 通过认证请求头发送，URL、缓存键和诊断信息均不保存明文 Token；不同登录会话使用隔离的内存缓存分区。AVPlayer 的 Direct Play/HLS 地址仍可携带短期查询认证，以保证 HLS 清单和分片请求在 iOS/tvOS 上可靠鉴权，但这些地址不得进入日志或持久缓存。

### 4.3 建议目录

```text
Shared/FamilyMediaCore/Sources/FamilyMediaCore
├── MediaSources
│   ├── MediaSource.swift
│   ├── MediaSourceRegistry.swift
│   ├── FamilyMedia
│   │   └── FamilyMediaService.swift
│   └── Jellyfin
│       ├── JellyfinAPIClient.swift
│       ├── JellyfinModels.swift
│       ├── JellyfinMediaService.swift
│       ├── JellyfinAuthenticationService.swift
│       └── JellyfinConfigurationStore.swift
├── Security
│   └── KeychainCredentialStore.swift
└── Stores
    ├── MediaSourcesStore.swift
    ├── JellyfinLoginStore.swift
    └── MediaLibraryStore.swift
```

不引入第三方 Jellyfin Swift SDK。首期使用的接口很少，直接定义小型 Codable DTO 更可控，也不会给 tvOS/iOS 增加较大的依赖。

## 5. Jellyfin 接口映射

具体字段在实现时按目标 Jellyfin 稳定版本的 OpenAPI 再核对。设计使用以下能力：

### 5.1 连接检查

```http
GET /System/Info/Public
```

用途：验证地址、获取服务器名称和版本，不需要先登录。

### 5.2 用户名密码登录

```http
POST /Users/AuthenticateByName
Content-Type: application/json
Authorization: MediaBrowser Client="FamilyMedia", Device="Apple TV|iPhone", DeviceId="...", Version="..."

{
  "Username": "...",
  "Pw": "..."
}
```

保存响应中的用户 ID 和访问令牌。密码只存在于登录界面的短生命周期状态中。

### 5.3 获取媒体库

```http
GET /Users/{userId}/Views
```

只显示用户可见的媒体库。每个媒体库作为容器卡片展示。

### 5.4 获取媒体项

```http
GET /Users/{userId}/Items
    ?ParentId={libraryOrFolderId}
    &Recursive=false
    &IncludeItemTypes=CollectionFolder,Folder,Series,Season,BoxSet,Playlist,PlaylistsFolder,PhotoAlbum,Movie,Episode,Video,Photo
    &StartIndex={offset}
    &Limit={limit}
    &SortBy=SortName
    &SortOrder=Ascending
```

Jellyfin 使用 `StartIndex + Limit`；现有客户端使用 cursor。适配器将下一页 offset 编码成内部 cursor，UI 无需感知分页差异。

`Playlist` 容器使用 Jellyfin 的专用成员接口，不能用普通文件夹的 `ParentId` 代替：

```http
GET /Playlists/{playlistId}/Items
    ?UserId={userId}
    &StartIndex={offset}
    &Limit={limit}
```

客户端在容器上下文中保存内部播放列表路由，进入时选择该接口，并保留服务器返回的播放列表顺序。普通文件夹、合集、相册、剧集和季仍使用 `/Users/{userId}/Items`。

### 5.5 图片

```http
GET /Items/{itemId}/Images/Primary
    ?maxWidth=600
    &quality=85
    &tag={imageTag}
```

没有 Primary Image 时显示现有占位图，不把原照片当作网格缩略图下载。

### 5.6 当前播放

视频进入查看器时先请求：

```http
POST /Items/{itemId}/PlaybackInfo
```

服务端根据 Apple 设备能力返回 Direct Play、Direct Stream 或 HLS Transcode。普通 Jellyfin API、封面和照片请求通过认证头发送 Token，不把 Token 放进图片 URL。AVPlayer/HLS 无法为每个分片附加认证头，因此最终播放 URL 可以携带短期查询认证，但该 URL 不得写入日志、诊断或持久缓存。

播放开始、进度、暂停和停止分别通过 Jellyfin Sessions 接口上报；切换项目、失败、退出和进入后台都必须结束旧会话及转码任务。

## 6. 安全设计

- Jellyfin 密码不写入 `UserDefaults`、日志或错误信息。
- 登录成功后清空内存中的密码输入。
- Access Token 和 User ID 存储在 Keychain。
- 服务地址、服务器显示名称可存储在 UserDefaults。
- 每次请求都只连接用户配置的 Jellyfin 地址。
- 退出登录时删除 Keychain 中的 Jellyfin 凭据。
- 收到 401 时保留服务器地址，清除失效令牌并提示重新登录。
- 局域网 HTTP 可继续使用，但如果将来需要外网访问，应使用 HTTPS 或 VPN，不直接暴露 Jellyfin HTTP 端口。

## 7. 错误与状态设计

对用户显示可操作的中文信息：

| 场景 | 提示 |
|---|---|
| 地址不可达 | 无法连接 Jellyfin，请检查地址和 NAS 网络 |
| 用户名或密码错误 | Jellyfin 用户名或密码不正确 |
| Token 失效 | Jellyfin 登录已失效，请重新登录 |
| 无媒体库权限 | 当前用户没有可访问的媒体库 |
| 媒体为空 | 此媒体库暂无可浏览内容 |
| AVPlayer 不支持 | 此视频格式暂不支持直接播放 |
| 服务器返回未知字段 | Jellyfin 返回的数据无法解析，请检查版本兼容性 |

单个媒体没有图片不视为错误；整个页面不会因为一张封面失败而进入失败状态。

## 8. 兼容性和测试

### Core 单元测试

- 登录请求的路径、方法、请求体和 Authorization 头。
- 登录响应保存 Token，密码不持久化。
- 401 清除失效会话。
- Jellyfin Item 到 `MediaItem` 的视频、照片及常见容器映射。
- `StartIndex` 与内部 cursor 的双向转换。
- 播放列表专用接口、分页和原始条目顺序。
- 图片、视频和照片 URL 的 base path、查询参数编码。
- Jellyfin 地址包含反向代理子路径时仍能正确拼接。
- 两个来源出现相同服务端 ID 时，客户端 ID 不冲突。
- 空媒体库、缺图和部分字段缺失。

### App 验证

- `swift test`
- tvOS generic build
- iOS generic build
- 真机连接 NAS Jellyfin，检查登录、分页、图片和直接播放。
- App 重启后会话恢复。
- Jellyfin 重启、Token 注销和 NAS 断网时不崩溃。

## 9. 分阶段实施计划

### 阶段 A：Core 接入

1. 拆分浏览与管理协议，保持现有服务行为不变。
2. 增加数据源身份、Jellyfin 配置和 Keychain 存储。
3. 实现 Jellyfin 登录、媒体库、媒体项和 URL 适配。
4. 增加 Core 单元测试。

### 阶段 B：界面接入

1. tvOS 增加来源首页和 Jellyfin 媒体库页。
2. iOS 改为“媒体、设置”两层结构。
3. 两端设置页增加 Jellyfin 登录区。
4. 复用现有网格和查看器，并隐藏 Jellyfin 不支持的缩略图重建操作。

### 阶段 C：稳定性验证

1. 运行 Core、tvOS 和 iOS 构建验证。
2. 使用真实 NAS 做登录和播放验证。
3. 根据实际视频编码统计决定是否进入转码阶段。

### 后续可选阶段：Jellyfin 完整播放

- 获取 PlaybackInfo 并提交 Apple 设备能力描述。
- 在 Direct Play、Direct Stream 和 Transcode 间选择。
- 支持 HLS 转码、字幕和音轨。
- 上报播放开始、进度和停止，支持断点续播。

## 10. 需要确认的设计项

建议按以下默认方案实施：

1. Jellyfin 先显示媒体库，再进入媒体项，不把所有内容揉成一个列表。
2. 首期只做直接播放，不兼容格式给出提示。
3. iOS 改成“媒体 + 设置”两个主 Tab，来源放在媒体页内。
4. 家庭媒体服务与 Jellyfin 同时连接、同时可用；首期在此基础上支持一个 Jellyfin 服务和一个 Jellyfin 用户。
5. Jellyfin Token 存 Keychain，密码不保存。

确认这五项后即可按阶段 A 开始实现。实现前还需要记录 NAS 当前 Jellyfin 的稳定版版本号，以便锁定接口兼容测试范围。
