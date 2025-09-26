import logging
import pathlib
import rasterio
import smart_hab.shared as shared

def mask(
  input: pathlib.Path,
  udm2: pathlib.Path,
  output: pathlib.Path,
  crs: str | None,
  bands: list[int],
  logger: logging.Logger,
) -> None:
  
  # load mask
  logger.info(f'Loading UDM2... {udm2}')
  raster_udm = shared.load_raster(udm2, crs)
  udm_bands = shared.raster_bands(raster_udm)

  # load raster
  logger.info(f'Loading raster... {input}')
  raster_sat = shared.load_raster(input, crs)

  # mask
  for band in bands:
    band_name = udm_bands[band]
    if not band_name:
      raise RuntimeError(f'Band {band} not found in raster')
    logger.info(f'Masking band {band_name}...')
    raster_sat = raster_sat.where(~raster_udm.sel(band=band).astype(bool))

  # save
  logger.info(f'Saving masked raster... {output}')
  shared.rio(raster_sat).to_raster(output, dtype=rasterio.uint16, compress='lzw')

  # done
  logger.info('Done')
