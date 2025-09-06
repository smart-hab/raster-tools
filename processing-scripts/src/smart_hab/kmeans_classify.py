import logging
import numpy as np
import pathlib
import rasterio
import smart_hab.shared as shared

def kmeans_classify(
  input: pathlib.Path,
  clusters: pathlib.Path,
  output: pathlib.Path,
  band: int,
  logger: logging.Logger,
) -> None:

  # Load cluster centers
  logger.info(f'Loading cluster centers... {clusters}')
  centers = np.loadtxt(clusters)
  if centers.ndim == 0:
    centers = np.array([centers])
  centers = centers.flatten().reshape(-1, 1)
  logger.info(f'Cluster centers: {centers}')

  # Load raster
  logger.info(f'Loading raster... {input}')
  raster = shared.load_raster(input)
  if band not in raster.coords['band'].values:
    raise RuntimeError(f'Band {band} not found in raster {input}')
  band_data = raster.sel(band=band).values

  # Prepare output array
  output_data = np.full(band_data.shape, np.nan, dtype=np.uint8)

  # Assign each pixel to nearest cluster using simple distance calculation
  mask = ~np.isnan(band_data)
  flat_pixels = band_data[mask].flatten().reshape(-1, 1)  # shape (N, 1)
  # Compute distances to each centroid
  dists = np.abs(flat_pixels - centers.T)  # shape (N, K)
  nearest = np.argmin(dists, axis=1)      # shape (N,)
  output_data[mask] = nearest.astype(np.uint8)  # assign index

  # Save output raster
  logger.info(f'Saving clustered raster... {output}')
  with rasterio.open(input) as src:
    meta = src.meta.copy()
    meta.update(dtype='uint8', count=1)
    with rasterio.open(output, 'w', **meta) as dst:
      dst.write(output_data.astype('uint8'), 1)

  logger.info('Done')
