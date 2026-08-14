# cyclOPS-monorepo

Mono-repo for the cyclOPS (Optical Pooled Screening) pipelines: image processing,
deep-learning models, organelle profiling, shared utilities, stitching, and the
analysis notebooks behind the paper.


This monorepo contains:
1. A set of **git submodules**, each pinning one package repo to a commit.
2. A **[uv workspace](https://docs.astral.sh/uv/concepts/workspaces/)** root, so every
   submodule is installed editable into one shared `.venv/`.


This repository accompanies the preprint:

> [A multimodal perturbation atlas defines the phenotypic resolution of cellular morphology](https://www.biorxiv.org/content/10.64898/2026.06.01.728087v1.abstract) — bioRxiv, 2026. doi:10.64898/2026.06.01.728087

## Data availability
The processed microscopy images and CROP-Seq data can be explored, visualized, and downloaded through our OPS Explorer portal

> [OPS Explorer — perturbation atlas collection](https://biohub.ai/ops-explorer?collection=6a3f8b91-1c5e-4d3a-9b4c-f7e0a2d8b6f3)

The outputs of all analyses, data underlying figures, and scripts to regenerate all figures from the paper can be found in the [ops-paper-analysis](https://github.com/czbiohub-sf/ops-paper-analysis) repository.

## Submodules

| Directory | Source | Package | Description |
|---|---|---|---|
| `cyclOPS_process` | [czbiohub-sf/cyclops-process](https://github.com/czbiohub-sf/cyclops-process) | `cyclops_process` | Core image-processing pipeline for OPS microscopy data |
| `cyclOPS_utils` | [czbiohub-sf/cyclops-utils](https://github.com/czbiohub-sf/cyclops-utils) | `cyclops_utils` | Shared utilities: experiment resolution, OME-Zarr I/O, SLURM, profiling |
| `cyclOPS_model` | [czbiohub-sf/cyclops-model](https://github.com/czbiohub-sf/cyclops-model) | `cyclops_model` | Single-cell feature extraction, processing, and analysis of OPS data |
| `organelle_profiler` | [czbiohub-sf/organelle-profiler](https://github.com/czbiohub-sf/organelle-profiler) | `organelle_profiler` | Organelle segmentation, geometric features, clustering |
| `ops_paper_analysis` | [czbiohub-sf/ops-paper-analysis](https://github.com/czbiohub-sf/ops-paper-analysis) | `ops-paper-analysis` | Analysis notebooks and figures for the OPS paper |
| `stitching` | [ahillsley/stitching](https://github.com/ahillsley/stitching) | `stitch` | Image stitching for combining microscopy tile acquisitions |


## Getting started

Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:czbiohub-sf/cyclops-monorepo.git
cd cyclops-monorepo
```

Already cloned without them?

```bash
git submodule update --init --recursive
```

### Install with uv

```bash
# Load uv package manager
module load uv
uv sync
```

**Everything**, including RAPIDS, tracking, and visualization:

```bash
uv sync --all-extras
```

Edits to any submodule are importable immediately -- no reinstall.

> **NFS note:** `uv sync --reinstall` can fail with `Directory not empty (os error 39)`
> from stale NFS handles in `__pycache__/`. Use the wrapper, which moves the old
> `.venv` aside first:
> ```bash
> bash scripts/uv_sync.sh              # base reinstall
> bash scripts/uv_sync.sh --all-extras # full reinstall
> ```

### Required configuration

Every OPS package resolves its storage roots from `$OPS_BASE_PATH`, which has **no
default** -- importing one raises a `RuntimeError` if it is unset, so a misconfigured run
cannot read or write somebody else's storage:

```bash
export OPS_BASE_PATH="/path/to/ops_data"
```

Individual pipelines read further optional variables (raw instrument mounts, config and
output roots, log roots). `cyclops_utils` is the source of truth for the full set -- see
[environment configuration](https://github.com/czbiohub-sf/cyclops-utils#environment-configuration)
in its README.

Verify:

```bash
uv run python -c "import cyclops_process, cyclops_utils, cyclops_model, organelle_profiler, stitch; print('imports OK')"
```

#### Extras

Each extra forwards to the corresponding extra on the member packages, so the
members stay the source of truth for their own optional dependencies.

| Extra | Pulls in |
|---|---|
| `gpu` | `cyclops_utils[gpu]` -- torch, cupy, pynvml, monai |
| `hpc` | `cyclops_utils[hpc]` -- submitit, dask |
| `slack` | `cyclops_utils[slack]` -- run notifications |
| `viz` | `cyclops_process[viz]`, `organelle_profiler[interactive]` |
| `model` | `cyclops_process[model]`, `cyclops_model[models,classifier]` |
| `tracking` | `cyclops_process[tracking]` -- gurobipy, tracksdata, geff, hoct |
| `rapids` | `cyclops_process[rapids]`, `organelle_profiler[rapids]` |
| `all` | all of the above |

```bash
uv sync --extra tracking --extra viz
```

Run anything inside the workspace environment with `uv run`:

```bash
uv run python my_script.py
```

## Working with submodules

`scripts/sync.sh` drives the parent and all submodules together:

```bash
bash scripts/sync.sh pull   # pull parent, then every submodule (rebase)
bash scripts/sync.sh push   # push submodules, commit updated refs, push parent
bash scripts/sync.sh        # pull then push
```

## Ownership and maintenance

**This repository is the result of work done at [biohub San Francisco](https://github.com/czbiohub-sf).**

This repository is owned by the [Leonetti group](https://biohub.org/leonetti/) at [biohub San Francisco](https://github.com/czbiohub-sf).

Maintainers (see also [`.github/CODEOWNERS`](.github/CODEOWNERS)):

- Alexander Hillsley ([@ahillsley](https://github.com/ahillsley))
- Gav Sturm ([@gav-sturm](https://github.com/gav-sturm))

Please open an issue or pull request for questions, bugs, or contributions.

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).