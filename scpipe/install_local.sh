#!/bin/bash
# =============================================================================
# install_local.sh - 无 Docker 模式：安装所有本地依赖
# 用法: bash install_local.sh [install_dir]
# =============================================================================
set -euo pipefail

INSTALL_DIR="${1:-$(pwd)/.scpipe_local}"
DNBC4TOOLS_URL="ftp://ftp2.cngb.org/pub/CNSA/data7/CNP0008672/Single_Cell/CSE0000574/dnbc4tools-3.0.tar.gz"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
fail(){ echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; exit 1; }

mkdir -p "$INSTALL_DIR"
echo "安装目录: $INSTALL_DIR"

# ---- 1. conda 环境 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_YML="${SCRIPT_DIR}/../environment.yml"

if command -v conda &>/dev/null; then
    log "[1/4] 创建 conda 环境 scpipe ..."
    if conda env list | grep -q "scpipe"; then
        ok "conda env scpipe 已存在，跳过"
    else
        conda env create -f "$ENV_YML" -n scpipe 2>&1 | tail -5
        ok "conda env scpipe 创建完成"
    fi
else
    fail "未安装 conda。请先安装 miniconda: https://docs.conda.io/en/latest/miniconda.html"
fi

# ---- 2. 下载 dnbc4tools ----
DNBC4_DIR="${INSTALL_DIR}/dnbc4tools3.0"
if [[ -d "$DNBC4_DIR" ]]; then
    ok "[2/4] dnbc4tools 已存在: ${DNBC4_DIR}"
else
    log "[2/4] 下载 dnbc4tools 3.0 (~500MB) ..."
    curl -o "${INSTALL_DIR}/dnbc4tools-3.0.tar.gz" "$DNBC4TOOLS_URL" --progress-bar
    tar -xzf "${INSTALL_DIR}/dnbc4tools-3.0.tar.gz" -C "$INSTALL_DIR"
    rm -f "${INSTALL_DIR}/dnbc4tools-3.0.tar.gz"
    ok "dnbc4tools 安装完成: ${DNBC4_DIR}"
fi

# ---- 3. 安装 R 包 (SoupX, SeuratDisk) ----
log "[3/4] 检查 R 包 ..."
eval "$(conda shell.bash hook)"
conda activate scpipe

Rscript -e '
pkgs_needed <- c("SoupX")
pkgs_missing <- pkgs_needed[!pkgs_needed %in% installed.packages()[,"Package"]]
if (length(pkgs_missing) > 0) {
    install.packages(pkgs_missing, repos="https://cloud.r-project.org", Ncpus=4)
}
cat("SoupX OK\n")

if (!requireNamespace("SeuratDisk", quietly=TRUE)) {
    remotes::install_github("mojaveazure/seurat-disk", quiet=TRUE)
}
cat("SeuratDisk OK\n")
' 2>&1 | tail -5
ok "R 包检查完成"

# ---- 4. 安装 velocyto (pip) ----
log "[4/4] 检查 velocyto ..."
pip install --no-build-isolation velocyto 2>&1 | tail -3 || true
ok "velocyto 检查完成"

# ---- 写配置 ----
cat > "${INSTALL_DIR}/env.sh" << EOF
# scpipe 本地环境配置 (source 此文件激活)
export SCPIPE_MODE=local
export SCPIPE_LOCAL_DIR="${INSTALL_DIR}"
export DNBC4TOOLS_PATH="${DNBC4_DIR}/dnbc4tools"
export PATH="${DNBC4_DIR}:\${PATH}"
export LD_LIBRARY_PATH="${INSTALL_DIR}/dnbc4tools3.0/external/conda/lib:\${LD_LIBRARY_PATH:-}"
EOF

echo ""
echo "================================================"
echo " 安装完成！"
echo ""
echo " 使用方法:"
echo "   conda activate scpipe"
echo "   source ${INSTALL_DIR}/env.sh"
echo "   scpipe upstream all"
echo ""
echo " 或手动:"
echo "   bash run_upstream.sh all"
echo "================================================"
