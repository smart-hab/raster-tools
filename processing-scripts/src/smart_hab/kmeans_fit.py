from sklearn.cluster import KMeans
import logging
import numpy as np
import pathlib
import smart_hab.shared as shared

def main(
  input: list[pathlib.Path],
  output: pathlib.Path,
  band: int,
  clusters: int,
  times: int,
  random: int | None,
  logger: logging.Logger,
) -> None:

  # load raster(s) band data
  all_band_data = []
  for raster_path in input:
    logger.info(f'Loading raster... {raster_path}')
    raster = shared.load_raster(raster_path)
    if band not in raster.coords['band'].values:
      raise RuntimeError(f'Band {band} not found in raster {raster_path}')
    band_data = raster.sel(band=band).values.flatten()
    band_data = band_data[~np.isnan(band_data)]

    # print min and max of the band data
    logger.info(f'Band {band} info min: {np.nanmin(band_data)}, max: {np.nanmax(band_data)}, dtype: {band_data.dtype}')

    all_band_data.append(band_data)

  # concatenate all band data
  if not all_band_data:
    raise RuntimeError('No band data found in input rasters')
  data = np.concatenate(all_band_data).reshape(-1, 1)

  # calculate clusters
  logger.info(f'Calculating... clusters: {clusters}, times: {times}, random: {random}')
  kmeans = KMeans(n_clusters=clusters, n_init=times, random_state=random)
  kmeans.fit(data)

  # round and sort the clusters
  centers = kmeans.cluster_centers_
  centers_rounded = np.round(centers, 6)
  centers_sorted = np.sort(centers_rounded.flatten())
  logger.info(f'Clusters: {centers_sorted}')

  # save
  logger.info(f'Saving clusters... {output}')
  np.savetxt(output, centers_sorted, delimiter=',', fmt='%.6f')

  # done
  logger.info('Done')
