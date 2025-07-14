import argparse
import pathlib
import os
import numpy as np
import rasterio
from sklearn.cluster import KMeans
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: typing.List[pathlib.Path]
  output: pathlib.Path
  clusters: int
  band: int
  times: int
  random: int | None
  verbose: bool
  cwd: pathlib.Path

def parse_args() -> Args:
  # parser
  p = argparse.ArgumentParser(
    prog='kmeans_fit',
    description='Fit K-Means clusters to a single band of one or more input rasters'
  )
  p.add_argument(
    '-i', '--input', nargs='+', help='Raster source path(s)', required=True
  )
  p.add_argument(
    '-o', '--output', help='Clusters destination path', required=True
  )
  p.add_argument(
    '-c', '--clusters', help='Number of clusters', type=int, default=6
  )
  p.add_argument(
    '-b', '--band', help='Band selection', type=int, default=1
  )
  p.add_argument(
    '-t', '--times', help='Number of times to run K-Means', type=int, default=3
  )
  p.add_argument(
    '-r', '--random', help='Random state for K-Means', type=int, default=None
  )
  p.add_argument(
    '-v', '--verbose', help='Display extra information', action='store_true', default=False
  )
  p.add_argument(
    '-w', '--cwd', help='Working directory', default=os.getcwd()
  )
  # args
  args = p.parse_args()
  input_paths = [pathlib.Path(args.cwd) / p for p in args.input]
  output_path = pathlib.Path(args.cwd) / args.output
  return Args(
    input=input_paths,
    output=output_path,
    clusters=args.clusters,
    band=args.band,
    times=args.times,
    random=args.random,
    verbose=args.verbose,
    cwd=pathlib.Path(args.cwd)
  )

def main(args: Args) -> None:

  # setup logger
  logger = shared.setup_logger('kmeans_fit', args.verbose)

  # load raster(s) band data
  all_band_data = []
  for raster_path in args.input:
    logger.info(f'Loading raster... {raster_path}')
    raster = shared.load_raster(raster_path)
    if args.band not in raster.coords['band'].values:
      raise RuntimeError(f'Band {args.band} not found in raster {raster_path}')
    band_data = raster.sel(band=args.band).values.flatten()
    band_data = band_data[~np.isnan(band_data)]

    # print min and max of the band data
    logger.info(f'Band {args.band} info min: {np.nanmin(band_data)}, max: {np.nanmax(band_data)}, dtype: {band_data.dtype}')

    all_band_data.append(band_data)

  # concatenate all band data
  if not all_band_data:
    raise RuntimeError('No band data found in input rasters')
  data = np.concatenate(all_band_data).reshape(-1, 1)

  # calculate clusters
  logger.info(f'Calculating... clusters: {args.clusters}, times: {args.times}, random: {args.random}')
  kmeans = KMeans(n_clusters=args.clusters, n_init=args.times, random_state=args.random)
  kmeans.fit(data)

  # round and sort the clusters
  centers = kmeans.cluster_centers_
  centers_rounded = np.round(centers, 6)
  centers_sorted = np.sort(centers_rounded.flatten())
  logger.info(f'Clusters: {centers_sorted}')

  # save
  logger.info(f'Saving clusters... {args.output}')
  np.savetxt(args.output, centers_sorted, delimiter=',', fmt='%.6f')

  # done
  logger.info('Done')
