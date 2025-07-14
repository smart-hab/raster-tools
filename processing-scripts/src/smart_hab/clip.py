import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  shape: pathlib.Path
  crs: typing.Optional[str]
  verbose: bool

def parse_args() -> Args:
  # parser
  p = argparse.ArgumentParser(prog='clip', description='Clip raster with shape file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination raster path')
  p.add_argument('-s', '--shape', help='Shape file path', required=True)
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-v', '--verbose', help='Display extra information', default=False, action='store_true')
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())

  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  shape = pathlib.Path(args.cwd) / args.shape
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_clipped.tif'
  return Args(
    input=input,
    output=output,
    shape=shape,
    crs=args.crs,
    verbose=args.verbose,
  )

def main(args: Args) -> None:
  # setup logger
  logger = shared.setup_logger('clip', args.verbose)

  # load shape
  logger.info(f'Loading shape... {args.shape}')
  shape = shared.load_shape(args.shape, args.crs)

  # load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)

  # clip
  logger.info(f'Clipping...')
  raster = raster.rio.clip(shape.geometry, args.crs)

  # output
  logger.info(f'Saving clipped raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress='lzw')

  # done
  logger.info('Done')
