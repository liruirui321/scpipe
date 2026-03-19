#!/usr/bin/env Rscript
# convert_rdsAh5ad2.R - h5ad <-> rds 格式互转
# 用法:
#   Rscript convert_rdsAh5ad2.R --input_file foo.h5ad --layers all
#   Rscript convert_rdsAh5ad2.R --input_file foo.rds  --layers all

suppressPackageStartupMessages({
  library(optparse)
  library(Seurat)
  library(SeuratDisk)
})

opt <- parse_args(OptionParser(option_list = list(
  make_option("--input_file", type = "character", help = "Input .h5ad or .rds file"),
  make_option("--layers",     type = "character", default = "all",
              help = "Layers to include (all or comma-separated names)")
)))

input  <- opt$input_file
ext    <- tolower(tools::file_ext(input))
base   <- tools::file_path_sans_ext(basename(input))

cat("[convert] input:", input, "\n")
cat("[convert] extension:", ext, "\n")

if (ext == "h5ad") {
  # ---- h5ad → rds ----
  h5seurat <- paste0(base, ".h5seurat")

  cat("[convert] Converting h5ad → h5seurat ...\n")
  Convert(input, dest = "h5seurat", overwrite = TRUE, verbose = FALSE)

  cat("[convert] Loading h5seurat → Seurat object ...\n")
  # 加载所有 layers
  assay_names <- tryCatch(
    rhdf5::h5ls(h5seurat) |> subset(group == "/assays/RNA") |> _$name,
    error = function(e) "counts"
  )
  seurat_obj <- LoadH5Seurat(h5seurat, verbose = FALSE)

  out_rds <- paste0(base, ".rds")
  saveRDS(seurat_obj, out_rds)
  cat("[convert] Saved:", out_rds, "\n")

  # 清理中间文件
  if (file.exists(h5seurat)) file.remove(h5seurat)

} else if (ext == "rds") {
  # ---- rds → h5ad ----
  cat("[convert] Loading Seurat object ...\n")
  seurat_obj <- readRDS(input)

  h5seurat <- paste0(base, ".h5seurat")
  cat("[convert] Saving h5seurat ...\n")
  SaveH5Seurat(seurat_obj, filename = h5seurat, overwrite = TRUE, verbose = FALSE)

  cat("[convert] Converting h5seurat → h5ad ...\n")
  Convert(h5seurat, dest = "h5ad", overwrite = TRUE, verbose = FALSE)

  out_h5ad <- paste0(base, ".h5ad")
  cat("[convert] Saved:", out_h5ad, "\n")

  if (file.exists(h5seurat)) file.remove(h5seurat)

} else {
  stop(paste("[convert] Unsupported extension:", ext, "- expected h5ad or rds"))
}

cat("[convert] Done.\n")
