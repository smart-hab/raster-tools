import geopandas as gpd
import json
import logging
import pathlib
import rasterio

def main(
  input: pathlib.Path,
  output: pathlib.Path,
  crs: str,
  logger: logging.Logger,
) -> None:

  # crs
  try:
    target = rasterio.CRS.from_string(crs)
  except:
    raise RuntimeError(f'Could not set target CRS: {crs}')

  # shape
  try:
    logger.info(f'Loading shape... {input}')
    oldshape = gpd.read_file(input)
  except:
    raise RuntimeError(f'Could not read shape file: {input}')

  # conversion
  if (oldshape.crs != target):
    logger.info(f'Converting CRS... {oldshape.crs} -> {target}')
    conversion = f'{oldshape.crs} -> {target}'
    oldshape.to_crs(target, inplace=True)
  else:
    conversion = f'{oldshape.crs}'

  # newshape
  try:
    newshape = json.loads(oldshape.to_json())
  except:
    raise RuntimeError(f'Could not read geometry coordinates of dataframe')

  # geojson
  geojson = json.dumps(newshape)

  # save
  try:
    logger.info(f'Saving GeoJSON... {output} [{conversion}]')
    with open(output, 'w') as file:
      file.write(geojson)
  except:
    raise RuntimeError(f'Could not write to file: {output}')
