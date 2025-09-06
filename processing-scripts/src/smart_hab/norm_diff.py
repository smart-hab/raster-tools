import logging
import pathlib
import smart_hab.shared as shared

def norm_diff(
  input: pathlib.Path,
  bands: tuple[int, int],
  new_name: str,
  output: pathlib.Path,
  crs: str | None,
  filter: tuple[float, float],
  dtype: shared.Dtype,
  logger: logging.Logger,
) -> None:

  # load raster
  logger.info(f'Loading raster... {input}')
  raster = shared.load_raster(input, crs)
  raster_bands = shared.raster_bands(raster)

  # band selection
  band_names = tuple(raster_bands.get(b, str(b)) for b in bands)

  # normalized difference
  logger.info(f'Calculating normalized difference... {band_names}')
  raster = shared.raster_norm_diff(raster, bands[0], bands[1])

  # robust normalization
  logger.info(f'Removing outlier values below {filter[0]} and above {filter[1]} percentile...')
  raster = shared.raster_robust_norm(raster, low=filter[0], high=filter[1])

  # scale
  logger.info(f'Scaling raster to {dtype}...')
  raster = shared.raster_scale(raster, dtype=dtype)

  # set attributes
  raster.attrs['long_name'] = (new_name,)

  # output
  logger.info(f'Saving {dtype} raster... {output}')
  raster.rio.to_raster(output, dtype=dtype, compress='lzw')

  # done
  logger.info('Done')
