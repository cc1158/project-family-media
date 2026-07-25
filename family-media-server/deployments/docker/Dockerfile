FROM golang:1.26-alpine AS builder
ARG GOPROXY=https://proxy.golang.org,direct
ARG VERSION=local
ARG BUILD_COMMIT=unknown
ARG BUILD_TIME=unknown
WORKDIR /src
COPY go.mod ./
COPY go.sum ./
COPY cmd ./cmd
COPY internal ./internal
RUN GOPROXY=${GOPROXY} CGO_ENABLED=0 go build \
    -ldflags "-s -w -X family-media-server/internal/platform/buildinfo.Version=${VERSION} -X family-media-server/internal/platform/buildinfo.Commit=${BUILD_COMMIT} -X family-media-server/internal/platform/buildinfo.BuiltAt=${BUILD_TIME}" \
    -o /out/family-media-server ./cmd/family-media-server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates ffmpeg libheif-tools tzdata && addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=builder /out/family-media-server /app/family-media-server
COPY configs/config.example.yaml /app/config.yaml
COPY deployments/docker/entrypoint.sh /app/entrypoint.sh
RUN chmod 755 /app/entrypoint.sh && mkdir -p /data && chown -R app:app /data
USER app
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["-config", "/app/config.yaml"]
