#!/bin/bash
# =============================================================================
# run_pipeline.sh - dataget scRNAseq 分步骤 pipeline（适配 dnbc4tools 输出）
#
# 用法:
#   bash run_pipeline.sh [step]
#
#   step:
#     all        全部运行 (默认)
#     prep       step0: 整理 dnbc4tools 输出目录结构
#     wdl        step1: 从镜像提取 run_SoupX.R
#     soupx      step2: SoupX 去环境 RNA
#     scrublet   step3: Scrublet QC (原始 filter matrix)
#     sscrublet  step4: Scrublet QC (SoupX 校正后)
#     scdatacg   step5: h5ad → rds 格式转换
#     status     查看各步骤完成状态
#     reset      清除状态，允许重跑
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ---- 颜色输出 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; exit 1; }

# ---- 状态记录（完成的步骤写入文件，重启后不重跑） ----
STATUS_FILE="${WORKDIR}/.pipeline_status"
mark_done() { mkdir -p "$WORKDIR"; echo "$1=done"   >> "$STATUS_FILE"; }
mark_fail() { mkdir -p "$WORKDIR"; echo "$1=failed" >> "$STATUS_FILE"; }
is_done()   { grep -q "^$1=done$" "$STATUS_FILE" 2>/dev/null; }

mkdir -p "$WORKDIR"
touch "$STATUS_FILE"

# 由 step_prep 填充，其他步骤使用
RAW_DIRS=()
FILTER_DIRS=()
SPLICE_DIRS=()
UNSPLICE_DIRS=()

# =============================================================================
# STEP 0: 整理 dnbc4tools 输出目录
# dnbc4tools 输出结构:
#   <sample>/output/raw_matrix/          → RawMatrix
#   <sample>/output/filter_matrix/       → FilterMatrix
#   <sample>/output/RNAvelocity_matrix/  → 需拆分为 SpliceMatrix + UnspliceMatrix
#
# dataget 期望:
#   SpliceMatrix/  : matrix.mtx.gz (来自 spliced.mtx.gz)
#   UnspliceMatrix/: unspliced.mtx.gz
# =============================================================================
step_prep() {
    if is_done "prep"; then
        warn "[step0/prep] 已完成，跳过，从缓存加载路径"
        _load_prep_paths; return
    fi
    log "[step0/prep] 整理 dnbc4tools 输出目录 ..."

    local failed=0
    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local base="${DNBC4_OUTPUT_DIRS[$i]}"
        local raw_src="${base}/outs/raw_matrix"
        local filter_src="${base}/outs/filter_matrix"
        local velocity_src="${base}/outs/RNAvelocity_matrix"

        # 验证原始目录存在
        for d in "$raw_src" "$filter_src" "$velocity_src"; do
            [[ -d "$d" ]] || { warn "找不到目录: $d"; failed=1; }
        done
        [[ $failed -eq 0 ]] || continue

        # 创建 splice 目录: 把 spliced.mtx.gz 软链接为 matrix.mtx.gz
        local splice_dir="${WORKDIR}/prep/${s}/splice"
        mkdir -p "$splice_dir"
        ln -sf "$(realpath "${velocity_src}/spliced.mtx.gz")"   "${splice_dir}/matrix.mtx.gz"
        ln -sf "$(realpath "${velocity_src}/features.tsv.gz")"  "${splice_dir}/features.tsv.gz"
        ln -sf "$(realpath "${velocity_src}/barcodes.tsv.gz")"  "${splice_dir}/barcodes.tsv.gz"

        # 创建 unsplice 目录: unspliced.mtx.gz 名字本身就对
        local unsplice_dir="${WORKDIR}/prep/${s}/unsplice"
        mkdir -p "$unsplice_dir"
        ln -sf "$(realpath "${velocity_src}/unspliced.mtx.gz")" "${unsplice_dir}/unspliced.mtx.gz"
        ln -sf "$(realpath "${velocity_src}/features.tsv.gz")"  "${unsplice_dir}/features.tsv.gz"
        ln -sf "$(realpath "${velocity_src}/barcodes.tsv.gz")"  "${unsplice_dir}/barcodes.tsv.gz"

        ok "  [prep] ${s}: splice -> ${splice_dir}, unsplice -> ${unsplice_dir}"
    done

    [[ $failed -eq 0 ]] \
        && mark_done "prep" && _load_prep_paths \
        && ok "[step0/prep] 完成" \
        || { mark_fail "prep"; fail "[step0/prep] 部分 sample 目录缺失，请检查 DNBC4_OUTPUT_DIRS"; }
}

