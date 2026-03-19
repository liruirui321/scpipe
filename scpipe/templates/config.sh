# =============================================================================
# config.sh - 本地测试配置（使用 upstream 输出）
# =============================================================================

# ---- Docker 镜像 ----
DOCKERHUB_USER="liruirui123"

IMG_SOUPX_ENV="${DOCKERHUB_USER}/r-soupx:latest"
IMG_DATAGET_ENV="${DOCKERHUB_USER}/py-scanpy:latest"
IMG_SCDATACG="${DOCKERHUB_USER}/r-seurat:latest"

# ---- 输出目录 ----
WORKDIR="$(pwd)/dataget_output"

# ---- 物种名（输出文件前缀）----
SPECIES="test_arabidopsis"

# ---- dnbc4tools 输出目录 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES=(
    "test_sample1"
)

DNBC4_OUTPUT_DIRS=(
    "${SCRIPT_DIR}/upstream_output/samples/test_sample1/test_sample1"
)

# ---- 线粒体基因列表（可选）----
MITOGENES_TXT=""

# ---- 参数 ----
MAX_RHO=0.2
MINCG=100
TFIDF_MIN=1
MITO_THRESHOLD=0.05
MINGENES=3
MINCELLS=1
GROUP_KEY="sample"
