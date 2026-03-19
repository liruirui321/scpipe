FROM continuumio/miniconda3:23.10.0-1

LABEL maintainer="dataget-pipeline" \
      description="Scrublet doublet detection + scanpy QC (Python environment)"

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libhdf5-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages via conda + pip
# Pin Python 3.10 for stability with leidenalg
RUN conda install -y -c conda-forge \
        python=3.10 \
        numpy=1.26 \
        pandas \
        scipy \
        matplotlib \
        seaborn \
        h5py \
        hdf5 \
        leidenalg \
        python-igraph \
    && conda clean -afy

# velocyto 的 setup.py 在编译时需要 numpy 和 Cython
RUN pip install --no-cache-dir numpy Cython pysam==0.22.1

RUN pip install --no-cache-dir \
        anndata==0.10.7 \
        scanpy==1.10.1 \
        scrublet==0.2.3

# velocyto 必须关闭 build isolation（其 setup.py 直接 import numpy）
RUN pip install --no-cache-dir --no-build-isolation velocyto==0.17.17

# Smoke test
RUN /opt/conda/bin/python -c "\
import scanpy; import scrublet; import leidenalg; import anndata; \
print('scanpy', scanpy.__version__); \
print('anndata', anndata.__version__); \
print('scrublet OK')"

# Pipeline scripts
COPY scripts/ /scripts/

WORKDIR /data