# 从 prep 输出填充路径数组（供后续步骤使用）
_load_prep_paths() {
    RAW_DIRS=(); FILTER_DIRS=(); SPLICE_DIRS=(); UNSPLICE_DIRS=()
    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local base="${DNBC4_OUTPUT_DIRS[$i]}"
        RAW_DIRS+=("${base}/outs/raw_matrix")
        FILTER_DIRS+=("${base}/outs/filter_matrix")
        SPLICE_DIRS+=("${WORKDIR}/prep/${s}/splice")
        UNSPLICE_DIRS+=("${WORKDIR}/prep/${s}/unsplice")
    done
}

# =============================================================================
# STEP 1: 从镜像提取 run_SoupX.R
# =============================================================================
step_wdl() {
    if is_done "wdl" && [[ -f "${WORKDIR}/run_SoupX.R" ]]; then
        warn "[step0/wdl] 已完成，跳过"; return
    fi
    log "[step0/wdl] 从镜像提取 run_SoupX.R ..."

    docker run --rm \
        -v "${WORKDIR}:/output" \
        -w /output \
        "${IMG_SOUPX_ENV}" \
        bash -c "cp /Scripts/dataget_scRNAseq/run_SoupX.R /output/run_SoupX.R" \
    && ok "[step0/wdl] 完成 -> ${WORKDIR}/run_SoupX.R" && mark_done "wdl" \
    || { mark_fail "wdl"; fail "[step0/wdl] 失败"; }
}

# =============================================================================
# STEP 1: SoupX（每个 sample 并行）
# =============================================================================
step_soupx() {
    if is_done "soupx"; then warn "[step1/soupx] 已完成，跳过"; return; fi
    [[ -f "${WORKDIR}/run_SoupX.R" ]] || fail "[step1/soupx] 找不到 run_SoupX.R，请先运行 step0: bash run_pipeline.sh wdl"

    log "[step1/soupx] 处理 ${#SAMPLES[@]} 个 sample ..."
    mkdir -p "${WORKDIR}/soupx"
    local pids=() failed=0

    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local raw_dir="${RAW_DIRS[$i]}"
        local filter_dir="${FILTER_DIRS[$i]}"
        local out_dir="${WORKDIR}/soupx/${s}"
        mkdir -p "$out_dir"
        log "  [soupx] 启动: $s"

        docker run --rm \
            -v "$(realpath "${WORKDIR}/run_SoupX.R"):/script/run_SoupX.R:ro" \
            -v "$(realpath "$raw_dir"):/input/raw:ro" \
            -v "$(realpath "$filter_dir"):/input/filter:ro" \
            -v "$out_dir:/output" \
            -w /output \
            "${IMG_SOUPX_ENV}" \
            /opt/conda/bin/Rscript /script/run_SoupX.R \
                --raw_path    /input/raw \
                --filter_path /input/filter \
                --sample_name "${s}" \
                --minCG       "${MINCG}" \
                --tfidfMin    "${TFIDF_MIN}" \
                --highestrho  "${MAX_RHO}" \
        > "${out_dir}/soupx.log" 2>&1 &
        pids+=($!)
    done

    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}"; then
            ok "  [soupx] ${SAMPLES[$i]} 完成"
        else
            warn "  [soupx] ${SAMPLES[$i]} 失败！日志: ${WORKDIR}/soupx/${SAMPLES[$i]}/soupx.log"
            failed=1
        fi
    done

    [[ $failed -eq 0 ]] \
        && ok "[step1/soupx] 全部完成" && mark_done "soupx" \
        || { mark_fail "soupx"; fail "[step1/soupx] 部分 sample 失败，查看上方日志路径"; }
}

