# =============================================================================
# CAMP Short-Read Assembly Pipeline
# =============================================================================
# Base image: continuumio/miniconda3 (Debian-based, conda pre-installed)

# -----------------------------------------------------------------------------
# Step 1: Base Image
# -----------------------------------------------------------------------------
FROM continuumio/miniconda3:latest

LABEL maintainer="raquellewei"
LABEL description="CAMP Short-Read Assembly Pipeline"
LABEL version="0.8.0"

# -----------------------------------------------------------------------------
# Step 2: System Dependencies
# -----------------------------------------------------------------------------
# - wget/curl        : downloading data at runtime
# - gzip/bzip2       : compressing/decompressing FASTQ/FASTA files
# - perl             : required by some bioinformatics tools
# - default-jre      : system-level Java (QUAST may invoke Java tools)
# - procps           : allows Snakemake to monitor system resources
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        curl \
        gzip \
        bzip2 \
        perl \
        default-jre-headless \
        procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Step 3: Main CAMP Conda Environment
# -----------------------------------------------------------------------------
# Installs the core runtime environment from the pinned yaml file.
# This includes: snakemake, click, pandas, biopython, and all supporting
# Python packages needed to run the CLI and workflow engine.
#
# Note: assembler tools (spades, megahit, quast) are in their own
# isolated environments (Step 4) to mirror how setup.sh installs them.
COPY configs/conda/short-read-assembly.yaml /tmp/conda/short-read-assembly.yaml

RUN conda env create -f /tmp/conda/short-read-assembly.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 4: Tool-Specific Conda Environments
# -----------------------------------------------------------------------------
# Each assembler and QC tool lives in its own isolated conda environment.
# This mirrors how setup.sh installs them locally:
#   conda create --prefix $envs/spades   -c bioconda spades
#   conda create --prefix $envs/megahit  -c bioconda megahit
#   conda create --prefix $envs/quast    -c bioconda quast
#
# Snakemake activates these envs at runtime via:
#   conda: "spades"  →  /opt/conda/envs/spades
#   conda: "megahit" →  /opt/conda/envs/megahit
#   conda: "quast"   →  /opt/conda/envs/quast
#
# We pre-build them here so the container needs no internet access at
# pipeline runtime.
COPY configs/conda/spades.yaml   /tmp/conda/spades.yaml
COPY configs/conda/megahit.yaml  /tmp/conda/megahit.yaml
COPY configs/conda/quast.yaml    /tmp/conda/quast.yaml

RUN conda env create -f /tmp/conda/spades.yaml \
    && conda env create -f /tmp/conda/megahit.yaml \
    && conda env create -f /tmp/conda/quast.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 5: Copy Pipeline Code
# -----------------------------------------------------------------------------
# Copy the pipeline source into /opt/camp inside the container.
# Only what's needed at runtime is copied — see .dockerignore for exclusions.
#
# Layout inside the container:
#   /opt/camp/workflow/   — Snakefile, CLI entrypoint, utils, ext/scripts
#   /opt/camp/configs/    — conda yamls, parameters templates, resources
#   /opt/camp/test_data/  — bundled test FASTQs for smoke-testing
WORKDIR /opt/camp

COPY workflow/       ./workflow/
COPY configs/        ./configs/
COPY test_data/      ./test_data/

# -----------------------------------------------------------------------------
# Step 6: Generate Container-Appropriate parameters.yaml
# -----------------------------------------------------------------------------
# The pipeline reads parameters.yaml to find:
#   ext           — path to workflow/ext/ (scripts, etc.)
#   conda_prefix  — where Snakemake looks for pre-built conda envs
#   assembler     — which assembler(s) to run ('metaspades', 'megahit', or both)
#   option        — SPAdes mode ('meta' for metagenomics)
#
# Two copies are written:
#   configs/parameters.yaml   — default, used by normal pipeline runs
#   test_data/parameters.yaml — used by the built-in `test` command
#
# Users can override by mounting their own parameters.yaml at runtime:
#   docker run -v /my/params.yaml:/opt/camp/configs/parameters.yaml ...
RUN printf '%s\n' \
    "#'''Parameters'''#" \
    "" \
    "ext: '/opt/camp/workflow/ext'" \
    "conda_prefix: '/opt/conda/envs'" \
    "" \
    "# --- general --- #" \
    "" \
    "# Choose 'megahit', 'metaspades', or both (comma-separated)" \
    "assembler:  'metaspades,megahit'" \
    "" \
    "# SPAdes assembly mode: 'meta' (metagenomics), 'rna', 'metaviral', 'metaplasmid'" \
    "option:     'meta'" \
    > /opt/camp/configs/parameters.yaml \
    && cp /opt/camp/configs/parameters.yaml /opt/camp/test_data/parameters.yaml

# -----------------------------------------------------------------------------
# Step 7: Volume Mount Points
# -----------------------------------------------------------------------------
# Create the directories that users will mount at runtime.
#
# Expected mounts:
#   /data/input    — user's raw FASTQ files
#   /data/output   — working directory for pipeline outputs (real experiments)
#   /data/config   — optional: override samples.csv or parameters.yaml
#   /data/test_out — dedicated output directory for the built-in test command
#                    kept separate from /data/output to avoid mixing test and
#                    real experiment outputs
#
# Example docker run with all mounts:
#   docker run \
#     -v /my/fastqs:/data/input \
#     -v /my/output:/data/output \
#     -v /my/config:/data/config \
#     camp-srasm run -d /data/output -s /data/config/samples.csv
RUN mkdir -p /data/input /data/output /data/config /data/test_out

VOLUME ["/data/input", "/data/output", "/data/config", "/data/test_out"]

# Generate test_data/samples.csv with container-correct paths.
# This file is gitignored (setup.sh writes it locally with host paths),
# so we create it here pointing to the bundled test FASTQs inside the image.
RUN printf '%s\n' \
    "sample_name,illumina_fwd,illumina_rev" \
    "uhgg,/opt/camp/test_data/uhgg_1.fastq.gz,/opt/camp/test_data/uhgg_2.fastq.gz" \
    > /opt/camp/test_data/samples.csv

# -----------------------------------------------------------------------------
# Step 8: Entrypoint
# -----------------------------------------------------------------------------
# The CLI script must run inside the 'short-read-assembly' conda env,
# since click, snakemake, pandas, etc. all live there — not in the base env.
#
# We use conda run to activate the env per-command rather than trying to
# activate it in the shell profile (which doesn't work reliably in Docker).
#
# ENTRYPOINT is fixed — always invokes the pipeline CLI.
# CMD provides the default subcommand ('run'), which users can override:
#
#   # Run the pipeline
#   docker run camp-srasm run -d /data/output -s /data/config/samples.csv
#
#   # Run the built-in test
#   docker run camp-srasm test
#
#   # Cleanup intermediate files
#   docker run camp-srasm cleanup -d /data/output -s /data/config/samples.csv
#
#   # Drop into a shell for debugging
#   docker run --entrypoint /bin/bash -it camp-srasm
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "short-read-assembly", \
            "python", "/opt/camp/workflow/short-read-assembly.py"]
CMD ["--help"]
