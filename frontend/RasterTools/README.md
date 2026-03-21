# RasterTools

A native macOS application for geospatial raster processing workflows.

## Overview

RasterTools provides a SwiftUI interface for configuring and running geospatial data processing pipelines.
All workflow orchestration is implemented natively in Swift, with direct subprocess calls to Python CLI tools for raster operations.

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
│   Python CLI Tools              │
│  - GDAL/rasterio operations     │
└─────────────────────────────────┘
```

## Features

### K-Means Clustering
- Configure clustering parameters
- Select fit/classify rasters  
- Generate mean & difference rasters
- Automatic visualization
- Real-time progress

### Preprocessing  
- Clip to shape boundaries
- Auto-apply UDM2 masks
- NDVI/NDCI calculation
- Batch processing
- Step-by-step progress

## Project Structure

```
Models/ToolConfiguration.swift     # SwiftData models
Services/
  ├── ToolRunner.swift             # Base runner
  ├── KMeansRunner.swift           # K-means workflow
  └── PreprocessRunner.swift       # Preprocess workflow
Views/
  ├── KMeansConfigView.swift
  ├── PreprocessConfigView.swift
  └── SharedViews.swift
ContentView.swift
RasterToolsApp.swift
```

### Models (SwiftData)
```swift
@Model ToolConfiguration
  - name, workspace, toolType
  - kmeansConfig: KMeansConfiguration?
  - preprocessConfig: PreprocessConfiguration?

@Model KMeansConfiguration
  - centersFile, centroids, nTimes, seed
  - filesFit, filesClassify

@Model PreprocessConfiguration  
  - shapeFile
  - processes: [PreprocessType]  // NDVI, NDCI
  - files
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

## Usage

1. Create configuration (name + workspace)
2. Configure parameters & select files  
3. Click "Run" → watch real-time progress
    - Reads config from SwiftData
    - Executes workflow step-by-step
    - Calls Python CLI tools as subprocesses
    - Updates UI in real-time
    - Shows progress bar and logs
4. View results in workspace


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
