import argparse
import pathlib
import os
import numpy as np
import rasterio
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  clusters: pathlib.Path
  output: pathlib.Path
  band: int
  verbose: bool
  cwd: pathlib.Path

def parse_args() -> Args:
  p = argparse.ArgumentParser(
    prog='kmeans_classify',
    description='Assign K-Means clusters classes to a raster band'
  )
  p.add_argument(
    '-i', '--input', help='Source raster path', required=True
  )
  p.add_argument(
    '-k', '--clusters', help='Cluster centers file (from kmeans_fit)', required=True
  )
  p.add_argument(
    '-o', '--output', help='Raster destination path', required=True
  )
  p.add_argument(
    '-b', '--band', help='Band selection', type=int, default=1
  )
  p.add_argument(
    '-v', '--verbose', help='Display extra information', action='store_true', default=False
  )
  p.add_argument(
    '-w', '--cwd', help='Working directory', default=os.getcwd()
  )
  args = p.parse_args()
  input_path = pathlib.Path(args.cwd) / args.input
  clusters_path = pathlib.Path(args.cwd) / args.clusters
  output_path = pathlib.Path(args.cwd) / args.output
  return Args(
    input=input_path,
    clusters=clusters_path,
    output=output_path,
    band=args.band,
    verbose=args.verbose,
    cwd=pathlib.Path(args.cwd)
  )

def main(args: Args) -> None:
  logger = shared.setup_logger('kmeans_classify', args.verbose)

  # Load cluster centers
  logger.info(f'Loading cluster centers... {args.clusters}')
  centers = np.loadtxt(args.clusters)
  if centers.ndim == 0:
    centers = np.array([centers])
  centers = centers.flatten().reshape(-1, 1)
  logger.info(f'Cluster centers: {centers}')

  # Load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input)
  if args.band not in raster.coords['band'].values:
    raise RuntimeError(f'Band {args.band} not found in raster {args.input}')
  band_data = raster.sel(band=args.band).values

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
  logger.info(f'Saving clustered raster... {args.output}')
  with rasterio.open(args.input) as src:
    meta = src.meta.copy()
    meta.update(dtype='uint8', count=1)
    with rasterio.open(args.output, 'w', **meta) as dst:
      dst.write(output_data.astype('uint8'), 1)

  logger.info('Done')
