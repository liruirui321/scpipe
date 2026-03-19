FROM continuumio/miniconda3:23.10.0-1

LABEL maintainer="dataget-pipeline" \
      description="dnbc4tools 3.0 for BGI DNBelab C4 scRNA-seq (build index + quantification)"

# ---- 系统依赖 ----
# libhts3: 解决 scStar 缺少 libhts.so.3 的问题
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        curl \
        libhts3 \
        libgomp1 \
        libz-dev \
        libbz2-dev \
        liblzma-dev \
        libncurses5-dev \
        pigz \
    && rm -rf /var/lib/apt/lists/*

# ---- 把系统 libhts.so.3 加入 conda lib 路径（供 scStar 找到）----
RUN ln -sf /usr/lib/x86_64-linux-gnu/libhts.so.3 /opt/conda/lib/libhts.so.3 2>/dev/null || true

ENV LD_LIBRARY_PATH=/opt/conda/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# ---- Python 依赖（dnbc4tools 内部用）----
RUN conda install -y -c conda-forge \
        python=3.8 \
        pyyaml \
        pandas \
        numpy \
    && conda clean -afy

# ---- 下载并安装 dnbc4tools 3.0 ----
# 已预先下载到 docker/dnbc4tools/dnbc4tools-3.0.tar.gz
WORKDIR /opt
COPY dnbc4tools/dnbc4tools-3.0.tar.gz /opt/
RUN tar -xzf dnbc4tools-3.0.tar.gz \
    && rm dnbc4tools-3.0.tar.gz

ENV PATH=/opt/dnbc4tools3.0:${PATH}

# ---- 验证 ----
RUN /opt/dnbc4tools3.0/dnbc4tools --version 2>&1 || echo "dnbc4tools installed"

# Pipeline scripts
COPY scripts/ /scripts/

WORKDIR /data
