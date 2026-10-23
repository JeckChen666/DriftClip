# DriftClip 多阶段构建：Web（React）→ 服务端（Go）→ 运行时（Alpine）
# 构建上下文为仓库根目录（docker compose build 时由 dockerfile 相对路径确定）。

# --- Stage 1: 构建 React Web 产物 ---
FROM node:24-alpine AS web-build
WORKDIR /build/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# --- Stage 2: 构建 Go 服务端 ---
FROM golang:1.26-alpine AS go-build
WORKDIR /build/server
COPY server/ ./
RUN go mod download \
    && CGO_ENABLED=0 go build -o /out/driftclip-server ./cmd/driftclip-server

# --- Stage 3: 运行时 ---
FROM alpine:3.24
WORKDIR /app
COPY --from=go-build /out/driftclip-server ./driftclip-server
COPY --from=web-build /build/web/dist ./web/dist
ENV DRIFTCLIP_WEB_STATIC_DIR=/app/web/dist
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["/app/driftclip-server"]
