# raster-tools

Tooling for processing and visualizing hazardous algae bloom (HAB) imagery: a Python
processing package and the native macOS application that drives it. Both halves used to
live in separate repositories and were merged here with their histories intact.

## Layout

```none
processing-scripts/   Python package `smart_hab` — the raster processing CLI
frontend/             RasterTools — SwiftUI macOS app that runs those tools
```

### `processing-scripts/`

A `hatchling` package (`src/smart_hab`) exposing one console script per operation —
`about`, `clip`, `convert_shape`, `kmeans_fit`, `kmeans_classify`, `mask`, `means`,
`norm_diff`, `plot`, `s2_stack`, `select_bands`, `subtract` — plus the higher level
`preprocess`, `kmeans` and `preload_source_files` pipelines. `http.py` serves the same
operations over FastAPI. Entry points and dependencies are declared in `pyproject.toml`.

See [processing-scripts/readme.md](processing-scripts/readme.md).

### `frontend/`

The RasterTools Xcode project: project browsing, tool configuration, Planet and
Sentinel-2 scene collection, and run history. Sources are under `RasterTools/`
(`Models/`, `Services/`, `Views/`), tests under `RasterToolsTests/` and
`RasterToolsUITests/`.

See [frontend/README.md](frontend/README.md) for usage and
[frontend/CLAUDE.md](frontend/CLAUDE.md) for the architecture notes.

## How the two halves connect

The app never imports the Python code. It provisions a virtualenv in
`~/Library/Application Support/RasterTools/venv`, pip-installs the processing package
into it (`ToolVenvSetup`), and then invokes the installed console scripts as
subprocesses (`ToolRunner`). Adding an operation therefore means adding it to
`pyproject.toml`'s `[project.scripts]` on the Python side and a matching tool
configuration on the Swift side.
