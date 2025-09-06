import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  crs: typing.Optional[str]
  bands: list[int]
  verbose: bool

# cli parser
def parse_args() -> Args:
  # parser
  p = argparse.ArgumentParser(prog='select_bands', description='Select bands from raster')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination raster path')
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int, default=[1])
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument('--4b', help='Select RGB + NIR bands', dest='bands', action='store_const', const=[6,4,2,8])
  p.add_argument('--rgb', help='Select RGB bands', dest='bands', action='store_const', const=[6,4,2])
  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_selected.tif'
  return Args(
    input=input,
    output=output,
    crs=args.crs,
    bands=args.bands,
    verbose=args.verbose,
  )

def select_bands(args: Args) -> None:

  # logger
  logger = shared.setup_logger('select_bands', args.verbose)

  # load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input, args.crs)
  raster_bands = shared.raster_bands(raster)

  # band names
  band_names = tuple(raster_bands.get(b, str(b)) for b in args.bands)
  logger.info(f'Selected bands: {band_names}')
  selection = '-'.join(band_names)

  # save raster
  logger.info(f'Saving raster... {args.output}')
  raster = raster.sel(band=args.bands)
  raster.attrs['long_name'] = band_names
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress='lzw')

  # done
  logger.info('Done')
