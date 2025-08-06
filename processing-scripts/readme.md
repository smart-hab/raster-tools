# processing-scripts

## Installation

Clone the repo

```none
https://github.com/smart-hab/processing-scripts.git
```

Change branch to `pypackage`

```none
cd processing-scripts
git checkout pypackage
```

In your project, create python virtual environment:

```none
cd /path/to/myproject
python3 -m venv .venv
```

Activate the environment:

```none
source .venv/bin/activate
```

Upgrade pip (optional):

```none
pip install --upgrade pip
```

Install the processing-scripts python package:

```none
pip install -e /path/to/processing-scripts
```

## Overview

This package provides a suite of command-line tools for processing geospatial raster and vector data, with a focus on satellite imagery workflows. The tools are designed to be modular and composable, allowing you to inspect, clean, transform, analyze, and visualize your data efficiently.

A typical processing workflow might look like this:

1. **Inspect your data**  
   Use `about` to quickly view metadata, dimensions, and coordinate systems of your raster or vector files. This helps ensure your inputs are valid and compatible.

2. **Convert vector data (if needed)**  
   If your region of interest is in a shapefile or other format, use `convert_shape` to convert it to GeoJSON for easier handling and compatibility.

3. **Clip rasters to your area of interest**  
   Use `clip` to extract just the region(s) you need from a larger raster, using a shape file or GeoJSON as a clipping path.

4. **Mask unwanted pixels**  
   Use `mask` with a UDM2 file to remove clouds, shadows, or other unwanted areas from your raster data.

5. **Calculate normalized differences or indices**  
   Use `norm_diff` to compute indices like NDVI or NDCI, which are useful for vegetation or water analysis.

6. **Unsupervised classification (optional)**  
   Use `kmeans_fit` to fit K-Means clusters to your data, and `kmeans_classify` to assign cluster labels to each pixel. This is useful for land cover classification or segmentation.

7. **Visualize your results**  
   Use `plot` to quickly generate PNG images from your rasters for reports, presentations, or quality checks.

Each tool is documented below with its parameters and usage examples. You can use them individually or combine them in scripts to automate your geospatial workflows.

## Documentation and examples

Available commands. For more details on each script, run `<command> --help`.

