import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared

# cli parser
def parse_args():
  p = argparse.ArgumentParser(prog='select_bands', description='Select bands from raster')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination raster path')
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int, default=[1])
  p.add_argument('-l', '--list', help='Display list of available bands', action='store_true', default=False)
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument('--8b', dest='bands', action='store_const', const=[1,2,3,4,5,6,7,8])
  p.add_argument('--4b', dest='bands', action='store_const', const=[2,4,6,8])
  p.add_argument('--rgb', dest='bands', action='store_const', const=[6,4,2])
  return p.parse_args()


def main(args):

  # logger
  logger = shared.setup_logger('select_bands', args.verbose)

  # input
  args.input = pathlib.Path(args.cwd) / args.input

  # raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)
  raster_bands = shared.raster_bands(raster)

  # list and exit
  if args.list:
    for (band, name) in raster_bands.items():
      print(f"Band {band}: {name}")
    exit(0)

  # band names
  band_names = tuple(raster_bands.get(b, str(b)) for b in args.bands)
  logger.info(f'Selected bands: {band_names}')
  selection = '-'.join(band_names)

  # output
  if not args.output:
    args.output = args.input.parent / f'{args.input.stem}_{selection}.tif'
  else:
    args.output = pathlib.Path(args.cwd) / args.output

  # save raster
  logger.info(f'Saving raster... {args.output}')
  raster = raster.sel(band=args.bands)
  raster.attrs['long_name'] = band_names
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")
  
  # done
  logger.info('Done')

if __name__ == '__main__':
    args = parse_args()
    main(args)
