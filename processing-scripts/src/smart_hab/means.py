from rasterio.enums import Resampling
import logging
import pathlib
import rioxarray
import smart_hab.shared as shared
import xarray

def means(
  inputs: list[pathlib.Path],
  output: pathlib.Path,
  bands: list[int] | None,
  crs: str | None,
  logger: logging.Logger,
  resampling: Resampling,
) -> None:
  
  # invariant
  count = len(inputs)
  assert count > 1, "At least two input rasters are required to compute the mean."

  # load rasters
  rasters = []
  for (i, input) in enumerate(inputs):
    try:
      logger.info(f'Loading raster {i+1}/{count}... {input}')
      r = rioxarray.open_rasterio(input)
      if not crs:
        logger.info(f'Target CRS set to first raster: {r.rio.crs}')
        crs = r.rio.crs
      if r.rio.crs != crs:
        logger.info(f'Reprojecting CRS... {r.rio.crs} -> {crs}')
        r = r.rio.reproject(crs, resampling=resampling)
      if bands:
        r = r.sel(band=bands)
      rasters.append(r)
    except Exception as e:
      raise RuntimeError(f'Could not read raster file: {input}') from e
  
  # intersection
  logger.info(f'Computing spatial intersection...')
  bounds_list = [r.rio.bounds() for r in rasters]
  
  intersection = (
    max(b[0] for b in bounds_list),  # left (minx)
    max(b[1] for b in bounds_list),  # bottom (miny) 
    min(b[2] for b in bounds_list),  # right (maxx)
    min(b[3] for b in bounds_list)   # top (maxy)
  )
  
  valid_intersection = intersection[0] < intersection[2] and intersection[1] < intersection[3]
  assert valid_intersection, "No spatial overlap found between input rasters!"
  
  # clip to intersection
  for (i, r) in enumerate(rasters):
    logger.info(f'Clipping raster {i+1}/{count}...')
    rasters[i] = r.rio.clip_box(*intersection)

  # align
  logger.info(f'Aligning raster 1/{count}...') # first raster is reference
  for (i, r) in enumerate(rasters[1:], start=1):
    logger.info(f'Aligning raster {i+1}/{count}...')
    rasters[i] = r.rio.reproject_match(rasters[0], resampling=resampling)

  # stack and compute mean
  stacked = xarray.concat(rasters, dim='raster')
  mean_raster = stacked.mean(dim='raster', skipna=True)

  # determine new band names
  try:
    long_name = rasters[0].attrs.get('long_name', None)
    bands = rasters[0].coords['band'].values
    if isinstance(long_name, tuple) and len(long_name) == len(bands):
      selection = set(bands)
      long_name = tuple(name for (band, name) in zip(bands, long_name) if band in selection)
  except:
    long_name = None
  
  # update attributes
  mean_raster.attrs.update({
    'description': f'Mean of {count} rasters',
    'input_files': list(map(str, inputs)),
    'long_name': long_name,
    'processing_date': shared.timestamp(),
  })
  
  # write to disk
  logger.info(f'Saving mean raster... {output}')
  mean_raster.rio.to_raster(output, compress='lzw')  # LZW compression to reduce file size
  
