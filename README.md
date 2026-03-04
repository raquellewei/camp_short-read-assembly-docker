![Version](https://img.shields.io/badge/version-0.8.0-brightgreen)

## Overview

This module is designed to function as both a standalone MAG short-read assembly pipeline as well as a component of the larger CAMP metagenome analysis pipeline. As such, it is both self-contained (ex. instructions included for the setup of a versioned environment, etc.), and seamlessly compatible with other CAMP modules (ex. ingests and spawns standardized input/output config files, etc.).

Both MetaSPAdes and MegaHit are provided as assembly algorithm options, with QUAST for assembly quality assessment.

---

## Installation

### Option 1: Singularity/Apptainer (Recommended — HPC & Linux servers)

No conda setup required. Singularity pulls the image directly from Docker Hub and caches it as a `.sif` file:

```bash
singularity pull camp-srasm.sif docker://raquelle70679/camp-srasm:latest
```

Run the built-in test to verify:
```bash
singularity run camp-srasm.sif test
```

> **Note:** Apptainer is the new name for Singularity (v3.9+). All commands are identical — just replace `singularity` with `apptainer`.

### Option 2: Docker (Cloud VMs & local machines)

```bash
docker pull raquelle70679/camp-srasm:latest
```

Or build the image yourself from this repo:

```bash
git clone https://github.com/raquellewei/camp_short-read-assembly-docker
cd camp_short-read-assembly-docker
docker build -t camp-srasm .
```

### Option 3: Local conda install

See the [original upstream repo](https://github.com/Meta-CAMP/camp_short-read-assembly) for conda-based local installation instructions using `setup.sh`.

---

## Using the Container

### Input

Prepare a `samples.csv` with absolute paths to your FASTQ files **as they will appear inside the container**:

```
sample_name,illumina_fwd,illumina_rev
sample1,/data/input/sample1_1.fastq.gz,/data/input/sample1_2.fastq.gz
```

### Output

The pipeline produces:
- `/data/output/short-read-assembly/final_reports/samples.csv` — output config for the next CAMP module
- `/data/output/short-read-assembly/final_reports/<sample>.metaspades.fasta` — MetaSPAdes assembled contigs
- `/data/output/short-read-assembly/final_reports/<sample>.megahit.fasta` — MegaHit assembled contigs
- `/data/output/short-read-assembly/final_reports/ctg_stats.csv` — per-assembler contig statistics
- `/data/output/short-read-assembly/final_reports/quast.tar.gz` — QUAST assembly quality report

---

## Singularity Usage

### Running the Pipeline

```bash
singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srasm.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running on a Slurm Cluster

```bash
sbatch << 'EOF'
#!/bin/bash
#SBATCH --job-name=camp-srasm
#SBATCH --cpus-per-task=10
#SBATCH --mem=80G
#SBATCH --output=camp-srasm-%j.log

singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srasm.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
EOF
```

### Choosing Assembler(s)

By default, both MetaSPAdes and MegaHit are run. To customize, create a `parameters.yaml`:

```yaml
conda_prefix: '/opt/conda/envs'

# Run only MetaSPAdes, only MegaHit, or both:
assembler: 'metaspades'       # or 'megahit' or 'metaspades,megahit'

# SPAdes mode: 'meta' (metagenomics), 'rna', 'metaviral', 'metaplasmid'
option: 'meta'
```

Then run with:

```bash
singularity run \
    --bind /path/to/your/fastqs:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srasm.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv \
    -p /data/config/parameters.yaml
```

### Running the Built-in Test

```bash
mkdir -p ~/camp-test-out
singularity run \
    --bind ~/camp-test-out:/data/test_out \
    ~/CAMP/camp-srasm.sif test
```

Output will be written to `~/camp-test-out/` on your host so you can inspect it. Test output is kept separate from real experiment output (`/data/output`) to avoid mixing the two.

### Cleanup Intermediate Files

After confirming results, remove large intermediate files (SPAdes K-mer graphs, MegaHit intermediate contigs):

```bash
singularity run \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-srasm.sif cleanup \
    -d /data/output \
    -s /data/config/samples.csv
```

### Debugging

Drop into a shell inside the container:

```bash
singularity shell camp-srasm.sif
```

Then manually invoke the pipeline:

```bash
conda run -n short-read-assembly \
    python /opt/camp/workflow/short-read-assembly.py --help
```

### Custom Parameters

The image ships with a default `parameters.yaml` at `/opt/camp/configs/parameters.yaml`. To override it, bind your own file:

```bash
singularity run \
    --bind /path/to/my/parameters.yaml:/opt/camp/configs/parameters.yaml \
    camp-srasm.sif run ...
```

Key parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `assembler` | `'metaspades,megahit'` | Assembler(s) to run — comma-separated |
| `option` | `'meta'` | SPAdes assembly mode (`meta`, `rna`, `metaviral`, `metaplasmid`) |
| `conda_prefix` | `'/opt/conda/envs'` | Path to pre-built conda environments |

---

## Docker Usage

### Running the Pipeline

```bash
docker run \
    -v /path/to/your/fastqs:/data/input \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/config:/data/config \
    raquelle70679/camp-srasm:latest run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running the Built-in Test

```bash
mkdir -p ~/camp-test-out
docker run --rm \
    -v ~/camp-test-out:/data/test_out \
    raquelle70679/camp-srasm:latest test
```

### Debugging

```bash
docker run --entrypoint /bin/bash -it raquelle70679/camp-srasm:latest
```

**Options:**

| Flag | Description |
|------|-------------|
| `-c` | Number of CPU cores (default: 1; use 10+ for real datasets) |
| `-d` | Working directory inside the container (e.g. `/data/output`) |
| `-s` | Path to `samples.csv` inside the container |
| `-p` | Path to a custom `parameters.yaml` (optional) |
| `-r` | Path to a custom `resources.yaml` (optional) |
| `--dry_run` | Print workflow commands without executing |
| `--unlock` | Remove a lock on the working directory after a failed run |

---

## Module Structure

```
└── workflow
    ├── Snakefile
    ├── short-read-assembly.py
    ├── utils.py
    ├── __init__.py
    └── ext/
        └── scripts/
            └── calc_ctg_lens.py
```

- `workflow/short-read-assembly.py`: Click-based CLI wrapping Snakemake for clean management of parameters, resources, and environment variables.
- `workflow/Snakefile`: The Snakemake pipeline definition.
- `workflow/utils.py`: Sample ingestion, work directory setup, and other utility functions.
- `workflow/ext/scripts/`: Helper scripts used within pipeline rules.

---

## Credits

- This package was created with [Cookiecutter](https://github.com/cookiecutter/cookiecutter) as a simplified version of the [project template](https://github.com/audreyr/cookiecutter-pypackage).
- Original upstream repo: [Meta-CAMP/camp_short-read-assembly](https://github.com/Meta-CAMP/camp_short-read-assembly)
- Free software: MIT
- Documentation: https://camp-documentation.readthedocs.io/en/latest/short-read-assembly.html
