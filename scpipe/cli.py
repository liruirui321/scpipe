#!/usr/bin/env python3
"""
scpipe - BGI DNBelab C4 单细胞 RNA-seq 分析 pipeline CLI 工具

用法:
    scpipe init                    生成配置文件模板
    scpipe pull                    拉取所有 Docker 镜像
    scpipe test                    生成测试数据并验证 pipeline
    scpipe upstream [step]         上游分析 (FASTQ → 矩阵)
    scpipe downstream [step]       下游分析 (矩阵 → QC h5ad)
    scpipe status                  查看所有步骤状态
    scpipe clean                   清理输出和状态文件
"""
import argparse
import os
import subprocess
import sys
import shutil

from . import __version__, DOCKER_IMAGES


def get_script_dir():
    """返回 scripts/ 目录路径"""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scripts')


def get_template_dir():
    """返回 templates/ 目录路径"""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates')


def run_shell(script_name, args=None, cwd=None):
    """运行 shell 脚本"""
    script = os.path.join(get_script_dir(), script_name)
    if not os.path.exists(script):
        print(f"Error: 找不到脚本 {script}")
        sys.exit(1)
    bash = shutil.which('bash') or '/bin/bash'
    cmd = [bash, script] + (args or [])
    env = os.environ.copy()
    env['PATH'] = '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:' + env.get('PATH', '')
    result = subprocess.run(cmd, cwd=cwd or os.getcwd(), env=env)
    return result.returncode


def check_docker():
    """检查 Docker 是否可用"""
    docker_cmd = shutil.which('docker') or '/usr/local/bin/docker'
    try:
        result = subprocess.run([docker_cmd, 'info'], capture_output=True, timeout=10)
        if result.returncode != 0:
            print("Error: Docker 未运行。请启动 Docker (OrbStack/Docker Desktop)")
            sys.exit(1)
    except FileNotFoundError:
        print("Error: 未安装 Docker。请先安装 Docker")
        sys.exit(1)


# ========== 子命令实现 ==========

def cmd_init(args):
    """生成配置文件模板到当前目录"""
    template_dir = get_template_dir()
    files = {
        'upstream_config.sh': '上游配置（FASTQ 路径、基因组等）',
        'config.sh':          '下游配置（物种、参数等）',
    }
    for f, desc in files.items():
        src = os.path.join(template_dir, f)
        dst = os.path.join(os.getcwd(), f)
        if os.path.exists(dst) and not args.force:
            print(f"  跳过 {f}（已存在，用 --force 覆盖）")
        else:
            shutil.copy2(src, dst)
            print(f"  生成 {f} - {desc}")
    print("\n请编辑上面的配置文件，然后运行:")
    print("  scpipe pull       # 拉取 Docker 镜像")
    print("  scpipe upstream   # 开始上游分析")


def cmd_pull(args):
    """拉取所有 Docker 镜像"""
    check_docker()
    images = DOCKER_IMAGES
    if args.image:
        images = {k: v for k, v in images.items() if k == args.image}
        if not images:
            print(f"未知镜像: {args.image}")
            print(f"可选: {', '.join(DOCKER_IMAGES.keys())}")
            sys.exit(1)

    for name, tag in images.items():
        print(f"\n拉取 {name}: {tag}")
        ret = subprocess.run(['docker', 'pull', tag])
        if ret.returncode == 0:
            print(f"  ✓ {name} 完成")
        else:
            print(f"  ✗ {name} 失败")
            sys.exit(1)
    print("\n所有镜像已就绪!")


def cmd_test(args):
    """生成测试数据并运行 pipeline 验证"""
    check_docker()
    test_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'generate_test_data.py')
    outdir = os.path.join(os.getcwd(), 'test_data')

    print("生成测试数据 ...")
    ret = subprocess.run([
        sys.executable, test_script,
        '--outdir', outdir,
        '--n_cells', '50',
        '--reads_per_cell', '200',
    ])
    if ret.returncode != 0:
        print("测试数据生成失败")
        sys.exit(1)

    print("\n测试数据已生成，运行 upstream pipeline ...")
    # 创建测试配置（覆盖）
    test_config = os.path.join(os.getcwd(), 'upstream_config.sh')
    with open(test_config, 'w') as f:
        f.write(f'''UPSTREAM_WORKDIR="$(pwd)/upstream_output"
SPECIES="test_species"
THREADS=4
FASTA_FILE="{outdir}/genome.fa"
GTF_FILE="{outdir}/genes.gtf"
SAMPLES=("test_sample1")
CDNA_R1=("{outdir}/test_cDNA_R1.fastq.gz")
CDNA_R2=("{outdir}/test_cDNA_R2.fastq.gz")
OLIGO_R1=("{outdir}/test_oligo_R1.fastq.gz")
OLIGO_R2=("{outdir}/test_oligo_R2.fastq.gz")
''')
    run_shell('run_upstream.sh', ['all'])


