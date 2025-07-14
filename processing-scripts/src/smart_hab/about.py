import argparse
import os
import pathlib
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  verbose: bool

def parse_args():
  # parser
  p = argparse.ArgumentParser(prog='info', description='Display raster or shape file info')
  p.add_argument('-i', '--input', help='Source raster or shape path', required=True)
  p.add_argument('-v', '--verbose', help='Display extra information', default=False, action='store_true')
  # args
  args = p.parse_args()
  args.cwd = os.getcwd()
  input = pathlib.Path(args.cwd) / args.input
  return Args(
    input=input,
    verbose=args.verbose,
  )

def main(args: Args) -> None:

  # setup logger
  logger = shared.setup_logger('info', args.verbose)

  match args.input.suffix:
    # shape file
    case '.shp' | '.geojson':
      logger.info(f'Loading shape... {args.input}')
      shape = shared.load_shape(args.input)
      print(f'\n\n[{args.input.name}]')
      print(f'\nCRS: {shape.crs}')
      print(f'\nBounds: {shape.bounds}')
      print(f'\nGeometry')
      print(shape.geometry.describe())
      exit(0)

    # raster file
    case '.tif' | '.tiff':
      logger.info(f'Loading raster... {args.input}')
      raster = shared.load_raster(args.input)
      print(f'\n\n[{args.input.name}]')
      print('\nBands:')
      for (band, name) in shared.raster_bands(raster).items():
        print('  * {0:12} {1}'.format(f'Band {band}', name))
      print(f'\n{raster.coords}')
      print(f'\nCRS: {raster.rio.crs}')
      print(f'\nNoData: {raster.rio.nodata}')
      print('\nTransform:')
      print(raster.rio.transform())
      exit(0)

    # unsupported file format
    case _:
      raise RuntimeError(f'Unsupported file format: {args.input.suffix}')
