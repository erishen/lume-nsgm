#!/usr/bin/env bash
#
# 构建 lume-nsgm 应用镜像。
#
# 构建上下文必须是 work/lume（lume-core 与 lume-nsgm 的父目录），
# 因为 Dockerfile 同时要 lume-core 源码与生成器源码。本脚本自动定位。

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$(cd "$DIR/.." && pwd)"
IMAGE="${1:-lume-nsgm-app:latest}"

echo "==> build context : $CONTEXT"
echo "==> dockerfile    : $DIR/Dockerfile"
echo "==> image         : $IMAGE"

# OrbStack 的 buildx 活动追踪在部分环境报 operation not permitted，
# 用 legacy builder（DOCKER_BUILDKIT=0）规避。
DOCKER_BUILDKIT=0 docker build -f "$DIR/Dockerfile" -t "$IMAGE" "$CONTEXT"
echo "==> done. 运行： docker run --rm -p 18081:18081 -v lume-nsgm-data:/app/data $IMAGE"