# =============================================================================
# STEP 2 & 3: Scrublet（内部函数，复用）
#   $1 = tag         ("raw" | "soupx")
#   $2 = species     (输出 h5ad 的前缀)
#   matrix dirs 来自 FILTER_DIRS 或 soupx 输出
# =============================================================================
_run_scrublet() {
    local tag="$1" species="$2"
    shift 2
    # $@ = matrix_dir_0 matrix_dir_1 ... (与 SAMPLES 对应)
    local matrix_dirs=("$@")

    local outfile="${species}_dataget"
    local out_dir="${WORKDIR}/scrublet_${tag}/${outfile}"
    mkdir -p "$out_dir"
    log "[scrublet/${tag}] species=${species} -> $out_dir"

    # 构建 volume mounts
    local vol_args=()
    local matrix_csv="" splice_csv="" unsplice_csv="" samples_csv=""

    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local mdir="$(realpath "${matrix_dirs[$i]}")"
        local sdir="$(realpath "${SPLICE_DIRS[$i]}")"
        local udir="$(realpath "${UNSPLICE_DIRS[$i]}")"
        vol_args+=(-v "${mdir}:/input/matrix/${s}:ro")
        vol_args+=(-v "${sdir}:/input/splice/${s}:ro")
        vol_args+=(-v "${udir}:/input/unsplice/${s}:ro")
        matrix_csv+="/input/matrix/${s},"
        splice_csv+="/input/splice/${s},"
        unsplice_csv+="/input/unsplice/${s},"
        samples_csv+="${s},"
    done
    # 去掉末尾逗号
    matrix_csv="${matrix_csv%,}"
    splice_csv="${splice_csv%,}"
    unsplice_csv="${unsplice_csv%,}"
    samples_csv="${samples_csv%,}"

    local mito_vol="" mito_path="None_mito_genes.csv"
    if [[ -n "${MITOGENES_TXT:-}" && -f "${MITOGENES_TXT}" ]]; then
        mito_vol="-v $(realpath "$MITOGENES_TXT"):/input/mito_genes.txt:ro"
        mito_path="/input/mito_genes.txt"
    fi

    docker run --rm \
        "${vol_args[@]}" \
        ${mito_vol:-} \
        -v "${out_dir}:/workdir" \
        -w /workdir \
        "${IMG_DATAGET_ENV}" \
        bash -s <<BASHEOF
set -euo pipefail
mkdir -p "${outfile}"
cd "${outfile}"

echo "${matrix_csv}"   | tr ',' '\n' > Matrix.txt
echo "${splice_csv}"   | tr ',' '\n' > SpliceMatrix.txt
echo "${unsplice_csv}" | tr ',' '\n' > UnspliceMatrix.txt
echo "${samples_csv}"  | tr ',' '\n' > samples.txt

/opt/conda/bin/python << 'PYEOF'
import numpy as np, pandas as pd, scanpy as sc, anndata as ad
import seaborn as sns
from matplotlib.pyplot import savefig
from pathlib import Path
import shutil, gzip, os, scrublet, leidenalg

species        = "${species}"
group_key      = "${GROUP_KEY}"
input_mingenes = ${MINGENES}
input_mincells = ${MINCELLS}
mito_genes     = "${mito_path}"
try:    mito_threshold = float("${MITO_THRESHOLD}")
except: mito_threshold = 0.05

def copy_and_process(mf, ff, bf, target):
    cwd = os.getcwd(); os.chdir(target)
    for src, dst in [(mf,"matrix.mtx.gz"),(ff,"features.tsv.gz"),(bf,"barcodes.tsv.gz")]:
        shutil.copy(src, dst)
    for gz, out in [("matrix.mtx.gz","matrix.mtx"),("features.tsv.gz","features.tsv"),("barcodes.tsv.gz","barcodes.tsv")]:
        with gzip.open(gz,'rb') as g, open(out,'wb') as f: f.write(g.read())
    with open('features.tsv') as fi, open('genes.tsv','w') as fo:
        for line in fi: fo.write(line.strip()+'\t'+line.strip()+'\n')
    os.chdir(cwd)

def fill_genes(adata, genes):
    miss = genes - set(adata.var_names)
    if miss:
        m = ad.AnnData(X=pd.DataFrame(0,index=adata.obs_names,columns=list(miss)).values,
                       obs=adata.obs, var=pd.DataFrame(index=list(miss)))
        adata = ad.concat([adata,m],axis=1)[:,list(genes)]
    return adata

def fill_cells(adata, cells):
    miss = cells - set(adata.obs_names)
    if miss:
        m = ad.AnnData(X=pd.DataFrame(0,index=list(miss),columns=adata.var_names).values,
                       obs=pd.DataFrame(index=list(miss)), var=adata.var)
        adata = ad.concat([adata,m],axis=0)[list(cells),:]
    return adata

with open("Matrix.txt")    as f: matrix_list   = f.read().strip().split('\n')
with open("SpliceMatrix.txt") as f: splice_list = f.read().strip().split('\n')
with open("UnspliceMatrix.txt") as f: unsplice_list = f.read().strip().split('\n')
with open("samples.txt")   as f: sample_names  = f.read().strip().split('\n')

trans_m, trans_s, trans_u = [], [], []
for i, samp in enumerate(sample_names):
    for pname, flist, dest in [("filter",matrix_list,trans_m),("splice",splice_list,trans_s),("unsplice",unsplice_list,trans_u)]:
        dp = Path(f"./{samp}/{pname}"); dp.mkdir(parents=True, exist_ok=True)
        fp = os.path.abspath(dp); dest.append(fp)
        mf = flist[i]+'/matrix.mtx.gz' if pname!='unsplice' else flist[i]+'/unspliced.mtx.gz'
        copy_and_process(mf, flist[i]+'/features.tsv.gz', flist[i]+'/barcodes.tsv.gz', fp)

sc.settings.verbosity = 3
sc.settings.set_figure_params(dpi=80, facecolor='white')
adatas = {}
for i, key in enumerate(sample_names):
    af = sc.read_10x_mtx(trans_m[i], var_names='gene_ids')
    as_ = sc.read_10x_mtx(trans_s[i], var_names='gene_ids')
    au = sc.read_10x_mtx(trans_u[i], var_names='gene_ids')
    all_g = set(af.var_names)|set(as_.var_names)|set(au.var_names)
    all_c = set(af.obs_names)|set(as_.obs_names)|set(au.obs_names)
    af  = fill_genes(fill_cells(af,  all_c), all_g)
    as_ = fill_genes(fill_cells(as_, all_c), all_g)
    au  = fill_genes(fill_cells(au,  all_c), all_g)
    a = af.copy(); a.layers['splice']=as_.X; a.layers['unsplice']=au.X
    a.obs_names = [f"{c}_{key}" for c in a.obs_names]
    adatas[key] = a

adata = ad.concat(adatas, label=group_key, join="outer")
if os.path.exists(mito_genes):
    mt = pd.read_csv(mito_genes, header=None, names=["gene_name"])
    adata.var["mt"] = adata.var_names.isin(mt["gene_name"].tolist())
    sc.pp.calculate_qc_metrics(adata, qc_vars=["mt"], inplace=True, log1p=True)
    sc.pl.violin(adata, ["n_genes_by_counts","total_counts","pct_counts_mt"], jitter=0.4, multi_panel=True, save="_mito.pdf")
    adata = adata[adata.obs.pct_counts_mt < mito_threshold].copy()
else:
    sc.pp.calculate_qc_metrics(adata, inplace=True, log1p=True)

sc.pp.filter_cells(adata, min_genes=input_mingenes)
sc.pp.filter_genes(adata, min_cells=input_mincells)
sc.external.pp.scrublet(adata, batch_key=group_key)
adata.layers["counts"] = adata.X.copy()
sc.pp.normalize_total(adata); sc.pp.log1p(adata)
sc.pp.highly_variable_genes(adata, n_top_genes=2000, batch_key=group_key)
sc.tl.pca(adata); sc.pp.neighbors(adata); sc.tl.umap(adata)
sc.tl.leiden(adata, resolution=1)
adata.obs['predicted_doublet'] = adata.obs['predicted_doublet'].astype('category')
for res in [0.02,0.2,0.5,0.8,1.0,1.3,1.6,2.0]:
    sc.tl.leiden(adata, key_added=f"leiden_res_{res:4.2f}", resolution=res)
os.makedirs("marker_csv", exist_ok=True)
for res in ["leiden_res_0.50","leiden_res_0.80","leiden_res_1.00"]:
    sc.tl.rank_genes_groups(adata, groupby=res, method="wilcoxon")
    m = sc.get.rank_genes_groups_df(adata, group=None)
    m['gene']=m['names']; m['cluster']=m['group']; m['p_val_adj']=m['pvals_adj']; m['avg_log2FC']=m['logfoldchanges']
    m.to_csv(f"marker_csv/{res}.markers.csv", index=False)
with open('summary.txt','w') as f:
    f.write(f"{species} summary\nCells: {adata.n_obs}\nGenes: {adata.n_vars}\n")
adata.X = adata.layers["counts"]
adata.write_h5ad(species+'.h5ad', compression="gzip")
print("Done:", species+'.h5ad')
PYEOF

for s in \$(cat samples.txt); do rm -rf "\$s"; done
rm -f Matrix.txt SpliceMatrix.txt UnspliceMatrix.txt samples.txt
BASHEOF

}

