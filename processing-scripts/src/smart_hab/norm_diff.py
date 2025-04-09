import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared

NDCI = [5,6]
NDVI = [5,7]
NDRI = [5,3]

def parse_args():
  p = argparse.ArgumentParser(prog='norm_diff', description='Normalize difference between two bands')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-l', '--list', help='Display list of available bands', action='store_true', default=False)
  p.add_argument('-b', '--bands', help='Band selection', nargs=2, type=int)
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument('--ndci', help='Calculate NDCI', dest='bands', action='store_const', const=NDCI)
  p.add_argument('--ndvi', help='Calculate NDVI', dest='bands', action='store_const', const=NDVI)
  p.add_argument('--ndri', help='Calculate NDRI', dest='bands', action='store_const', const=NDRI)
  return p.parse_args()  

def main(args):

  # logger
  logger = shared.setup_logger('png', args.verbose)

  # load raster
  args.input = pathlib.Path(args.cwd) / args.input
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)
  raster_bands = shared.raster_bands(raster)

  # list and exit
  if args.list:
    for (band, name) in raster_bands.items():
      print(f"Band {band}: {name}")
    exit(0)

  # band selection
  band_names = tuple(raster_bands.get(b, str(b)) for b in args.bands)
  selection = '-'.join(("norm", "diff", *band_names))
  if args.bands == NDCI: selection = 'ndci'
  if args.bands == NDVI: selection = 'ndvi'
  if args.bands == NDRI: selection = 'ndri'

  # normalized diff
  logger.info(f'Calculating normalized difference... {band_names}')
  raster = shared.raster_norm_diff(raster, args.bands[0], args.bands[1])
  raster = raster * 10000
  raster.attrs['long_name'] = (selection,)

  # output
  if not args.output:
    args.output = args.input.parent / f'{args.input.stem}_{selection}.tif'
  else:
    args.output = pathlib.Path(args.cwd) / args.output
  logger.info(f'Saving raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")
  
  # done
  logger.info('Done')

if __name__ == '__main__':
    args = parse_args()
    main(args)
