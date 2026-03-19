#!/usr/bin/env python3
"""
deal_layers_ydgenomics.py
将 h5ad 的 layers 转换为 SeuratDisk/Seurat 兼容格式，再交给 R 脚本做格式转换。
"""
import argparse, os, scipy.sparse as sp, numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("--input_path", required=True, help="h5ad or rds file path")
parser.add_argument("--sctype",     required=True, choices=["h5ad", "rds"],
                    help="File type: h5ad or rds")
args = parser.parse_args()

if args.sctype == "h5ad":
    import anndata as ad
    print(f"[deal_layers] Reading {args.input_path}")
    adata = ad.read_h5ad(args.input_path)

    # 1. X → CSC sparse (SeuratDisk 要求)
    if not sp.issparse(adata.X):
        adata.X = sp.csc_matrix(adata.X)
    else:
        adata.X = adata.X.tocsc()

    # 2. layers → CSC
    for key in list(adata.layers.keys()):
        if sp.issparse(adata.layers[key]):
            adata.layers[key] = adata.layers[key].tocsc()
        else:
            adata.layers[key] = sp.csc_matrix(adata.layers[key])

    # 3. var 需要有 gene_ids 列（Seurat 用 var_names 作 feature ID）
    if "gene_ids" not in adata.var.columns:
        adata.var["gene_ids"] = adata.var.index.astype(str)
    if "feature_types" not in adata.var.columns:
        adata.var["feature_types"] = "Gene Expression"

    # 4. obs 列类型修正（bool/category → str，避免 hdf5 写入报错）
    for col in adata.obs.columns:
        if adata.obs[col].dtype == bool:
            adata.obs[col] = adata.obs[col].astype(str)

    adata.write_h5ad(args.input_path, compression="gzip")
    print(f"[deal_layers] Done: {args.input_path}")

elif args.sctype == "rds":
    # rds 由 R 读取，Python 端无需处理，直接跳过
    print(f"[deal_layers] sctype=rds, skipping Python processing.")