step_scrublet() {
    if is_done "scrublet"; then warn "[step2/scrublet] 已完成，跳过"; return; fi
    _run_scrublet "raw" "${SPECIES}" "${FILTER_DIRS[@]}" \
    > "${WORKDIR}/scrublet_raw.log" 2>&1 \
    && ok "[step2/scrublet] 完成 -> ${WORKDIR}/scrublet_raw/${SPECIES}_dataget/${SPECIES}.h5ad" \
    && mark_done "scrublet" \
    || { mark_fail "scrublet"; fail "[step2/scrublet] 失败，查看日志: ${WORKDIR}/scrublet_raw.log"; }
}

step_sscrublet() {
    if is_done "sscrublet"; then warn "[step3/sscrublet] 已完成，跳过"; return; fi
    is_done "soupx" || fail "[step3/sscrublet] 需要先完成 step1/soupx"

    # SoupX 输出目录数组
    local soupx_dirs=()
    for s in "${SAMPLES[@]}"; do
        soupx_dirs+=("${WORKDIR}/soupx/${s}")
    done

    _run_scrublet "soupx" "${SPECIES}_soupx" "${soupx_dirs[@]}" \
    > "${WORKDIR}/scrublet_soupx.log" 2>&1 \
    && ok "[step3/sscrublet] 完成 -> ${WORKDIR}/scrublet_soupx/${SPECIES}_soupx_dataget/${SPECIES}_soupx.h5ad" \
    && mark_done "sscrublet" \
    || { mark_fail "sscrublet"; fail "[step3/sscrublet] 失败，查看日志: ${WORKDIR}/scrublet_soupx.log"; }
}

