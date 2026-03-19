#!/usr/bin/env python3
"""
generate_test_data.py - 生成 DNBelab C4 scRNA-seq 模拟测试数据

生成内容:
  1. 小型拟南芥参考基因组 (Chr1 前 100kb) + 对应 GTF
  2. cDNA FASTQ (R1 + R2)
  3. oligo FASTQ (R1 + R2)

Chemistry: scRNAv2HT (DNBelab C Series V2.0)
  cDNA R1: 6bp linker + 10bp CB1 + 6bp linker + 10bp CB2 + 5bp linker + 10bp UMI = 47bp+
  cDNA R2: RNA insert (100bp)
  oligo R1: same as cDNA R1 (barcode region)
  oligo R2: 10bp index1 + 6bp linker + 10bp index2 + 6bp linker + 10bp index3

用法:
  python3 generate_test_data.py --outdir ./test_data --n_cells 100 --n_reads 10000
"""

import argparse
import gzip
import os
import random
import string

random.seed(42)

# === C4 Barcode whitelist (从真实白名单文件加载) ===
BARCODES = []
_whitelist_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_data", "whitelist.txt")
if os.path.exists(_whitelist_path):
    with open(_whitelist_path) as _f:
        BARCODES = [line.strip() for line in _f if line.strip()]
if not BARCODES:
    # fallback: 前 50 个硬编码 barcode
    BARCODES = [
        "TAACAGCCAA", "CTAAGAGTCC", "TTACTGCCTT", "CGCTGAATTC", "TGACGTCCTT",
        "AAGGTCCTAG", "GCTACGGACA", "TTCGCCATGA", "CAGACCTTGT", "GATCATGCAG",
    ]

# === Linker sequences (固定序列，C4 实际使用的) ===
LINKER1 = "GTCGGA"   # 6bp before CB1
LINKER2 = "ACGTCC"   # 6bp between CB1 and CB2
LINKER3 = "TTGCG"    # 5bp between CB2 and UMI

# === Helper functions ===
def random_seq(length):
    return ''.join(random.choices('ACGT', k=length))

def random_qual(length, min_q=30, max_q=40):
    """Generate quality string (Phred+33)"""
    return ''.join(chr(random.randint(min_q + 33, max_q + 33)) for _ in range(length))

def make_gene_entry(gene_id, gene_name, chrom, start, end, strand):
    """Create a simple gene GTF entry with one transcript and one exon"""
    attrs_gene = f'gene_id "{gene_id}"; gene_name "{gene_name}"; gene_biotype "protein_coding";'
    attrs_tx = f'gene_id "{gene_id}"; transcript_id "{gene_id}.1"; gene_name "{gene_name}"; gene_biotype "protein_coding";'

    lines = []
    lines.append(f"{chrom}\tensembl\tgene\t{start}\t{end}\t.\t{strand}\t.\t{attrs_gene}")
    lines.append(f"{chrom}\tensembl\ttranscript\t{start}\t{end}\t.\t{strand}\t.\t{attrs_tx}")
    lines.append(f"{chrom}\tensembl\texon\t{start}\t{end}\t.\t{strand}\t.\t{attrs_tx}")
    return lines


def generate_genome(outdir, genome_size=100000):
    """Generate a small fake Arabidopsis Chr1 genome + GTF"""
    fasta_path = os.path.join(outdir, "genome.fa")
    gtf_path = os.path.join(outdir, "genes.gtf")

    # Generate random genome sequence
    seq = random_seq(genome_size)

    with open(fasta_path, 'w') as f:
        f.write(">Chr1\n")
        for i in range(0, len(seq), 80):
            f.write(seq[i:i+80] + "\n")

    # Generate fake genes every ~2kb
    gtf_lines = []
    gene_names = []
    gene_idx = 0
    pos = 1000
    while pos + 1000 < genome_size:
        gene_len = random.randint(500, 1500)
        gene_id = f"AT1G{gene_idx:05d}"
        gene_name = f"GENE{gene_idx}"
        strand = random.choice(['+', '-'])
        gtf_lines.extend(make_gene_entry(gene_id, gene_name, "Chr1", pos, pos + gene_len, strand))
        gene_names.append((gene_id, gene_name, pos, pos + gene_len))
        gene_idx += 1
        pos += gene_len + random.randint(500, 1500)

    with open(gtf_path, 'w') as f:
        for line in gtf_lines:
            f.write(line + "\n")

    print(f"  Genome: {fasta_path} ({genome_size} bp)")
    print(f"  GTF: {gtf_path} ({gene_idx} genes)")
    return fasta_path, gtf_path, seq, gene_names


