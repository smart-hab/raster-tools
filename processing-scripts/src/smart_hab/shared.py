import logging
import sys
import geopandas
import rioxarray
import re

def setup_logger(name, verbose):
  logger = logging.getLogger(name)
  if verbose:
    logger.setLevel(logging.DEBUG)
  else:
    logger.setLevel(logging.WARNING)
  handler = logging.StreamHandler(sys.stderr)
  formatter = logging.Formatter("[%(levelname)s] %(message)s")
  handler.setFormatter(formatter)
  logger.addHandler(handler)
  return logger

def get_date(filename):
  m = re.search(r"-(\d{8})-", filename)
  if not m: return None
  return m.group(1)

def load_shape(shape_path, crs=None):
  try:
    shape = geopandas.read_file(shape_path)
    if crs and shape.crs != crs:
      shape = shape.to_crs(crs)
    return shape
  except:
    raise RuntimeError(f"Could not read shape file: {shape_path}")
  
def load_raster(raster_path, crs=None):
  try:
    ras = rioxarray.open_rasterio(raster_path)
    if crs and ras.rio.crs != crs:
      ras = ras.rio.reproject(crs)
    return ras
  except:
    raise RuntimeError(f"Could not read raster file: {raster_path}")

def raster_bands(raster):
  if not "band" in raster.coords:
    raise RuntimeError("No bands found in raster")
  values = raster.coords["band"].values
  names = raster.attrs.get("long_name", None)
  dict = { b: name for (b, name) in zip(values, names)}
  return dict

# def raster_bands(raster):
#   if not "band" in raster.coords:
#     raise RuntimeError("No bands found in raster")
#   values = raster.coords["band"].values
#   names = raster.attrs.get("long_name", [f"band_{b}" for b in values])
#   band_dict = {} 
#   try:
#     for v in values:
#       print("selecting", v)
#       band_dict[v] = names[v - 1]
#   except IndexError as e:
#     raise RuntimeError("Invalid band selection") from e
#   return band_dict

def raster_norm_diff(raster, band1, band2):
  a = raster.sel(band=band1)
  b = raster.sel(band=band2)
  diff = (a - b) / (a + b)
  return diff

# def raster_save_png(raster, bands, png_path, cmap="viridis", width=10, height=10, dpi=300):
#   match len(bands):
#     case 1:
#       dataset = raster.sel(band=bands[0]).squeeze()
#       fig, ax = plt.subplots(figsize=(width, height))
#       dataset.plot.imshow(cmap=cmap, ax=ax)
#       ax.set_axis_off()
#       plt.savefig(png_path, bbox_inches="tight", dpi=dpi)
#       plt.close()
#     case 3:
#       dataset = raster.sel(band=bands)
#       fig, ax = plt.subplots(figsize=(width, height))
#       dataset.plot.imshow(rgb="band", ax=ax)
#       ax.set_axis_off()
#       plt.savefig(png_path, bbox_inches="tight", dpi=dpi)
#       plt.close()
#     case _:
#       raise RuntimeError("Invalid number of bands")
  
  
