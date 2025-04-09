import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared


def parse_args():
  p = argparse.ArgumentParser(prog='clip', description='Clip raster with shape file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination raster path')
  p.add_argument('-s', '--shape', help='Shape file path', required=True)
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-v', '--verbose', help='Display extra information', default=False, action='store_true')
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  return p.parse_args()


def main(args):

  # setup logger
  logger = shared.setup_logger('clip', args.verbose)

  # load shape
  args.shape = pathlib.Path(args.cwd) / args.shape
  logger.info(f'Clipping with shape... {args.shape}')
  shape = shared.load_shape(args.shape, args.crs)

  # load raster
  args.input = pathlib.Path(args.cwd) / args.input
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)

  # clip
  logger.info(f'Clipping...')
  raster = raster.rio.clip(shape.geometry, args.crs)

  # output
  if not args.output:
    args.output = args.input.parent / f'{args.input.stem}_clipped.tif'
  else:
    args.output = pathlib.Path(args.cwd) / args.output
  logger.info(f'Saving clipped raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")

  # done
  logger.info('Done')

if __name__ == '__main__':
  args = parse_args()
  main(args)
