FROM continuumio/miniconda3:23.10.0-1

LABEL maintainer="dataget-pipeline" \
      description="h5ad <-> rds format conversion (R + Python)"

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libhdf5-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        libgit2-dev \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# ---- Python packages ----
RUN conda install -y -c conda-forge \
        python=3.10 \
        anndata=0.10.7 \
        scipy \
        h5py \
        hdf5 \
    && conda clean -afy

RUN pip install --no-cache-dir anndata==0.10.7

# ---- R + Seurat + SeuratDisk ----
RUN conda install -y -c conda-forge \
        r-base=4.3.1 \
        r-optparse \
        r-remotes \
        r-hdf5r \
        r-matrix \
        r-ggplot2 \
        r-cowplot \
        r-dplyr \
    && conda clean -afy

# Seurat v4 (SeuratDisk 与 v5 兼容性尚不完整)
RUN /opt/conda/bin/Rscript -e \
    "install.packages('Seurat', repos='https://cloud.r-project.org', Ncpus=4)"

# SeuratDisk (h5ad <-> h5seurat <-> rds)
RUN /opt/conda/bin/Rscript -e \
    "remotes::install_github('mojaveazure/seurat-disk', quiet=TRUE)"

# rhdf5 via conda (更可靠，避免 BiocManager 的 CRAN mirror 问题)
RUN conda install -y -c bioconda -c conda-forge \
        bioconductor-rhdf5 \
    && conda clean -afy

# ---- 放置脚本 ----
RUN mkdir -p /script
COPY r-seurat/deal_layers.py      /script/deal_layers_ydgenomics.py
COPY r-seurat/convert_rds_h5ad.R  /script/convert_rdsAh5ad2.R

# /software/conda/Anaconda/bin/ 路径兼容（原 WDL 平台路径）
RUN mkdir -p /software/conda/Anaconda/bin && \
    ln -s /opt/conda/bin/Rscript /software/conda/Anaconda/bin/Rscript

# Smoke test
RUN /opt/conda/bin/Rscript -e "library(Seurat); library(SeuratDisk); cat('SeuratDisk OK\n')"
RUN /opt/conda/bin/python  -c "import anndata; print('anndata', anndata.__version__)"

# Pipeline scripts
COPY scripts/ /scripts/

WORKDIR /data
