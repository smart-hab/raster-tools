import logging
import pathlib
import smart_hab.shared as shared

def about(
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
      print(f'\nBounds: {shared.rio(raster).bounds()}')
      print(f'\n{raster.coords}')
      print(f'\nCRS: {shared.rio(raster).crs}')
      print(f'\nDimensions: {raster.dims}')
      print(f'\nDtype: {raster.dtype}')
      print(f'\nNoData: {shared.rio(raster).nodata}')
      print(f'\nPixels: {raster.size}')
      print(f'\nResolution: {shared.rio(raster).resolution()}')
      print(f'\nShape: {raster.shape}')
      print(f'\nSize: {raster.nbytes / (1024 * 1024):.2f} MB')
      print('\nTransform:')
      print(shared.rio(raster).transform())
      exit(0)

    # unsupported file format
    case _:
      raise RuntimeError(f'Unsupported file format: {input.suffix}')
