FROM continuumio/miniconda3:23.10.0-1

LABEL maintainer="dataget-pipeline" \
      description="SoupX ambient RNA removal (R environment)"

# System dependencies for R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        libhdf5-dev \
        libgit2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R + core packages via conda (much faster than source)
RUN conda install -y -c conda-forge \
        r-base=4.3.1 \
        r-matrix \
        r-ggplot2 \
        r-optparse \
        r-r.utils \
        r-remotes \
    && conda clean -afy

# Install SoupX from CRAN (not on conda-forge)
RUN /opt/conda/bin/Rscript -e \
    "install.packages('SoupX', repos='https://cloud.r-project.org', Ncpus=4)"

# Copy analysis script into image
RUN mkdir -p /Scripts/dataget_scRNAseq
COPY r-soupx/run_SoupX.R /Scripts/dataget_scRNAseq/run_SoupX.R
COPY r-soupx/run_SoupX.R /opt/conda/bin/run_SoupX.R

# Smoke test
RUN /opt/conda/bin/Rscript -e "library(SoupX); library(optparse); cat('SoupX OK\n')"

# Pipeline scripts
COPY scripts/ /scripts/

WORKDIR /data
