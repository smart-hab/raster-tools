import argparse
import os
import pathlib
import rasterio
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  udm2: pathlib.Path
  bands: list[int]
  crs: typing.Optional[str]
  verbose: bool

def parse_args():
  # parser
  p = argparse.ArgumentParser(prog='mask', description='Mask raster with UDM2 file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-u', '--udm2', help='UDM2 file path', required=True)
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int, default=[3, 6])
  p.add_argument('-c', '--crs', help='Target CRS', default='EPSG:4326')
  p.add_argument('-v', '--verbose', help='Display extra information', default=False, action='store_true')
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_masked.tif'
  udm2 = pathlib.Path(args.cwd) / args.udm2
  return Args(
    input=input,
    output=output,
    udm2=udm2,
    bands=args.bands,
    crs=args.crs,
    verbose=args.verbose,
  )

def main(args: Args) -> None:

  # setup logger
  logger = shared.setup_logger('mask', args.verbose)

  # load mask
  logger.info(f'Loading UDM2... {args.udm2}')
  udm = shared.load_raster(args.udm2, args.crs)
  udm_bands = shared.raster_bands(udm)

  # load raster
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
  logger.info(f'Saving masked raster... {args.output}')
  raster.rio.to_raster(args.output, dtype=rasterio.uint16, compress="lzw")

  # done
  logger.info('Done')
