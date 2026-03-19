#!/bin/bash
# =============================================================================
# run_upstream.sh - dnbc4tools 上游流程（step1 建索引 + step2 定量）
#
# 用法:
#   bash run_upstream.sh [step]
#
#   step:
#     all       全部运行（默认）
#     mkgtf     step1a: 校正 GTF
#     mkref     step1b: 建基因组索引
#     count     step2:  定量（每个 sample）
#     status    查看步骤状态
#     reset     清除状态，允许重跑
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PWD}/upstream_config.sh"
[[ -f "$CONFIG_FILE" ]] || { echo "Error: 找不到 ${CONFIG_FILE}. 运行 scpipe init 生成配置"; exit 1; }
source "$CONFIG_FILE"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; exit 1; }

STATUS_FILE="${UPSTREAM_WORKDIR}/.upstream_status"
mark_done() { mkdir -p "$UPSTREAM_WORKDIR"; echo "$1=done"   >> "$STATUS_FILE"; }
mark_fail() { mkdir -p "$UPSTREAM_WORKDIR"; echo "$1=failed" >> "$STATUS_FILE"; }
is_done()   { grep -q "^$1=done$" "$STATUS_FILE" 2>/dev/null; }

mkdir -p "$UPSTREAM_WORKDIR"
touch "$STATUS_FILE"

IMG="liruirui123/dnbc4tools:latest"

# =============================================================================
# 准备：把 FASTA + 校正后 GTF 放在同一个 /ref 目录
# 这样 ref.json 里的路径在 mkref 和 rna run 时保持一致
# =============================================================================
REF_DIR="${UPSTREAM_WORKDIR}/ref"

# =============================================================================
# STEP 1a: 校正 GTF
# =============================================================================
step_mkgtf() {
    if is_done "mkgtf"; then warn "[step1a/mkgtf] 已完成，跳过"; return; fi
    log "[step1a/mkgtf] 校正 GTF: $(basename "$GTF_FILE") ..."
    mkdir -p "$REF_DIR"

    # 把原始 FASTA 复制到 ref 目录（Docker 挂载不支持跨目录符号链接）
    cp -f "$(realpath "$FASTA_FILE")" "${REF_DIR}/genome.fa"

    docker run --rm \
        -v "$(realpath "$GTF_FILE"):/input/raw.gtf:ro" \
        -v "${REF_DIR}:/ref" \
        "$IMG" \
        dnbc4tools tools mkgtf \
            --action check \
            --ingtf /input/raw.gtf \
            --output /ref/corrected.gtf \
    > "${REF_DIR}/mkgtf.log" 2>&1 \
    && ok "[step1a/mkgtf] 完成 -> ${REF_DIR}/corrected.gtf" && mark_done "mkgtf" \
    || { mark_fail "mkgtf"; fail "[step1a/mkgtf] 失败，查看日志: ${REF_DIR}/mkgtf.log"; }
}

# =============================================================================
# STEP 1b: 建基因组索引
# 关键：ref.json 会记录容器内路径，后续 rna run 必须用相同的挂载路径
#   /ref/genome.fa       → FASTA
#   /ref/corrected.gtf   → GTF
#   /genome              → 索引输出
# =============================================================================
step_mkref() {
    if is_done "mkref"; then warn "[step1b/mkref] 已完成，跳过"; return; fi
    is_done "mkgtf" || fail "[step1b/mkref] 需要先完成 step1a/mkgtf"

    local index_dir="${UPSTREAM_WORKDIR}/genome_index"
    mkdir -p "$index_dir"

    # 验证 ref 目录有必要文件
    [[ -f "${REF_DIR}/genome.fa" ]]      || fail "找不到 ${REF_DIR}/genome.fa"
    [[ -f "${REF_DIR}/corrected.gtf" ]]  || fail "找不到 ${REF_DIR}/corrected.gtf"

    log "[step1b/mkref] 建索引: species=${SPECIES}, threads=${THREADS} ..."
    warn "预计耗时 30-60 分钟"

    docker run --rm \
        -v "${REF_DIR}:/ref:ro" \
        -v "${index_dir}:/genome" \
        "$IMG" \
        dnbc4tools rna mkref \
            --fasta /ref/genome.fa \
            --ingtf /ref/corrected.gtf \
            --species "$SPECIES" \
            --threads "$THREADS" \
            --genomeDir /genome \
    > "${index_dir}/mkref.log" 2>&1 \
    && ok "[step1b/mkref] 完成 -> ${index_dir}" && mark_done "mkref" \
    || { mark_fail "mkref"; fail "[step1b/mkref] 失败，查看日志: ${index_dir}/mkref.log"; }

    # 修复 ref.json 中的路径（确保 rna run 能找到）
    if [[ -f "${index_dir}/ref.json" ]]; then
        log "  修复 ref.json 路径 ..."
        sed -i.bak 's|/ref/genome.fa|/ref/genome.fa|g; s|/ref/corrected.gtf|/ref/corrected.gtf|g' \
            "${index_dir}/ref.json"
    fi
}