# =============================================================================
# STEP 4: scdatacg - h5ad → rds
# =============================================================================
step_scdatacg() {
    if is_done "scdatacg"; then warn "[step4/scdatacg] 已完成，跳过"; return; fi
    is_done "scrublet"  || fail "[step4/scdatacg] 需要先完成 step2/scrublet"
    is_done "sscrublet" || fail "[step4/scdatacg] 需要先完成 step3/sscrublet"

    local h5ad1="${WORKDIR}/scrublet_raw/${SPECIES}_dataget/${SPECIES}.h5ad"
    local h5ad2="${WORKDIR}/scrublet_soupx/${SPECIES}_soupx_dataget/${SPECIES}_soupx.h5ad"
    local out_dir="${WORKDIR}/scdatacg"
    mkdir -p "$out_dir"

    local failed=0
    for h5ad in "$h5ad1" "$h5ad2"; do
        [[ -f "$h5ad" ]] || { warn "找不到: $h5ad"; failed=1; continue; }
        local name; name="$(basename "$h5ad" .h5ad)"
        log "[step4/scdatacg] 转换: $name"

        docker run --rm \
            -v "$(realpath "$h5ad"):/input/${name}.h5ad:ro" \
            -v "${out_dir}:/output" \
            -w /output \
            "${IMG_SCDATACG}" \
            bash -c "
                python /script/deal_layers_ydgenomics.py \
                    --input_path /input/${name}.h5ad --sctype h5ad
                /software/conda/Anaconda/bin/Rscript /script/convert_rdsAh5ad2.R \
                    --input_file /input/${name}.h5ad --layers all
            " > "${out_dir}/${name}.log" 2>&1 \
        && ok "  [scdatacg] $name 完成" \
        || { warn "  [scdatacg] $name 失败！日志: ${out_dir}/${name}.log"; failed=1; }
    done

    [[ $failed -eq 0 ]] \
        && ok "[step4/scdatacg] 全部完成" && mark_done "scdatacg" \
        || { mark_fail "scdatacg"; fail "[step4/scdatacg] 部分文件转换失败"; }
}

