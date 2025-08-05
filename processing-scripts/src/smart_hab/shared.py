import geopandas
import logging
import numpy
import re
import rioxarray
import sys
import typing

Dtype = typing.Literal['int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64']

dtypes = ['int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64']

def setup_logger(name, verbose=False):
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

def get_date(filename):
  m = re.search(r'-(\d{8})-', filename)
  if not m: return None
  return m.group(1)

def load_shape(shape_path, crs=None):
  try:
    shape = geopandas.read_file(shape_path)
    if crs and shape.crs != crs:
      shape = shape.to_crs(crs)
    return shape
  except:
    raise RuntimeError(f'Could not read shape file: {shape_path}')
  
def load_raster(raster_path, crs=None):
  try:
    ras = rioxarray.open_rasterio(raster_path)
    if crs and ras.rio.crs != crs:
      ras = ras.rio.reproject(crs)
    return ras
  except:
    raise RuntimeError(f'Could not read raster file: {raster_path}')

def raster_bands(raster):
  if not 'band' in raster.coords:
    raise RuntimeError('No bands found in raster')
  values = raster.coords['band'].values
  names = raster.attrs.get('long_name', [f'band_{b}' for b in values])
  dict = { b: name for (b, name) in zip(values, names)}
  return dict
  
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
#     raise RuntimeError('Invalid band selection') from e
#   return band_dict

def raster_norm_diff(raster, band1, band2, epsilon=1e-10):
  v1 = raster.sel(band=band1)
  v2 = raster.sel(band=band2)
  if v1.shape != v2.shape:
    raise ValueError('Input bands must have the same shape.')
  norm_diff = (v1 - v2) / (v1 + v2 + epsilon)
  return norm_diff

def raster_robust_norm(raster, low=0, high=100):
  valid = numpy.isfinite(raster.values)
  vmin, vmax = numpy.percentile(raster.values[valid], [low, high])
  raster = numpy.clip(raster, vmin, vmax)
  norm = (raster - vmin) / (vmax - vmin)
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

def raster_scale(scaled, dtype: Dtype):
  dtype = getattr(numpy, dtype)
  scale = numpy.iinfo(dtype).max
  scaled = scaled * scale
  return scaled
