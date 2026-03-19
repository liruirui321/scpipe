#!/usr/bin/env Rscript
# run_SoupX.R - SoupX ambient RNA removal
# 输出: ${sample}_soupx_rho.txt, ${sample}_rho.pdf, ${sample}/ (10x mtx dir)

suppressPackageStartupMessages({
  library(optparse)
  library(SoupX)
  library(Matrix)
  library(ggplot2)
})

opt <- parse_args(OptionParser(option_list = list(
  make_option("--raw_path",    type="character", help="Raw matrix dir (CellRanger raw_feature_bc_matrix)"),
  make_option("--filter_path", type="character", help="Filtered matrix dir"),
  make_option("--sample_name", type="character", help="Sample name (used as output prefix)"),
  make_option("--minCG",       type="integer",   default=100,  help="Min cells per gene [default: %default]"),
  make_option("--tfidfMin",    type="numeric",   default=1.0,  help="TF-IDF min [default: %default]"),
  make_option("--highestrho",  type="numeric",   default=0.2,  help="Max rho cap [default: %default]")
)))

cat("[SoupX] Sample:", opt$sample_name, "\n")
cat("[SoupX] raw_path:", opt$raw_path, "\n")
cat("[SoupX] filter_path:", opt$filter_path, "\n")

# ---- 读取 10x 矩阵的辅助函数（不依赖 Seurat）----
read10xMatrix <- function(dir_path) {
  mtx_file <- file.path(dir_path, "matrix.mtx.gz")
  feat_file <- file.path(dir_path, "features.tsv.gz")
  bc_file <- file.path(dir_path, "barcodes.tsv.gz")

  if (!file.exists(mtx_file)) mtx_file <- file.path(dir_path, "matrix.mtx")
  if (!file.exists(feat_file)) feat_file <- file.path(dir_path, "features.tsv")
  if (!file.exists(bc_file)) bc_file <- file.path(dir_path, "barcodes.tsv")

  mat <- Matrix::readMM(mtx_file)
  features <- read.delim(feat_file, header = FALSE, stringsAsFactors = FALSE)
  barcodes <- read.delim(bc_file, header = FALSE, stringsAsFactors = FALSE)

  rownames(mat) <- make.unique(features$V1)
  colnames(mat) <- barcodes$V1
  return(mat)
}

# ---- Load 10x data ----
toc <- read10xMatrix(opt$filter_path)   # table of counts (filtered)
tod <- read10xMatrix(opt$raw_path)      # table of droplets (raw)

# ---- Create SoupChannel ----
sc <- SoupChannel(tod, toc)

# ---- Estimate contamination ----
rho <- tryCatch({
  sc <- autoEstCont(sc, tfidfMin = opt$tfidfMin, doPlot = FALSE)
  sc$fit$rhoEst
}, error = function(e) {
  cat("[SoupX] autoEstCont failed:", conditionMessage(e), "\n")
  cat("[SoupX] Falling back to rho = 0.05\n")
  sc <<- setContaminationFraction(sc, 0.05)
  0.05
})

# Cap rho at highestrho
if (rho > opt$highestrho) {
  cat(sprintf("[SoupX] rho=%.3f > highestrho=%.3f, capping.\n", rho, opt$highestrho))
  sc <- setContaminationFraction(sc, opt$highestrho)
  rho <- opt$highestrho
}
cat(sprintf("[SoupX] rho = %.4f\n", rho))

# ---- Write rho txt ----
write.table(
  data.frame(sample = opt$sample_name, rho = rho),
  file  = paste0(opt$sample_name, "_soupx_rho.txt"),
  sep   = "\t", quote = FALSE, row.names = FALSE
)

# ---- Write rho plot ----
pdf(paste0(opt$sample_name, "_rho.pdf"))
tryCatch(plotMarkerDistribution(sc), error = function(e) {
  plot.new(); title(paste("rho =", round(rho, 4)))
})
dev.off()

# ---- Apply correction ----
out <- adjustCounts(sc, roundToInt = TRUE)

# ---- Write corrected matrix in 10x gz format ----
out_dir <- opt$sample_name
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

writeMM(out, file.path(out_dir, "matrix.mtx"))
R.utils::gzip(file.path(out_dir, "matrix.mtx"), overwrite = TRUE)

features <- data.frame(
  gene_id     = rownames(out),
  gene_symbol = rownames(out),
  feature_type = "Gene Expression"
)
gz_feat <- gzfile(file.path(out_dir, "features.tsv.gz"), "w")
write.table(features, gz_feat, sep = "\t", quote = FALSE, col.names = FALSE, row.names = FALSE)
close(gz_feat)

gz_bc <- gzfile(file.path(out_dir, "barcodes.tsv.gz"), "w")
writeLines(colnames(out), gz_bc)
close(gz_bc)

cat("[SoupX] Done. Output dir:", out_dir, "\n")