def generate_fastq(outdir, genome_seq, gene_names, n_cells=100, reads_per_cell=100):
    """Generate C4 scRNAv2HT format cDNA + oligo FASTQ files"""

    n_cells = min(n_cells, len(BARCODES))
    total_reads = n_cells * reads_per_cell

    cdna_r1_path = os.path.join(outdir, "test_cDNA_R1.fastq.gz")
    cdna_r2_path = os.path.join(outdir, "test_cDNA_R2.fastq.gz")
    oligo_r1_path = os.path.join(outdir, "test_oligo_R1.fastq.gz")
    oligo_r2_path = os.path.join(outdir, "test_oligo_R2.fastq.gz")

    # Assign barcodes to cells
    cell_barcodes = []
    for i in range(n_cells):
        cb1 = BARCODES[i % len(BARCODES)]
        cb2 = BARCODES[(i + 7) % len(BARCODES)]  # offset for CB2
        cell_barcodes.append((cb1, cb2))

    # Oligo index: use whitelist barcodes for index too (dnbc4tools checks them)
    oligo_indices = []
    for i in range(n_cells):
        idx1 = BARCODES[(i + 20) % len(BARCODES)]
        idx2 = BARCODES[(i + 40) % len(BARCODES)]
        idx3 = BARCODES[(i + 60) % len(BARCODES)]
        oligo_indices.append((idx1, idx2, idx3))

    read_count = 0

    with gzip.open(cdna_r1_path, 'wt') as cr1, \
         gzip.open(cdna_r2_path, 'wt') as cr2, \
         gzip.open(oligo_r1_path, 'wt') as or1, \
         gzip.open(oligo_r2_path, 'wt') as or2:

        for cell_idx in range(n_cells):
            cb1, cb2 = cell_barcodes[cell_idx]
            idx1, idx2, idx3 = oligo_indices[cell_idx]

            for _ in range(reads_per_cell):
                read_count += 1
                read_id = f"@READ{read_count:08d}"
                umi = random_seq(10)

                # ---- cDNA R1: linker1(6) + CB1(10) + linker2(6) + CB2(10) + linker3(5) + UMI(10) = 47bp ----
                cdna_r1_seq = LINKER1 + cb1 + LINKER2 + cb2 + LINKER3 + umi
                cdna_r1_qual = random_qual(len(cdna_r1_seq))

                # ---- cDNA R2: RNA insert (100bp from a random gene region) ----
                gene = random.choice(gene_names)
                gene_start, gene_end = gene[2], gene[3]
                read_start = random.randint(gene_start, max(gene_start, gene_end - 100))
                rna_seq = genome_seq[read_start:read_start + 100]
                if len(rna_seq) < 100:
                    rna_seq += random_seq(100 - len(rna_seq))
                cdna_r2_qual = random_qual(100)

                # Write cDNA R1
                cr1.write(f"{read_id}/1\n{cdna_r1_seq}\n+\n{cdna_r1_qual}\n")
                # Write cDNA R2
                cr2.write(f"{read_id}/2\n{rna_seq}\n+\n{cdna_r2_qual}\n")

                # ---- oligo R1: same barcode structure as cDNA R1 ----
                oligo_r1_seq = cdna_r1_seq
                or1.write(f"{read_id}/1\n{oligo_r1_seq}\n+\n{cdna_r1_qual}\n")

                # ---- oligo R2: scRNAv2HT format ----
                # pos 1-10: index1 (from whitelist), 11-16: linker, 17-26: index2, 27-32: linker, 33-42: index3
                oligo_r2_seq = idx1 + "AGTCAA" + idx2 + "AGTCAA" + idx3
                oligo_r2_qual = random_qual(len(oligo_r2_seq))
                or2.write(f"{read_id}/2\n{oligo_r2_seq}\n+\n{oligo_r2_qual}\n")

    print(f"  cDNA R1:  {cdna_r1_path}")
    print(f"  cDNA R2:  {cdna_r2_path}")
    print(f"  oligo R1: {oligo_r1_path}")
    print(f"  oligo R2: {oligo_r2_path}")
    print(f"  Total: {total_reads} reads from {n_cells} cells")
    return cdna_r1_path, cdna_r2_path, oligo_r1_path, oligo_r2_path


def main():
    parser = argparse.ArgumentParser(description="Generate DNBelab C4 test FASTQ data")
    parser.add_argument("--outdir", default="./test_data", help="Output directory")
    parser.add_argument("--n_cells", type=int, default=50, help="Number of simulated cells")
    parser.add_argument("--reads_per_cell", type=int, default=200, help="Reads per cell")
    parser.add_argument("--genome_size", type=int, default=100000, help="Genome size (bp)")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    print("=" * 50)
    print(" Generating DNBelab C4 test data")
    print(f" Output: {args.outdir}")
    print(f" Cells: {args.n_cells}, Reads/cell: {args.reads_per_cell}")
    print("=" * 50)

    print("\n[1/2] Generating genome + GTF ...")
    fasta, gtf, genome_seq, gene_names = generate_genome(args.outdir, args.genome_size)

    print("\n[2/2] Generating FASTQ files ...")
    generate_fastq(args.outdir, genome_seq, gene_names, args.n_cells, args.reads_per_cell)

    print("\n" + "=" * 50)
    print(" Done! Test data generated.")
    print(f"\n 在 upstream_config.sh 中配置:")
    print(f'   FASTA_FILE="{os.path.abspath(fasta)}"')
    print(f'   GTF_FILE="{os.path.abspath(gtf)}"')
    print(f'   CDNA_R1=("{os.path.abspath(args.outdir)}/test_cDNA_R1.fastq.gz")')
    print(f'   CDNA_R2=("{os.path.abspath(args.outdir)}/test_cDNA_R2.fastq.gz")')
    print(f'   OLIGO_R1=("{os.path.abspath(args.outdir)}/test_oligo_R1.fastq.gz")')
    print(f'   OLIGO_R2=("{os.path.abspath(args.outdir)}/test_oligo_R2.fastq.gz")')
    print("=" * 50)


if __name__ == "__main__":
    main()