# =============================================================================
# 状态显示
# =============================================================================
show_status() {
    echo ""
    echo "============ Pipeline 状态 ============"
    local steps=("prep:step0/prep" "wdl:step1/wdl" "soupx:step2/soupx" "scrublet:step3/scrublet" "sscrublet:step4/sscrublet" "scdatacg:step5/scdatacg")
    for entry in "${steps[@]}"; do
        local key="${entry%%:*}" name="${entry##*:}"
        if   grep -q "^${key}=done$"   "$STATUS_FILE" 2>/dev/null; then echo -e "  ${GREEN}✓${NC} $name"
        elif grep -q "^${key}=failed$" "$STATUS_FILE" 2>/dev/null; then echo -e "  ${RED}✗${NC} $name  ← 失败"
        else echo -e "  ${YELLOW}○${NC} $name  (未运行)"
        fi
    done
    echo "======================================="
    echo ""
}

# =============================================================================
# 入口
# =============================================================================
TARGET="${1:-all}"

echo "======================================="
echo " dataget scRNAseq Pipeline"
echo " WORKDIR : $WORKDIR"
echo " SPECIES : $SPECIES"
echo " SAMPLES : ${SAMPLES[*]}"
echo " TARGET  : $TARGET"
echo "======================================="

case "$TARGET" in
    all)
        step_prep
        step_wdl; step_soupx; step_scrublet; step_sscrublet; step_scdatacg
        ;;
    prep)      step_prep ;;
    wdl)       step_prep; step_wdl ;;
    soupx)     step_prep; step_soupx ;;
    scrublet)  step_prep; step_scrublet ;;
    sscrublet) step_prep; step_sscrublet ;;
    scdatacg)  step_prep; step_scdatacg ;;
    status)    show_status; exit 0 ;;
    reset)
        warn "清除所有步骤状态 ..."
        rm -f "$STATUS_FILE"
        ok "已重置，可重新运行任意步骤"
        exit 0
        ;;
    *)
        echo "未知步骤: $TARGET"
        echo "可用: all | wdl | soupx | scrublet | sscrublet | scdatacg | status | reset"
        exit 1
        ;;
esac

show_status
ok "完成！结果目录: $WORKDIR"
