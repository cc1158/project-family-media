# family-media-server API 概览

客户端契约、参数、响应和错误码以 [client_api.md](client_api.md) 为准。本页只列出当前路由，避免维护第二份重复协议。

```text
GET  /healthz
GET  /api/v1/media
GET  /api/v1/videos
GET  /api/v1/photos
GET  /api/v1/browse
GET  /api/v1/timeline/index
POST /api/v1/admin/scan
GET  /api/v1/admin/scan/status
POST /api/v1/admin/data/clear
POST /api/v1/admin/media/{id}/thumbnail/regenerate
GET  /media/original/{path}
GET  /media/thumbnails/{path}
```

所有 cursor 均为不透明值。调用方不得解析、拼接或跨目录、过滤、排序、月份及时区复用 cursor。
