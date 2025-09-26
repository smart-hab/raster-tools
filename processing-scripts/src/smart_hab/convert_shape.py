import geopandas as gpd
import json
import logging
import pathlib
import rasterio

def convert_shape(
  input: pathlib.Path,
  output: pathlib.Path,
  crs: str | None,
  logger: logging.Logger,
) -> None:

  # shape
  try:
    logger.info(f'Loading shape... {input}')
    oldshape = gpd.read_file(input)
  except Exception as e:
    raise RuntimeError(f'Could not read shape file: {input}') from e

  # type check
  if not isinstance(oldshape, gpd.GeoDataFrame):
    raise RuntimeError(f'Not pandas GeoDataFrame type: {input}')

  # crs conversion
  if crs and oldshape.crs != crs:
    logger.info(f'Converting CRS... {oldshape.crs} -> {crs}')
    oldshape.to_crs(crs, inplace=True)

  # newshape
  try:
    newshape = json.loads(oldshape.to_json())
  except:
    raise RuntimeError(f'Could not read geometry coordinates of dataframe')

  # geojson
  geojson = json.dumps(newshape)

  # save
  try:
    logger.info(f'Saving GeoJSON... {output}')
    with open(output, 'w') as file:
      file.write(geojson)
  except Exception as e:
    raise RuntimeError(f'Could not write to file: {output}') from e
