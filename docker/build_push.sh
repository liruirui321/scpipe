#!/bin/bash
# =============================================================================
# build_push.sh - 构建 Docker 镜像并推送到 Docker Hub
#
# 用法:
#   bash build_push.sh <your-dockerhub-username> [镜像名|all]
#
# 示例:
#   bash build_push.sh liruirui123 all
#   bash build_push.sh liruirui123 py-scanpy
# =============================================================================

set -euo pipefail

DOCKERHUB_USER="${1:?用法: bash build_push.sh <dockerhub-user> [dnbc4tools|r-soupx|py-scanpy|r-seurat|all]}"
TARGET="${2:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; exit 1; }

build_push() {
    local name="$1"   # 镜像名，如 py-scanpy
    local full_tag="${DOCKERHUB_USER}/${name}:latest"

    log "====== Building: ${full_tag} ======"

    # 用 docker/ 作为构建上下文，-f 指定子目录的 Dockerfile
    # 这样所有 Dockerfile 都能 COPY scripts/ 目录
    docker build \
        --platform linux/amd64 \
        -f "${SCRIPT_DIR}/${name}/Dockerfile" \
        -t "${full_tag}" \
        "${SCRIPT_DIR}" \
    && ok "Build 完成: ${full_tag}" \
    || fail "Build 失败: ${full_tag}"

    log "Pushing: ${full_tag} ..."
    docker push "${full_tag}" \
    && ok "Push 完成: ${full_tag}" \
    || fail "Push 失败: ${full_tag}，请先运行 docker login"
}

echo ""
echo "================================================"
echo " Docker Hub 用户: ${DOCKERHUB_USER}"
echo " 构建目标: ${TARGET}"
echo "================================================"
echo ""

case "$TARGET" in
    all)
        build_push "dnbc4tools"
        build_push "r-soupx"
        build_push "py-scanpy"
        build_push "r-seurat"
        ;;
    dnbc4tools) build_push "dnbc4tools" ;;
    r-soupx)    build_push "r-soupx" ;;
    py-scanpy)  build_push "py-scanpy" ;;
    r-seurat)   build_push "r-seurat" ;;
    *)
        echo "未知目标: $TARGET"
        echo "可用: all | dnbc4tools | r-soupx | py-scanpy | r-seurat"
        exit 1
        ;;
esac

echo ""
echo "================================================"
echo " 全部完成！镜像地址:"
echo "   ${DOCKERHUB_USER}/dnbc4tools:latest"
echo "   ${DOCKERHUB_USER}/r-soupx:latest"
echo "   ${DOCKERHUB_USER}/py-scanpy:latest"
echo "   ${DOCKERHUB_USER}/r-seurat:latest"
echo ""
echo " 服务器上提取脚本:"
echo "   docker run --rm ${DOCKERHUB_USER}/py-scanpy:latest tar -cf - -C /scripts . | tar -xf -"
echo "================================================"
