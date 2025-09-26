import datetime
import geopandas
import logging
import numpy
import os
import pathlib
import re
import rioxarray
import sys
import typing
import xarray

type Dtype = typing.Literal['int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64']

dtypes: list[Dtype] = ['int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64']

def setup_logger(name: str, verbose: bool = False) -> logging.Logger:
  logger = logging.getLogger(name)
  if verbose:
    logger.setLevel(logging.DEBUG)
  else:
    logger.setLevel(logging.WARNING)
  handler = logging.StreamHandler(sys.stderr)
  formatter = logging.Formatter('[%(levelname)s] %(message)s')
  handler.setFormatter(formatter)
  logger.addHandler(handler)
  return logger

def get_date(filename: str) -> typing.Optional[str]:
  m = re.search(r'-(\d{8})-', filename)
  if not m: return None
  return m.group(1)

def load_shape(shape_path: pathlib.Path, crs: typing.Optional[str] = None) -> geopandas.GeoDataFrame:
  try:
    shape = geopandas.read_file(shape_path)
  except Exception as e:
    raise RuntimeError(f'Could not read shape file: {shape_path}') from e
  if not isinstance(shape, geopandas.GeoDataFrame):
    raise RuntimeError(f'Shape does not contain GeoDataFrame: {shape_path}')
  if crs and shape.crs != crs:
    shape.to_crs(crs, inplace=True)
  return shape
  
def load_raster(raster_path: os.PathLike[str], crs: typing.Optional[str] = None) -> xarray.DataArray:
  try:
    ras = rioxarray.open_rasterio(raster_path)
  except Exception as e:
    raise RuntimeError(f'Could not read raster file: {raster_path}') from e
  if not isinstance(ras, xarray.DataArray):
    raise RuntimeError(f'Raster does not contain DataArray: {raster_path}')
  if crs and rio(ras).crs != crs:
    ras = rio(ras).reproject(crs)
  return ras

def raster_bands(raster: xarray.DataArray) -> dict[int, str]:
  assert 'band' in raster.coords, 'No bands found in raster'
  bands = list(map(int, raster.coords['band'].values))
  names = list(map(str, raster.attrs.get('long_name', []))) or list(f'band_{b}' for b in bands)
  return dict(zip(bands, names))
  
# def raster_bands(raster):
#   if not 'band' in raster.coords:
#     raise RuntimeError('No bands found in raster')
#   values = raster.coords['band'].values
#   names = raster.attrs.get('long_name', [f'band_{b}' for b in values])
#   band_dict = {} 
#   try:
#     for v in values:
#       print('selecting', v)
#       band_dict[v] = names[v - 1]
#   except IndexError as e:
#   return band_dict

def raster_norm_diff(raster: xarray.DataArray, band1: int, band2: int, epsilon: float = 1e-10) -> xarray.DataArray:
  v1 = raster.sel(band=band1)
  v2 = raster.sel(band=band2)
  if v1.shape != v2.shape:
    raise ValueError('Input bands must have the same shape.')
  norm_diff = (v1 - v2) / (v1 + v2 + epsilon)
  return norm_diff

def raster_robust_norm(raster: xarray.DataArray, low: float = 0, high: float = 100) -> xarray.DataArray:
  valid = numpy.isfinite(raster.values)
  vmin, vmax = typing.cast(tuple[float, float], numpy.percentile(raster.values[valid], [low, high]))
  clipped = typing.cast(xarray.DataArray, numpy.clip(raster, vmin, vmax))
  norm = (clipped - vmin) / (vmax - vmin)
  return norm

# def raster_save_png(raster, bands, png_path, cmap='viridis', width=10, height=10, dpi=300):
#   match len(bands):
#     case 1:
#       dataset = raster.sel(band=bands[0]).squeeze()
#       fig, ax = plt.subplots(figsize=(width, height))
#       dataset.plot.imshow(cmap=cmap, ax=ax)
#       ax.set_axis_off()
#       plt.savefig(png_path, bbox_inches='tight', dpi=dpi)
#       plt.close()
#     case 3:
#       dataset = raster.sel(band=bands)
#       fig, ax = plt.subplots(figsize=(width, height))
#       dataset.plot.imshow(rgb='band', ax=ax)
#       ax.set_axis_off()
#       plt.savefig(png_path, bbox_inches='tight', dpi=dpi)
#       plt.close()
#     case _:
#       raise RuntimeError('Invalid number of bands')

def raster_scale(raster: xarray.DataArray, dtype: Dtype) -> xarray.DataArray:
  scale = numpy.iinfo(dtype).max
  scaled = raster * scale
  return scaled

def rio(raster: xarray.DataArray) -> rioxarray.raster_array.RasterArray:
  value = getattr(raster, 'rio', None)
  if not isinstance(value, rioxarray.raster_array.RasterArray):
    raise RuntimeError('Raster is not a valid rioxarray RasterArray.')
  return value

def timestamp() -> str:
  return datetime.datetime.now(datetime.timezone.utc).isoformat()
