import logging
import pathlib
import smart_hab.shared as shared

def main(
  input: pathlib.Path,
  logger: logging.Logger,
) -> None:

  match input.suffix:
    # shape file
    case '.shp' | '.geojson':
      logger.info(f'Loading shape... {input}')
      shape = shared.load_shape(input)
      print(f'\n\n[{input.name}]')
      print(f'\nCRS: {shape.crs}')
      print(f'\nBounds: {shape.bounds}')
      print(f'\nGeometry')
      print(shape.geometry.describe())
      exit(0)

    # raster file
    case '.tif' | '.tiff':
      logger.info(f'Loading raster... {input}')
      raster = shared.load_raster(input)
      print(f'\n\n[{input.name}]')
      print('\nAttributes:')
      for (key, value) in raster.attrs.items():
        print(f'  * {key:12} {value}')
      print('\nBands:')
      for (band, name) in shared.raster_bands(raster).items():
        print('  * {0:12} {1}'.format(f'Band {band}', name))
      print(f'\nBounds: {raster.rio.bounds()}')
      print(f'\n{raster.coords}')
      print(f'\nCRS: {raster.rio.crs}')
      print(f'\nDimensions: {raster.dims}')
      print(f'\nDtype: {raster.dtype}')
      print(f'\nNoData: {raster.rio.nodata}')
      print(f'\nPixels: {raster.size}')
      print(f'\nResolution: {raster.rio.resolution()}')
      print(f'\nShape: {raster.shape}')
      print(f'\nSize: {raster.nbytes / (1024 * 1024):.2f} MB')
      print('\nTransform:')
      print(raster.rio.transform())
      exit(0)

    # unsupported file format
    case _:
      raise RuntimeError(f'Unsupported file format: {input.suffix}')
