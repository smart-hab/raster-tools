# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
# Build (outputs to build/Release/RasterTools.app)
xcodebuild -scheme RasterTools -destination 'platform=macOS' -configuration Release SYMROOT=build build

# Test
xcodebuild -scheme RasterTools -destination 'platform=macOS' test

# Run a single test
xcodebuild -scheme RasterTools -destination 'platform=macOS' test -only-testing RasterToolsTests/RasterToolsTests/testExample
```

Deployment target: macOS 26.2. Uses Swift 6 Testing APIs (`@Test`, `#expect`).

## Architecture

RasterTools is a macOS app for geospatial raster processing. All heavy computation is delegated to Python CLI tools invoked as subprocesses; the Swift layer handles UI, persistence, and orchestration.

```
SwiftUI Views → SwiftData Models → Service Layer (ToolRunners) → Python subprocess calls
```

**Data flow:**
1. User adds a workspace (source directory on disk)
2. `WorkspaceScanner` discovers raster files (composite.tif, udm2, shapefiles) and creates `WorkspaceResource` records
3. User creates a tool configuration (`ToolKmeansConfiguration`, `ToolPreprocessConfiguration`, or `ToolCollectionConfiguration`)
4. Running a configuration instantiates the matching `ToolRunner` subclass, which invokes Python scripts step-by-step
5. Each step records output files as new `WorkspaceResource` objects with parent-child provenance links
6. Outputs go to `~/Library/Application Support/RasterTools/outputs/{WorkspaceID}/{ToolID}/`, keeping source directories clean

## Key Layers

### Models (`Models/`) — SwiftData entities
- **`Workspace`** — root container; holds source directory path, resources, and tool configs
- **`WorkspaceResource`** — a file on disk with kind, metadata, and provenance (parent/children)
- **`ResourceKind`** — 14-value enum (sourceRaster, clipped, masked, ndvi, ndci, kmeansCenters, kmeansClassed, kmeansMean, kmeansDiff, shapeFile, udm, metadata, unknown, …)
- **`ToolKmeansConfiguration`**, **`ToolPreprocessConfiguration`**, **`ToolCollectionConfiguration`** — per-tool parameter structs persisted via SwiftData

### Services (`Services/`) — business logic
- **`ToolRunner`** (base, `@Observable`) — subprocess execution, real-time log/progress updates, `makeResource()` for provenance recording. Executables resolved from user-configured Python venv.
- **`ToolKmeans`** — fit → classify → mean → difference raster pipeline
- **`ToolPreprocess`** — clip → mask → NDVI/NDCI pipeline
- **`ToolCollection`** — Planet API search → queue (5-min countdown) → order → download with order memory
- **`ToolPlanetDownload`** — downloads and SHA256-verifies Planet orders
- **`WorkspaceScanner`** — filesystem scan with date extraction and automatic UDM2 pairing
- **`JobRegistry`** — singleton tracking active jobs; blocks app quit while jobs run
- **`AppSettings`** — `UserDefaults`-backed global config (venv path, Planet API key)
- **`AppStorage`** — manages output directory structure
- **`PlanetAPI`** — HTTP client for Planet API (search, order, status, manifest, download)

### Views (`Views/`) — SwiftUI
- **`AppView`** — root `NavigationSplitView`
- **`SidebarView`** — workspace/configuration tree
- **`WorkspaceDetailView`** — resource gallery + configuration list
- **`ToolKmeansView`**, **`ToolPreprocessView`**, **`ToolCollectionView`** — per-tool parameter editors
- **`ToolRunnerSheet`** — modal with live progress bar and log output
- **`ResourcePickerView`** — multi-select file picker with sorting/grouping
- **`ResourceGallerySheet`** — thumbnail image gallery (PNG previews of rasters)
- **`SettingsView`** — venv path and Planet API key configuration

## Patterns & Conventions

- **`@Observable` for runners**: `ToolRunner` and subclasses use the `@Observable` macro (not `ObservableObject`). UI observes properties directly without explicit `@Published`.
- **SwiftData previews**: Always use an in-memory `ModelContainer` in `#Preview` blocks — never use the live store or strip `@Model` from view interfaces just to avoid the requirement.
