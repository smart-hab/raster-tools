import logging
import pathlib
import rasterio
import smart_hab.shared as shared

def clip( 
  input: pathlib.Path,
  shape: pathlib.Path,
  output: pathlib.Path,
  crs: str | None,
  logger: logging.Logger,
) -> None:

  # load shape
  logger.info(f'Loading shape... {shape}')
  shape_data = shared.load_shape(shape, crs)

  # load raster
  logger.info(f'Loading raster... {input}')
  raster = shared.load_raster(input, crs)

  # clip
  logger.info(f'Clipping...')
  raster = raster.rio.clip(shape_data.geometry, crs)

  # output
  logger.info(f'Saving clipped raster... {output}')
  raster.rio.to_raster(output, dtype=rasterio.uint16, compress='lzw')

  # done
  logger.info('Done')
