import argparse
import os
import pathlib
import smart_hab.shared as shared
import typing

NDCI = [7,6] # NDCI = (Red Edge, Red)
NDVI = [8,6] # NDVI = (NIR, RED) 

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  crs: typing.Optional[str]
  bands: list[int]
  filter: tuple[float, float]
  dtype: shared.Dtype
  selection: str
  verbose: bool

def parse_args() -> Args:
  # parser
  p = argparse.ArgumentParser(prog='norm_diff', description='Normalize difference between two bands')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-b', '--bands', help='Band selection', nargs=2, type=int)
  p.add_argument('-f', '--filter', metavar=('LOW', 'HIGH'), help='Robust normalization percentile filter', type=float, nargs=2, default=[1.0, 99.0])
  p.add_argument('-d', '--dtype', help='Output data type', choices=shared.dtypes, default='uint16')
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument('--ndci', help='Calculate NDCI', dest='bands', action='store_const', const=NDCI)
  p.add_argument('--ndvi', help='Calculate NDVI', dest='bands', action='store_const', const=NDVI)
  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  # selection
  selection = 'norm_diff'
  if args.bands == NDCI: selection = 'ndci'
  if args.bands == NDVI: selection = 'ndvi'
  # output
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_{selection}.tif'
  return Args(
    input=input,
    output=output,
    crs=args.crs,
    bands=args.bands,
    filter=(args.filter[0], args.filter[1]),
    dtype=args.dtype,
    selection=selection,
    verbose=args.verbose,
  )

def main(args: Args) -> None:
  # logger
  logger = shared.setup_logger('png', args.verbose)

  # load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)
  raster_bands = shared.raster_bands(raster)

  # band selection
  band_names = tuple(raster_bands.get(b, str(b)) for b in args.bands)

  # normalized difference
  logger.info(f'Calculating normalized difference... {band_names}')
  raster = shared.raster_norm_diff(raster, args.bands[0], args.bands[1])

  # robust normalization
  logger.info(f'Removing outlier values below {args.filter[0]} and above {args.filter[1]} percentile...')
  raster = shared.raster_robust_norm(raster, low=args.filter[0], high=args.filter[1])

  # scale
  logger.info(f'Scaling raster to {args.dtype}...')
  raster = shared.raster_scale(raster, dtype=args.dtype)

  # set attributes
  raster.attrs['long_name'] = (args.selection,)

  # output
  logger.info(f'Saving {args.dtype} raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=args.dtype, compress='lzw')

  # done
  logger.info('Done')
