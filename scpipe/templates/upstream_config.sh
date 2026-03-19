# =============================================================================
# upstream_config.sh - 本地测试配置（模拟 DNBelab C4 数据）
# =============================================================================

# ---- 输出目录 ----
UPSTREAM_WORKDIR="$(pwd)/upstream_output"

# ---- 物种名 ----
SPECIES="test_arabidopsis"

# ---- 线程数 ----
THREADS=4

# ---- 参考基因组文件 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FASTA_FILE="${SCRIPT_DIR}/test_data/genome.fa"
GTF_FILE="${SCRIPT_DIR}/test_data/genes.gtf"

# ---- Samples ----
SAMPLES=(
    "test_sample1"
)

# ---- cDNA fastq ----
CDNA_R1=(
    "${SCRIPT_DIR}/test_data/test_cDNA_R1.fastq.gz"
)
CDNA_R2=(
    "${SCRIPT_DIR}/test_data/test_cDNA_R2.fastq.gz"
)

# ---- oligo fastq ----
OLIGO_R1=(
    "${SCRIPT_DIR}/test_data/test_oligo_R1.fastq.gz"
)
OLIGO_R2=(
    "${SCRIPT_DIR}/test_data/test_oligo_R2.fastq.gz"
)
