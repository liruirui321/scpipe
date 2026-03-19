from setuptools import setup, find_packages

setup(
    name="scpipe",
    version="0.1.0",
    description="BGI DNBelab C4 单细胞 RNA-seq 全流程分析 pipeline",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    author="liruirui",
    url="https://github.com/liruirui123/scpipe",
    packages=find_packages(),
    include_package_data=True,
    package_data={
        "scpipe": ["templates/*"],
    },
    data_files=[
        ("scripts", [
            "scripts/run_upstream.sh",
            "scripts/run_pipeline.sh",
        ]),
        ("tests", [
            "tests/generate_test_data.py",
        ]),
    ],
    entry_points={
        "console_scripts": [
            "scpipe=scpipe.cli:main",
        ],
    },
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Science/Research",
        "Topic :: Scientific/Engineering :: Bio-Informatics",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
    ],
)
