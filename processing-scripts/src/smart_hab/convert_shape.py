from . import shared
import geopandas as gpd
import json
import logging
import pathlib
import rasterio
import typing

def convert_shape(
  input: pathlib.Path | typing.BinaryIO,
  output: pathlib.Path,
  crs: str | None,
  logger: logging.Logger,
) -> None:

  # oldshape
  oldshape = shared.load_shape(input, crs=None)

  # crs conversion
  if crs and oldshape.crs != crs:
    logger.info(f'Converting CRS... {oldshape.crs} -> {crs}')
    oldshape.to_crs(crs, inplace=True)

  # newshape
  try:
    newshape = json.loads(oldshape.to_json())
  except:
    raise RuntimeError(f'Could not read geometry coordinates of dataframe')

  # save
  try:
    logger.info(f'Saving GeoJSON... {output}')
    geojson = json.dumps(newshape, indent=2)
    with open(output, 'w') as file:
      file.write(geojson)
  except Exception as e:
    raise RuntimeError(f'Could not write to file: {output}') from e
