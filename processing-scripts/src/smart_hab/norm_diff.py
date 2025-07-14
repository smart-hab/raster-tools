import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared
import typing

NDCI = [5,6]
NDVI = [5,7]

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  crs: typing.Optional[str]
  bands: list[int]
  selection: str
  info: bool
  verbose: bool

def parse_args() -> Args:
  # parser
  p = argparse.ArgumentParser(prog='norm_diff', description='Normalize difference between two bands')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-I', '--info', help='Display raster info', action='store_true', default=False)
  p.add_argument('-b', '--bands', help='Band selection', nargs=2, type=int)
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
    selection=selection,
    info=args.info,
    verbose=args.verbose,
  )

def main(args: Args) -> None:
  # logger
  logger = shared.setup_logger('png', args.verbose)

  # load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)
  raster_bands = shared.raster_bands(raster)

  # info and exit
  if args.info:
    print(f'\n[{args.input.name}]')
    shared.raster_print_info(raster)
    exit(0)

  # band selection
  band_names = tuple(raster_bands.get(b, str(b)) for b in args.bands)

  # normalized diff
  logger.info(f'Calculating normalized difference... {band_names}')
  raster = shared.raster_norm_diff(raster, args.bands[0], args.bands[1])
  raster = raster * 10000
  raster.attrs['long_name'] = (args.selection,)

  # output
  logger.info(f'Saving raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")
  
  # done
  logger.info('Done')

if __name__ == '__main__':
    args = parse_args()
    main(args)