def cmd_upstream(args):
    """运行上游 pipeline"""
    check_docker()
    if not os.path.exists('upstream_config.sh'):
        print("Error: 找不到 upstream_config.sh")
        print("运行 scpipe init 生成配置模板")
        sys.exit(1)
    step = args.step or 'status'
    return run_shell('run_upstream.sh', [step])


def cmd_downstream(args):
    """运行下游 pipeline"""
    check_docker()
    if not os.path.exists('config.sh'):
        print("Error: 找不到 config.sh")
        print("运行 scpipe init 生成配置模板")
        sys.exit(1)
    step = args.step or 'status'
    return run_shell('run_pipeline.sh', [step])


def cmd_status(args):
    """查看状态"""
    print("=== Upstream ===")
    run_shell('run_upstream.sh', ['status'])
    print("\n=== Downstream ===")
    run_shell('run_pipeline.sh', ['status'])


def cmd_clean(args):
    """清理输出"""
    dirs = ['upstream_output', 'dataget_output', 'test_data']
    for d in dirs:
        if os.path.exists(d):
            if args.yes or input(f"删除 {d}/ ? [y/N] ").lower() == 'y':
                shutil.rmtree(d)
                print(f"  已删除 {d}/")
    print("清理完成")


# ========== 主入口 ==========

def main():
    parser = argparse.ArgumentParser(
        prog='scpipe',
        description='BGI DNBelab C4 单细胞 RNA-seq 分析 pipeline',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例:
  scpipe init                     生成配置文件
  scpipe pull                     拉取 Docker 镜像
  scpipe upstream mkgtf           校正 GTF
  scpipe upstream mkref           建基因组索引
  scpipe upstream count           定量
  scpipe upstream velocity        提取 velocity 矩阵
  scpipe downstream prep          整理目录
  scpipe downstream soupx         去环境 RNA
  scpipe downstream scrublet      QC + 双细胞检测
  scpipe downstream all           全部下游步骤
  scpipe status                   查看进度

GitHub: https://github.com/liruirui123/scpipe
'''
    )
    parser.add_argument('-v', '--version', action='version', version=f'scpipe {__version__}')
    sub = parser.add_subparsers(dest='command')

    # init
    p_init = sub.add_parser('init', help='生成配置文件模板')
    p_init.add_argument('--force', action='store_true', help='覆盖已有配置')

    # pull
    p_pull = sub.add_parser('pull', help='拉取 Docker 镜像')
    p_pull.add_argument('image', nargs='?', help='只拉取指定镜像 (dnbc4tools|py-scanpy|r-soupx|r-seurat)')

    # test
    sub.add_parser('test', help='生成测试数据并验证 pipeline')

    # upstream
    p_up = sub.add_parser('upstream', help='上游分析 (FASTQ → 矩阵)')
    p_up.add_argument('step', nargs='?', default='status',
                       choices=['all', 'mkgtf', 'mkref', 'count', 'velocity', 'status', 'reset'],
                       help='运行步骤')

    # downstream
    p_down = sub.add_parser('downstream', help='下游分析 (矩阵 → QC h5ad)')
    p_down.add_argument('step', nargs='?', default='status',
                         choices=['all', 'prep', 'wdl', 'soupx', 'scrublet', 'sscrublet', 'scdatacg', 'status', 'reset'],
                         help='运行步骤')

    # status
    sub.add_parser('status', help='查看所有步骤状态')

    # clean
    p_clean = sub.add_parser('clean', help='清理输出文件')
    p_clean.add_argument('-y', '--yes', action='store_true', help='不询问直接删除')

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    cmds = {
        'init': cmd_init,
        'pull': cmd_pull,
        'test': cmd_test,
        'upstream': cmd_upstream,
        'downstream': cmd_downstream,
        'status': cmd_status,
        'clean': cmd_clean,
    }
    sys.exit(cmds[args.command](args) or 0)


if __name__ == '__main__':
    main()