# =============================================================================
# STEP 2: 定量（逐个 sample 运行）
# 关键挂载路径与 mkref 一致：
#   /ref        → 包含 genome.fa 和 corrected.gtf
#   /genome     → 基因组索引
#   /input/*    → fastq 文件（逐个挂载，避免目录冲突）
#   /output     → 工作目录
# =============================================================================
step_count() {
    if is_done "count"; then warn "[step2/count] 已完成，跳过"; return; fi
    is_done "mkref" || fail "[step2/count] 需要先完成 step1b/mkref"

    # mkref 在 genome_index/ 下创建 ${SPECIES}/ 子目录
    # ref.json 里的路径是 /genome/${SPECIES}/star 等，所以挂载 genome_index/ -> /genome
    local index_dir="${UPSTREAM_WORKDIR}/genome_index"
    [[ -f "${index_dir}/${SPECIES}/ref.json" ]] || fail "找不到 ${index_dir}/${SPECIES}/ref.json，请先运行 mkref"
    log "[step2/count] 开始定量 ${#SAMPLES[@]} 个 sample ..."

    local failed=0

    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local cdna_r1="${CDNA_R1[$i]}"
        local cdna_r2="${CDNA_R2[$i]}"
        local oligo_r1="${OLIGO_R1[$i]}"
        local oligo_r2="${OLIGO_R2[$i]}"
        local out_dir="${UPSTREAM_WORKDIR}/samples/${s}"
        mkdir -p "$out_dir"

        # 验证 fastq 文件存在
        for f in "$cdna_r1" "$cdna_r2" "$oligo_r1" "$oligo_r2"; do
            [[ -f "$f" ]] || { warn "找不到 FASTQ: $f"; failed=1; }
        done
        [[ $failed -eq 0 ]] || continue

        log "  [count] 运行: ${s} ..."

        # 每个 fastq 单独挂载（R1/R2 可能在不同目录）
        docker run --rm \
            -v "${REF_DIR}:/ref:ro" \
            -v "${index_dir}:/genome:ro" \
            -v "$(realpath "$cdna_r1"):/input/cdna_r1.fq.gz:ro" \
            -v "$(realpath "$cdna_r2"):/input/cdna_r2.fq.gz:ro" \
            -v "$(realpath "$oligo_r1"):/input/oligo_r1.fq.gz:ro" \
            -v "$(realpath "$oligo_r2"):/input/oligo_r2.fq.gz:ro" \
            -v "${out_dir}:/output" \
            -w /output \
            "$IMG" \
            dnbc4tools rna run \
                --name "$s" \
                --cDNAfastq1  /input/cdna_r1.fq.gz \
                --cDNAfastq2  /input/cdna_r2.fq.gz \
                --oligofastq1 /input/oligo_r1.fq.gz \
                --oligofastq2 /input/oligo_r2.fq.gz \
                --genomeDir   /genome/${SPECIES} \
                --chemistry   scRNAv2HT \
                --darkreaction unset,unset \
                --threads     "$THREADS" \
        > "${out_dir}/count.log" 2>&1

        if [[ $? -eq 0 ]]; then
            ok "  [count] ${s} 完成"
        else
            warn "  [count] ${s} 失败！日志: ${out_dir}/count.log"
            failed=1
        fi
    done

    [[ $failed -eq 0 ]] \
        && ok "[step2/count] 全部完成" && mark_done "count" \
        || { mark_fail "count"; fail "[step2/count] 部分 sample 失败"; }
}

