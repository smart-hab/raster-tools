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

  # load raster
  logger.info(f'Loading raster... {input}')
  raster = shared.load_raster(input, crs)

  # load shape, using input raster CRS
  logger.info(f'Loading shape... {shape}')
  shape_data = shared.load_shape(shape, shared.rio(raster).crs)

  # clip
  logger.info(f'Clipping...')
  raster = shared.rio(raster).clip(shape_data.geometry)

  # output
  logger.info(f'Saving clipped raster... {output}')
  shared.rio(raster).to_raster(output, dtype=rasterio.uint16, compress='lzw')

  # done
  logger.info('Done')
