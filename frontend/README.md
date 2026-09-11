# RasterTools

A native macOS application for geospatial raster processing workflows.

## Quick Links

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Tools](#tools)
   - [Collection Tool](#collection-tool)
   - [Pre-processing Tools](#pre-processing-tools)
   - [K-Means Clustering](#k-means-clustering)
4. [How to use RasterTools](#how-to-use-rastertools)
   - [Initial Settings](#initial-settings)
   - [Create a Project…](#create-a-project)
   - [Add a Shape File…](#add-a-shape-file)
   - [Add a Tool Configuration…](#add-a-tool-configuration)
   - [Run a Tool Configuration](#run-a-tool-configuration)
   - [Preview Rasters](#preview-rasters)
   - [Place Raster Orders](#place-raster-orders)
   - [Pre-process Rasters](#pre-process-rasters)
   - [Create K-Means Model](#create-k-means-model)
   - [Classify Rasters With K-Means Model](#classify-rasters-with-k-means-model)
5. [Tool Configurations](#tools-configurations)
   - [Collection Parameters](#collection-parameters)
   - [Pre-processing Parameters](#pre-processing-parameters)
   - [K-Means Clustering Parameters](#k-means-clustering-parameters)
6. [Developer](#developer)

## Overview

RasterTools provides a SwiftUI interface for configuring and running geospatial data processing pipelines.
All workflow orchestration is implemented natively in Swift, with direct subprocess calls to Python tools for raster operations.

## Architecture

```
┌────────────────────────────────┐
│      SwiftUI GUI               │
│  - Forms & file selection      │
│  - Real-time progress          │
└─────────────┬──────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│   SwiftData Persistence         │
│  - Configurations & parameters  │
└─────────────┬───────────────────┘
              │
              ▼
┌─────────────────────────────────┐
│   Swift Runner Classes          │
│  - Native workflow logic        │
│  - Progress tracking            │
└─────────────┬───────────────────┘
              │
              ▼ (subprocesses)
┌─────────────────────────────────┐
│   Python Tools                  │
│  - GDAL/rasterio operations     │
└─────────────────────────────────┘
```

## Tools

### Collection Tool

The Collection tool searches Planet.com for available imagery within a date range and area of interest, then places and tracks download orders. Orders are remembered per configuration so you won't accidentally re-order the same scene.

- [x] Search Planet.com imagery
- [x] Save search parameters
- [x] Place Planet.com orders
- [ ] Remember ordered scenes

### Pre-processing Tools

The Pre-processing tool prepares raw Planet rasters for analysis. For each selected raster it clips to a shape boundary, applies a UDM2 cloud/shadow mask, and optionally computes spectral indices (NDVI and/or NDCI).

- [x] Clip to shape boundaries
- [x] Masking with UDM
- [x] NDVI/NDCI band calculation

### K-Means Clustering

The K-Means Clustering tool fits a K-Means model on a set of rasters, classifies a (potentially different) set of rasters using that model, and then generates mean and difference rasters for each cluster.

- [x] Configure clustering parameters
- [x] Select fit/classify rasters  
- [x] Generate mean & difference rasters

### Shared Features
- [x] Automatic PNG previews
- [x] Batch processing
- [x] Step-by-step progress
- [ ] Automatic setup of Python virtual environment


## How to use RasterTools

### Initial Settings

  1. Open the **RasterTools** menu
  2. Select **Settings** (or press `⌘,`)
  3. Set your **Virtual Environment Path** by clicking the **Choose…** button
  4. Set your **Planet API Key** by pasting it in field
  5. **Close** the Settings window

### Create a Project

Projects are the top-level organizational unit. Each project points to a source directory containing the raster files for your area of study, and can reference any number of shape files for clipping and masking operations.

1. Open the **Project** menu
2. Select **Create New Project…** (or press `⌘P`)
3. Type the name in **Name** field
4. Select your project's **Source Directory** using the **Choose Directory…** button
5. Click the **Create** button

Your new project opens in the main view, showing all discovered shape files and raster files from the source directory. A link to the project's output directory is shown at the top — this is where all generated files are written.

![ProjectView](missing-url)

### Add a Shape File

Shape files define the geographic boundaries used by clipping and masking operations. When a project is created, shape files are automatically discovered from the source directory. You can add more at any time by dragging and dropping them onto the Shapes section, or via the Project menu.

1. With a project selected, open the **Project** menu
2. Select **Import Shape Files…**
3. Choose one or more shape files using the system's file browser
4. Click the **Open** button to copy the shapes to your project

### Add a Tool Configuration…

Tool configurations are saved presets of parameters for a specific tool. A project can have multiple configurations — useful when you want to run the same tool with different settings (e.g., different shape files, date ranges, or cluster counts).

1. With a project selected, open the **Project** menu
2. Select **Add Configuration**
3. Choose the **Tool** option (*Collection*, *Preprocess*, *K-Means Clustering*)
4. Type a memorable name in the **Name** field
5. Click the **Create** button

### Run a Tool Configuration

1. With a tool selected, press the **Run Configuration** button
2. The **Tool Progress** is displayed in the sidebar
3. Click the **Tool Progress** in the sidebar to view the **Full Text Log**
4. To cancel a tool, click the **X** button in the **Tool Progress**

### Preview Rasters

When a raster is created by any tool, a PNG plot is automatically generated alongside it so you can preview results without opening a GIS application.

1. With a tool selected, **make a selection** of files you wish to preview
2. Click the **Photograph** (Preview Images) icon to open the **Image Preview**
3. Click any **image thumbnail** to view the enlarged preview
4. Press **Escape** to close the Image Preview

### Place Raster Orders

New rasters are ordered from Planet.com using a Collection configuration. You search for available scenes by date and area, then queue individual dates for ordering and download. Orders are tracked in the configuration's memory so previously ordered scenes are clearly marked.

1. Select a **Collection** configuration in the sidebar
2. Set the **Search Parameters** (date range, shape file, cloud cover)
3. Click **Search** in the toolbar — results appear grouped by date
4. For each date you want, click the **Queue** icon in the result's row
5. The order is placed automatically; progress appears in the sidebar
6. Once complete, downloaded rasters appear in the project resource list

### Pre-process Rasters

Pre-processing clips each raster to your area of interest, removes cloud and shadow pixels using the paired UDM2 mask, and optionally computes NDVI and NDCI spectral indices.

1. Select a **Preprocess** configuration in the sidebar
2. Choose a **Shape File** to use as the clip boundary
3. Under **Files**, select the rasters you want to process
4. Toggle **NDVI** and/or **NDCI** on or off under **Processes**
5. Click **Run** — a progress sheet shows each step as it completes
6. Processed rasters appear in the **Outputs** list when done

### Create K-Means Model

Fitting trains a K-Means model on a set of rasters. The resulting cluster centers are saved and can later be used to classify other rasters.

1. Select a **K-Means Clustering** configuration in the sidebar
2. Set **Centroids**, **N Times**, and **Seed** as desired
3. Under **Fit Files**, select the rasters to train on
4. Click **Run** to compute the fit
5. The fitted model (cluster centers) appears in the **Outputs** list

### Classify Rasters with K-Means Model

Classification applies a previously fitted model to a set of rasters, assigning each pixel to the nearest cluster center.

1. Select a **K-Means Clustering** configuration that has already been fit
2. Under **Classify Files**, select the rasters to classify
3. Click **Run** — the classify step runs, producing classed rasters, a mean average, and difference raster
4. The rasters appear in the project **Outputs** list

## Tools Configurations

Each tool configuration has its own set of parameters. The tables below describe every parameter, its purpose, and its default value.

### Collection Parameters

| Parameter | Description | Default |
|---|---|---|
| Shape File | Area of interest for the search | — |
| Search Start Date | Beginning of the imagery date range | Start of current month |
| Search End Date | End of the imagery date range | End of current month |
| Cloud Cover | Maximum acceptable cloud cover (0–1) | 0.2 (20%) |
| Item Type | Planet item type (e.g. PSScene) | PSScene |
| Product Bundle | Product bundle to order (e.g. analytic_8b_sr_udm2) | analytic_8b_sr_udm2 |
| Harmonized | Apply radiometric harmonization | Yes |
| Composite | Order as composite scenes | Yes |
| Naming Pattern | Template for output file names | `{ConfigName}-{Year}{Month}{Day}-{Parameters}` |

![CollectionView](missing-url)

### Pre-processing Parameters

| Parameter | Description |
|---|---|
| Shape File | Boundary used for clipping |
| Files | Rasters to process |
| Processes | Index calculations to run: **NDVI** (bands 8 & 6) and/or **NDCI** (bands 7 & 6) |

Click **Run** to start processing. A progress sheet opens showing per-step status and live log output. Processed rasters will be saved to the tool's output directory and can be used by other downstream tools.

![PreprocessingView](missing-url)

### K-Means Clustering Parameters

| Parameter | Description | Default |
|---|---|---|
| Centroids | Number of k-means clusters | 6 |
| N Times | Number of independent fits; best result is kept | 10 |
| Seed | Random seed for reproducibility | 42 |
| Fit Files | Rasters used to train the k-means model | — |
| Classify Files | Rasters to classify using the fitted model | — |

Click **Run** to start the pipeline: fit → classify → mean → difference. A progress sheet opens showing per-step status and live log output. All outputs are written to the project's output directory.

![KmeansClusteringView](missing-url)

---

## Developer

### Project Structure

These are the main files of the application. Each tool has its own SwiftData configuration model, SwiftUI view, and service/runner class.

```
Models/
  ├── Project.swift                     # Project, ProjectResource, ResourceKind
  ├── ToolConfiguration.swift           # Base ToolConfiguration protocol
  ├── ToolCollectionConfiguration.swift # Collection model
  ├── ToolKmeansConfiguration.swift     # Kmeans model
  └── ToolPreprocessConfiguration.swift # Proprocess model
Services/
  ├── ToolKmeans.swift                  # K-means workflow
  ├── ToolPlanetDownload.swift          # Planet order downloader
  ├── ToolPreprocess.swift              # Preprocess workflow
  └── ToolRunner.swift                  # Base runner
Views/
  ├── AppView.swift                     # Main view
  ├── PlanetView.swift                  # Planet.com view
  ├── ToolCollectionView.swift          # Collection view
  ├── ToolKmeansView.swift              # Kmeans view
  └── ToolPreprocessView.swift          # Preprocess view
```


### Runner Classes
```swift
class ToolRunner: Observable
  - isRunning, progress, error
  - runProcess() → runs Python tools as subprocesses
  - log(), updateStep(), completeFile()

class KMeansRunner: ToolRunner
  - Implements kmeans workflow in Swift
  - fitKMeans() → calls kmeans_fit
  - classifyRasters() → calls kmeans_classify
  - generateMeanRaster() → calls means
  - generateDifferenceRasters() → calls subtract

class PreprocessRunner: ToolRunner
  - Implements preprocessing workflow in Swift
  - preprocessRaster() for each file:
    1. clip → shape boundary
    2. mask → UDM2 cloud/shadow removal
    3. calculateIndex() → NDVI/NDCI
  - All steps call Python tools directly
```

### Example: Preprocessing a Single Raster

**Swift Code** (replaces bash script):
```swift
// 1. Clip
try await runProcess("clip", ["-i", input, "-o", clipped, "-s", shape])

// 2. Mask  
try await runProcess("mask", ["-i", clipped, "-u", udm, "-o", masked])

// 3. NDCI
if processes.contains(.ndci) {
    try await runProcess("norm_diff", ["-i", masked, "-o", ndci, "-b", "7", "6"])
}

// 4. NDVI
if processes.contains(.ndvi) {
    try await runProcess("norm_diff", ["-i", masked, "-o", ndvi, "-b", "8", "6"])
}

// 5. Visualizations
try await runProcess("plot", ["-i", output, "-o", png])
```

## Implementation Notes

### Python Tool Calls

All Python tools are called directly:
- `kmeans_fit`, `kmeans_classify`
- `clip`, `mask`, `norm_diff`
- `means`, `subtract`, `plot`

These must be in PATH or you can specify full paths.

## Requirements

- macOS 14.0+
- Python CLI tools: `clip`, `mask`, `norm_diff`, `kmeans_fit`, `kmeans_classify`, `means`, `subtract`, `plot`