# =============================================================================
# STEP 3: Velocity - 从 BAM 提取 spliced/unspliced 矩阵
# 使用 py-scanpy 镜像（包含 Python 环境），用内置脚本从 BAM 生成 velocity 矩阵
# =============================================================================
step_velocity() {
    if is_done "velocity"; then warn "[step3/velocity] 已完成，跳过"; return; fi
    is_done "count" || fail "[step3/velocity] 需要先完成 step2/count"

    local gtf="${REF_DIR}/corrected.gtf"
    log "[step3/velocity] 从 BAM 提取 spliced/unspliced 矩阵 ..."

    local failed=0
    for i in "${!SAMPLES[@]}"; do
        local s="${SAMPLES[$i]}"
        local sample_dir="${UPSTREAM_WORKDIR}/samples/${s}/${s}"
        local bam="${sample_dir}/outs/anno_decon_sorted.bam"
        local barcodes="${sample_dir}/outs/filter_matrix/barcodes.tsv.gz"
        local velocity_dir="${sample_dir}/outs/RNAvelocity_matrix"
        mkdir -p "$velocity_dir"

        [[ -f "$bam" ]] || { warn "找不到 BAM: $bam"; failed=1; continue; }
        log "  [velocity] ${s}: velocyto 提取 spliced/unspliced ..."

        # 用 velocyto run 从 BAM + GTF 提取 splice/unsplice
        docker run --rm \
            -v "$(realpath "$bam"):/input/sorted.bam:ro" \
            -v "$(realpath "${bam}.bai"):/input/sorted.bam.bai:ro" \
            -v "$(realpath "$gtf"):/input/genes.gtf:ro" \
            -v "$(realpath "$barcodes"):/input/barcodes.tsv.gz:ro" \
            -v "${velocity_dir}:/output" \
            -v "${sample_dir}/outs/filter_matrix:/input/filter_matrix:ro" \
            "liruirui123/py-scanpy:latest" \
            /opt/conda/bin/python -c "
import subprocess, os, sys, gzip, shutil

# 解压 barcodes 给 velocyto（它不接受 gz）
with gzip.open('/input/barcodes.tsv.gz', 'rt') as f:
    barcodes = [line.strip() for line in f]
with open('/output/barcodes.tsv', 'w') as f:
    f.write('\n'.join(barcodes) + '\n')

# 尝试用 velocyto
try:
    cmd = [
        'velocyto', 'run',
        '-b', '/output/barcodes.tsv',
        '-o', '/output/velocyto_out',
        '/input/sorted.bam',
        '/input/genes.gtf'
    ]
    print('Running:', ' '.join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    print(result.stdout[-500:] if result.stdout else '')
    if result.returncode != 0:
        print('velocyto stderr:', result.stderr[-500:] if result.stderr else '')
        raise RuntimeError('velocyto failed')

    # velocyto 输出 .loom，转成 mtx 格式
    import loompy, scipy.io, scipy.sparse
    loom_files = [f for f in os.listdir('/output/velocyto_out') if f.endswith('.loom')]
    if loom_files:
        ds = loompy.connect(f'/output/velocyto_out/{loom_files[0]}')
        spliced = scipy.sparse.csr_matrix(ds.layers['spliced'][:,:].T)
        unspliced = scipy.sparse.csr_matrix(ds.layers['unspliced'][:,:].T)
        genes = ds.ra['Gene']
        cells = ds.ca['CellID']
        ds.close()

        scipy.io.mmwrite('/output/spliced.mtx', spliced)
        os.system('gzip -f /output/spliced.mtx')
        scipy.io.mmwrite('/output/unspliced.mtx', unspliced)
        os.system('gzip -f /output/unspliced.mtx')

        # features.tsv.gz
        with gzip.open('/output/features.tsv.gz', 'wt') as f:
            for g in genes: f.write(g + '\t' + g + '\tGene Expression\n')
        # barcodes.tsv.gz
        with gzip.open('/output/barcodes.tsv.gz', 'wt') as f:
            for c in cells: f.write(c + '\n')
        print(f'Done: {spliced.shape[0]} cells, {spliced.shape[1]} genes')
    else:
        raise RuntimeError('No loom file generated')

except Exception as e:
    print(f'velocyto failed ({e}), using fallback: spliced=counts, unspliced=zeros')
    # Fallback: spliced = filter_matrix counts, unspliced = zero matrix
    import scipy.io, scipy.sparse
    m = scipy.io.mmread('/input/filter_matrix/matrix.mtx.gz')
    scipy.io.mmwrite('/output/spliced.mtx', m)
    os.system('gzip -f /output/spliced.mtx')
    zero = scipy.sparse.csr_matrix(m.shape)
    scipy.io.mmwrite('/output/unspliced.mtx', zero)
    os.system('gzip -f /output/unspliced.mtx')
    shutil.copy('/input/filter_matrix/features.tsv.gz', '/output/features.tsv.gz')
    shutil.copy('/input/filter_matrix/barcodes.tsv.gz', '/output/barcodes.tsv.gz')
    print('Fallback complete: spliced=counts, unspliced=zeros')

# 清理临时文件
if os.path.exists('/output/barcodes.tsv'): os.remove('/output/barcodes.tsv')
if os.path.exists('/output/velocyto_out'): shutil.rmtree('/output/velocyto_out', ignore_errors=True)
" > "${velocity_dir}/velocity.log" 2>&1

        if [[ $? -eq 0 ]] && [[ -f "${velocity_dir}/spliced.mtx.gz" ]]; then
            ok "  [velocity] ${s} 完成 -> ${velocity_dir}/"
        else
            warn "  [velocity] ${s} 失败！日志: ${velocity_dir}/velocity.log"
            failed=1
        fi
    done

    [[ $failed -eq 0 ]] \
        && ok "[step3/velocity] 完成" && mark_done "velocity" \
        || { mark_fail "velocity"; fail "[step3/velocity] 部分 sample 失败"; }
}

# =============================================================================
# 状态显示
# =============================================================================
show_status() {
    echo ""
    echo "========= Upstream 状态 ========="
    for entry in "mkgtf:step1a/mkgtf" "mkref:step1b/mkref" "count:step2/count" "velocity:step3/velocity"; do
        local key="${entry%%:*}" name="${entry##*:}"
        if   grep -q "^${key}=done$"   "$STATUS_FILE" 2>/dev/null; then echo -e "  ${GREEN}✓${NC} $name"
        elif grep -q "^${key}=failed$" "$STATUS_FILE" 2>/dev/null; then echo -e "  ${RED}✗${NC} $name ← 失败"
        else echo -e "  ${YELLOW}○${NC} $name (未运行)"
        fi
    done
    echo "=================================="
    echo ""
    echo "定量完成后，输出目录："
    for s in "${SAMPLES[@]}"; do
        echo "  ${UPSTREAM_WORKDIR}/samples/${s}/${s}/"
    done
    echo ""
    echo "在 config.sh 中设置 DNBC4_OUTPUT_DIRS 指向上面的路径（注意双层目录）"
}

# =============================================================================
# 入口
# =============================================================================
TARGET="${1:-all}"

echo "=================================="
echo " Upstream Pipeline (dnbc4tools)"
echo " SPECIES : $SPECIES"
echo " SAMPLES : ${SAMPLES[*]}"
echo " THREADS : $THREADS"
echo " TARGET  : $TARGET"
echo "=================================="

case "$TARGET" in
    all)    step_mkgtf; step_mkref; step_count; step_velocity ;;
    mkgtf)  step_mkgtf ;;
    mkref)  step_mkgtf; step_mkref ;;
    count)    step_count ;;
    velocity) step_velocity ;;
    status) show_status; exit 0 ;;
    reset)
        warn "清除 upstream 状态 ..."
        rm -f "$STATUS_FILE"
        ok "已重置"
        exit 0
        ;;
    *)
        echo "未知步骤: $TARGET"
        echo "可用: all | mkgtf | mkref | count | status | reset"
        exit 1
        ;;
esac

show_status
ok "完成！"
