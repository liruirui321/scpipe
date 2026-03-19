# scpipe - BGI DNBelab C4 单细胞 RNA-seq 全流程分析工具

一站式 Docker 化 pipeline，覆盖从原始 FASTQ 到 QC 后 h5ad 的完整流程。

## 流程概览

```
FASTQ (cDNA + oligo)
    │
    ├── Step 1: mkgtf      校正 GTF 注释文件
    ├── Step 2: mkref      构建基因组索引
    ├── Step 3: count      单细胞定量 (dnbc4tools)
    ├── Step 4: velocity   提取 spliced/unspliced 矩阵
    │
    ├── Step 5: prep       整理目录结构
    ├── Step 6: soupx      去除环境 RNA (SoupX)
    ├── Step 7: scrublet   QC + 双细胞检测 (Scrublet)
    ├── Step 8: sscrublet  SoupX 校正后 QC
    └── Step 9: scdatacg   h5ad ↔ rds 格式转换
```

## 快速开始

### 1. 安装

```bash
# 环境要求: Linux/macOS, Docker, Python >= 3.8
git clone https://github.com/liruirui123/scpipe.git
cd scpipe
pip install .
```

### 2. 拉取 Docker 镜像

```bash
scpipe pull
```

镜像列表:

| 镜像 | 大小 | 功能 |
|------|------|------|
| `liruirui123/dnbc4tools` | ~3.3 GB | FASTQ 定量 (dnbc4tools 3.0) |
| `liruirui123/py-scanpy` | ~2.7 GB | QC + Scrublet + velocyto |
| `liruirui123/r-soupx` | ~2.2 GB | SoupX 去环境 RNA |
| `liruirui123/r-seurat` | ~3.0 GB | Seurat h5ad ↔ rds |

### 3. 初始化配置

```bash
scpipe init
# 生成 upstream_config.sh 和 config.sh
# 编辑配置文件，填入你的数据路径
```

### 4. 运行分析

```bash
# 上游分析 (FASTQ → 矩阵)
scpipe upstream mkgtf       # 校正 GTF
scpipe upstream mkref       # 建索引 (~30 min)
scpipe upstream count       # 定量 (~数小时)
scpipe upstream velocity    # 提取 velocity 矩阵

# 下游分析 (矩阵 → QC h5ad)
scpipe downstream all       # 一键全跑
# 或分步:
scpipe downstream prep
scpipe downstream soupx
scpipe downstream scrublet

# 查看进度
scpipe status
```

## 测试

```bash
# 生成模拟 DNBelab C4 测试数据并验证 pipeline
scpipe test
```

## 配置说明

### upstream_config.sh

```bash
SPECIES="Arabidopsis_thaliana"   # 物种名
THREADS=16                       # CPU 线程数
FASTA_FILE="/path/to/genome.fa"  # 参考基因组
GTF_FILE="/path/to/genes.gtf"    # 基因注释

SAMPLES=("sample1" "sample2")    # 样本名称
CDNA_R1=("/path/to/cDNA_R1.fq.gz" ...)
CDNA_R2=("/path/to/cDNA_R2.fq.gz" ...)
OLIGO_R1=("/path/to/oligo_R1.fq.gz" ...)
OLIGO_R2=("/path/to/oligo_R2.fq.gz" ...)
```

### config.sh

```bash
SPECIES="Arabidopsis_thaliana"
DNBC4_OUTPUT_DIRS=("/path/to/upstream_output/samples/sample1/sample1" ...)
MINGENES=100           # 每个细胞最少基因数
MINCELLS=3             # 每个基因最少细胞数
MITO_THRESHOLD=0.05    # 线粒体基因过滤阈值
```

## 输出文件

```
upstream_output/
├── genome_index/                    基因组索引
└── samples/<sample>/
    └── <sample>/outs/
        ├── raw_matrix/              原始计数矩阵
        ├── filter_matrix/           过滤后计数矩阵
        ├── RNAvelocity_matrix/      Velocity 矩阵
        ├── filter_feature.h5ad      h5ad 格式
        └── *_scRNA_report.html      QC 报告

dataget_output/
├── soupx/<sample>/                  SoupX 校正矩阵
├── scrublet_raw/                    Scrublet QC 结果
│   └── <species>_dataget/
│       ├── <species>.h5ad           主要结果
│       └── marker_csv/              Marker 基因
├── scrublet_soupx/                  SoupX 校正后的 QC
└── scdatacg/                        RDS 格式输出
```

## 适配平台

- **试剂盒**: DNBelab C 系列高通量单细胞 RNA 文库制备试剂盒 V2.0
- **Chemistry**: scRNAv2HT
- **测序平台**: DNBSEQ

## 断点续跑

Pipeline 自动记录每步完成状态。如果某步失败：

```bash
# 查看哪步失败
scpipe status

# 修好问题后，只重跑失败的步骤
scpipe upstream count

# 需要全部重来
scpipe upstream reset
scpipe downstream reset
```

## 不使用 CLI（纯 Shell）

也可以直接用 Shell 脚本：

```bash
# 从镜像提取脚本
docker run --rm liruirui123/py-scanpy:latest tar -cf - -C /scripts . | tar -xf -

# 编辑配置
vim upstream_config.sh
vim config.sh

# 运行
bash run_upstream.sh all
bash run_pipeline.sh all
```

## Docker 镜像构建（开发者）

```bash
cd docker
bash build_push.sh <your-dockerhub-username> all
```

## 无 Docker 模式

如果服务器没有 Docker，可以用 conda 安装所有依赖：

```bash
# 安装依赖（自动创建 conda 环境 + 下载 dnbc4tools）
scpipe install-deps

# 激活环境
conda activate scpipe
source .scpipe_local/env.sh

# 使用 --local 参数运行（不调用 Docker）
scpipe upstream all --local
scpipe downstream all --local
```

或手动安装：

```bash
# 创建 conda 环境
conda env create -f environment.yml
conda activate scpipe

# 下载 dnbc4tools
wget -O dnbc4tools-3.0.tar.gz "ftp://ftp2.cngb.org/pub/CNSA/data7/CNP0008672/Single_Cell/CSE0000574/dnbc4tools-3.0.tar.gz"
tar -xzf dnbc4tools-3.0.tar.gz
export PATH=$(pwd)/dnbc4tools3.0:$PATH
export LD_LIBRARY_PATH=$(pwd)/dnbc4tools3.0/external/conda/lib:$LD_LIBRARY_PATH

# 运行
export SCPIPE_MODE=local
bash scripts/run_upstream.sh all
```

## Singularity/Apptainer（HPC 集群）

如果集群支持 Singularity 但不支持 Docker：

```bash
# 转换 Docker 镜像为 Singularity
singularity pull docker://liruirui123/dnbc4tools:latest
singularity pull docker://liruirui123/py-scanpy:latest

# 用 singularity exec 替代 docker run
singularity exec dnbc4tools_latest.sif dnbc4tools rna mkref ...
```

## License

MIT
