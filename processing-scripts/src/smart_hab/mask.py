import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared

def parse_args():
  p = argparse.ArgumentParser(prog='mask', description='Mask raster with UDM2 file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-u', '--udm2', help='UDM2 file path', required=True)
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int, default=[3, 6])
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-l', '--list', help='Display list of available bands', action='store_true', default=False)
  p.add_argument('-v', '--verbose', help='Display extra information', default=False, action='store_true')
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  return p.parse_args()
  
def main(args):
  
  # setup logger
  logger = shared.setup_logger('mask', args.verbose)

  # load mask
  args.udm2 = pathlib.Path(args.cwd) / args.udm2
  logger.info(f'Loading UDM2... {args.udm2}')
  udm = shared.load_raster(args.udm2, args.crs)
  udm_bands = shared.raster_bands(udm)

  # list and exit
  if args.list:
    for (band, name) in udm_bands.items():
      print(f"Band {band}: {name}")
    exit(0)

  # load raster
  args.input = pathlib.Path(args.cwd) / args.input
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)

  # mask
  for band in args.bands:
    band_name = udm_bands[band]
    if not band_name:
      raise RuntimeError(f"Band {band} not found in raster")
    logger.info(f'Masking band {band_name}...')
    raster = raster.where(~udm.sel(band=band).astype(bool))

  # save
  if not args.output:
    args.output = args.input.parent / f'{args.input.stem}_masked.tif'
  else:
    args.output = pathlib.Path(args.cwd) / args.output
  logger.info(f'Saving masked raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")

  # done
  logger.info('Done')

if __name__ == '__main__':
  args = parse_args()
  main(args)