- [about](#about)
- [convert_shape](#convert_shape)
- [clip](#clip)
- [mask](#mask)
- [norm_diff](#norm_diff)
- [kmeans_fit](#kmeans_fit)
- [kmeans_classify](#kmeans_classify)
- [plot](#plot)


### `about`

Displays detailed information about a raster or shape file, such as dimensions, coordinate system, and metadata. Useful for quickly inspecting geospatial data before processing or troubleshooting file issues.

**Parameters**

| Parameter        | Type    | Required | Default | Description                 |
|------------------|---------|----------|---------|-----------------------------|
| `-i`, `--input`  | path    | Yes      |         | Source raster or shape path |
| `-v`, `--verbose`| flag    | No       | False   | Show extra information      |
| `-w`, `--cwd`    | path    | No       | .       | Working directory           |

**Examples**

- Show info for a raster file:
  ```sh
  about -i my_image.tif
  ```
  *Prints dimensions, CRS, and metadata for `my_image.tif`.*

- Show verbose info for a shapefile in a subfolder:
  ```sh
  about -i data/region.shp -v
  ```
  *Prints extra details about `region.shp`.*

---

### `convert_shape`

Converts a shape file (Esri/Fiona/Pyogrio) to GeoJSON format for easier use in web applications or other GIS tools.

**Parameters**

| Parameter        | Type    | Required | Default   | Description                 |
|------------------|---------|----------|-----------|-----------------------------|
| `-i`, `--input`  | path    | Yes      |           | Source shape path           |
| `-o`, `--output` | path    | No       |           | Output GeoJSON path         |
| `-c`, `--crs`    | string  | No       | EPSG:4326 | Target CRS (e.g. EPSG:4326) |
| `-f`, `--format` | string  | No       | geojson   | Output format               |
| `-v`, `--verbose`| flag    | No       | False     | Show extra information      |
| `-w`, `--cwd`    | path    | No       | .         | Working directory           |

**Examples**

- Convert a shapefile to GeoJSON:
  ```sh
  convert_shape -i region.shp
  ```
  *Creates `region.geojson`.*

- Convert and reproject to WGS84 coordinate reference system:
  ```sh
  convert_shape -i region.shp -c EPSG:4326
  ```
  *Creates a GeoJSON in WGS84.*

---

### `clip`

Clips a raster file using a shape file as a mask. Use this to extract a region of interest from a larger dataset, such as focusing on a study area within a satellite image.

**Parameters**

| Parameter        | Type    | Required | Default | Description                 |
|------------------|---------|----------|---------|-----------------------------|
| `-i`, `--input`  | path    | Yes      |         | Source raster path          |
| `-s`, `--shape`  | path    | Yes      |         | Source shape path           |
| `-o`, `--output` | path    | No       |         | Output raster path          |
| `-c`, `--crs`    | string  | No       |         | Target CRS (e.g. EPSG:4326) |
| `-v`, `--verbose`| flag    | No       | False   | Show extra information      |
| `-w`, `--cwd`    | path    | No       | .       | Working directory           |

**Examples**

- Clip a raster to a region defined by a shapefile:
  ```sh
  clip -i big_image.tif -s region.geojson
  ```
  *Creates `big_image_clipped.tif` containing only the area inside `region.geojson`.*

- Clip and specify output file and coordinate reference system:
  ```sh
  clip -i big_image.tif -s region.geojson -o clipped.tif -c EPSG:4326
  ```
  *Creates `clipped.tif` in WGS84 CRS.*

---

### `mask`

Masks a raster file using a UDM2 file, typically to remove clouds or shadows from satellite imagery. This is essential for cleaning up data before analysis.

**Parameters**

| Parameter        | Type    | Required | Default | Description                 |
|------------------|---------|----------|---------|-----------------------------|
| `-i`, `--input`  | path    | Yes      |         | Source raster path          |
| `-u`, `--udm2`   | path    | Yes      |         | Source UDM2 mask path       |
| `-o`, `--output` | path    | No       |         | Output raster path          |
| `-c`, `--crs`    | string  | No       |         | Target CRS (e.g. EPSG:4326) |
| `-b`, `--bands`  | int+    | No       | 3 6     | Band selection              |
| `-v`, `--verbose`| flag    | No       | False   | Show extra information      |
| `-w`, `--cwd`    | path    | No       | .       | Working directory           |

**Examples**

- Mask a raster using a UDM2 file:
  ```sh
  mask -i image.tif -u mask.udm2
  ```
  *Creates `image_masked.tif` with clouds and shadows masked out.*

- Mask a raster using specific UDM bands:
  ```sh
  mask -i image.tif -u mask.udm2 -b 1 2 3
  ```
  *Masks using only bands 1, 2, and 3 from `mask.udm2`*

---

### `norm_diff`

Calculates the normalized difference between two bands (e.g. NDVI for vegetation, NDCI for chlorophyll). This is a common remote sensing technique for highlighting features like vegetation or water.

**Parameters**

| Parameter        | Type    | Required | Default  | Description                                |
|------------------|---------|----------|----------|--------------------------------------------|
| `-i`, `--input`  | path    | Yes      |          | Source raster path                         |
| `-b`, `--bands`  | int+    | Yes*     |          | Source raster bands to use for calculation |
| `-o`, `--output` | path    | No       |          | Output raster path                         |
| `-c`, `--crs`    | string  | No       |          | Target CRS (e.g. EPSG:4326)                |
| `-f`, `--filter` | float+  | No       | 1.0 99.0 | Robust normalization percentile filter     |
| `-d`, `--dtype`  | string  | No       | uint16   | Output data type                           |
| `-v`, `--verbose`| flag    | No       | False    | Show extra information                     |
| `-w`, `--cwd`    | path    | No       | .        | Working directory                          |
| `--ndci`         | flag    | No       |          | Shortcut for NDCI (--bands 7 6)            |
| `--ndvi`         | flag    | No       |          | Shortcut for NDVI (--bands 8 6)            |

\* Either `--bands`, `--ndci`, or `--ndvi` must be specified.

**Examples**

- Calculate NDVI (Normalized Difference Vegetation Index):
  ```sh
  norm_diff -i image.tif --ndvi
  ```
  *Creates `image_ndvi.tif` showing vegetation index.*

- Calculate normalized difference between bands 5 and 3:
  ```sh
  norm_diff -i image.tif -b 5 3 -o image_diff.tif
  ```
  *Creates `image_diff.tif` using bands 5 and 3.*

---

### `kmeans_fit`

Fits K-Means clusters to a single band of one or more input rasters. Useful for unsupervised classification or segmentation of satellite imagery, such as identifying land cover types.

**Parameters**

| Parameter         | Type    | Required | Default | Description                    |
|-------------------|---------|----------|---------|--------------------------------|
| `-i`, `--input`   | path+   | Yes      |         | Source raster path(s)          |
| `-o`, `--output`  | path    | Yes      |         | Output clusters path           |
| `-b`, `--band`    | int     | No       | 1       | Band selection                 |
| `-c`, `--clusters`| int     | No       | 6       | Number of clusters             |
| `-t`, `--times`   | int     | No       | 5       | Number of times to run K-Means |
| `-r`, `--random`  | int     | No       | None    | Random state for K-Means       |
| `-v`, `--verbose` | flag    | No       | False   | Show extra information         |
| `-w`, `--cwd`     | path    | No       | .       | Working directory              |

**Examples**

- Fit clusters to band 1 of a raster:
  ```sh
  kmeans_fit -i image.tif -o summer.npy
  ```
  *Saves cluster centers to `summer.npy`.*

- Fit 3 clusters using band 4 of multiple rasters:
  ```sh
  kmeans_fit -i img1.tif img2.tif -o winter.npy -c 3 -b 4
  ```
  *Clusters are fitted using data from both rasters.*

---

### `kmeans_classify`

Assigns K-Means cluster classes to a raster band using a previously fitted cluster file. This allows you to apply learned clusters to new data for classification.

**Parameters**

| Parameter         | Type    | Required | Default  | Description                              |
|-------------------|---------|----------|----------|------------------------------------------|
| `-i`, `--input`   | path    | Yes      |          | Source raster path                       |
| `-k`, `--clusters`| path    | Yes      |          | Cluster centers path (from `kmeans_fit`) |
| `-o`, `--output`  | path    | Yes      |          | Output raster path                       |
| `-b`, `--band`    | int     | No       | 1        | Band selection                           |
| `-v`, `--verbose` | flag    | No       | False    | Show extra information                   |
| `-w`, `--cwd`     | path    | No       | .        | Working directory                        |

**Examples**

- Classify band 1 on raster using precomputed clusters:
  ```sh
  kmeans_classify -i image.tif -k summer.npy -o classified.tif
  ```
  *Creates `classified.tif` with `summer.npy` clusters for each pixel.*

- Classify a specific band:
  ```sh
  kmeans_classify -i image.tif -k summer.npy -o classified.tif -b 4
  ```
  *Creates `classified.tif` by classifying band 4 with `summer.npy` clusters.*

---

### `plot`

Plots a raster file to a PNG image, either as a grayscale or RGB image. Useful for quick visualization of geospatial data for reports or quality checks.

**Parameters**

| Parameter          | Type    | Required | Default    | Description                            |
|--------------------|---------|----------|------------|----------------------------------------|
| `-i`, `--input`    | path    | Yes      |            | Source raster path                     |
| `-o`, `--output`   | path    | No       |            | Output image path                      |
| `-g`, `--grayscale`| int     | No       | 1          | Plot grayscale image (specify band)    |
| `-r`, `--rgb`      | int+    | No       |            | Plot RGB image (specify three bands)   |
| `-a`, `--alpha`    | float   | No       | 0          | Alpha transparency for NoData values   |
| `-f`, `--filter`   | float+  | No       | 0.5 99.5   | Robust normalization percentile filter |
| `-d`, `--dpi`      | int     | No       | 300        | Plot resolution (dots per inch)        |
| `-c`, `--cmap`     | string  | No       | viridis    | Color map for grayscale images         |
| `-v`, `--verbose`  | flag    | No       | False      | Show extra information                 |
| `-w`, `--cwd`      | path    | No       | .          | Working directory                      |

**Examples**

- Plot a grayscale image from band 1:
  ```sh
  plot -i image.tif
  ```
  *Creates `image.png` using viridis color map.*

- Plot an RGB image using bands 6, 4, 2:
  ```sh
  plot -i image.tif -r 6 4 2 -o image_rgb.png
  ```
  *Creates `image_rgb.png` as a color image.*

---
