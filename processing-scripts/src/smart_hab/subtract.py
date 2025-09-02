from rasterio.enums import Resampling
import pathlib
import logging
import rioxarray
import smart_hab.shared as shared

def subtract(
  inputs: tuple[pathlib.Path, pathlib.Path],
  output: pathlib.Path,
  bands: list[int] | None,
  crs: str | None,
  logger: logging.Logger,
  resampling: Resampling,
) -> None:
  
  # load rasters
  try:
    logger.info(f'Loading base raster... {inputs[0]}')
    r1 = rioxarray.open_rasterio(inputs[0])
    if not crs:
      logger.info(f'Target CRS set to: {r1.rio.crs}')
      crs = r1.rio.crs
    if r1.rio.crs != crs:
      logger.info(f'Reprojecting CRS... {r1.rio.crs} -> {crs}')
      r1 = r1.rio.reproject(crs, resampling=resampling)
    if bands:
      r1 = r1.sel(band=bands)
  except Exception as e:
    raise RuntimeError(f'Could not read raster file: {inputs[0]}') from e

  try:
    logger.info(f'Loading subtraction raster... {inputs[1]}')
    r2 = rioxarray.open_rasterio(inputs[1])
    if r2.rio.crs != crs:
      logger.info(f'Reprojecting CRS... {r2.rio.crs} -> {crs}')
      r2 = r2.rio.reproject(crs, resampling=resampling)
    if bands:
      r2 = r2.sel(band=bands)
  except Exception as e:
    raise RuntimeError(f'Could not read raster file: {inputs[1]}') from e
  
  # align
  logger.info(f'Aligning rasters...')
  r2 = r2.rio.reproject_match(r1, resampling=resampling)

  # subtract
  logger.info(f'Subtracting rasters...')
  diff_raster = r1 - r2

  # determine new band names
  try:
    long_name = r1.attrs.get('long_name', None)
    bands = r1.coords['band'].values
    if isinstance(long_name, tuple) and len(long_name) == len(bands):
      selection = set(bands)
      long_name = tuple(name for (band, name) in zip(bands, long_name) if band in selection)
  except:
    long_name = None
  
  # update attributes
  diff_raster.attrs.update({
    'description': f'Computed difference between {inputs[0].name} and {inputs[1].name}',
    'input_files': list(map(str, inputs)),
    'long_name': long_name,
    'processing_date': shared.timestamp(),
  })

  # write to disk
  logger.info(f'Saving difference raster... {output}')
  diff_raster.rio.to_raster(output, compress='lzw')
