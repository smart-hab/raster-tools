import argparse
import os
import pathlib
import smart_hab.shared as shared

def about():
  import smart_hab.about as _about
  p = argparse.ArgumentParser(prog='info', description='Display raster or shape file info')
  p.add_argument('-i', '--input', help='Source raster or shape path', required=True)
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  logger = shared.setup_logger('about', args.verbose)
  _about.about(
    input=pathlib.Path(args.cwd) / args.input,
    logger=logger,
  )

def clip():
  import smart_hab.clip as _clip
  p = argparse.ArgumentParser(prog='clip', description='Clip raster with shape file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-s', '--shape', help='Source shape path', required=True)
  p.add_argument('-o', '--output', help='Destination raster path')
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)')
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  shape = pathlib.Path(args.cwd) / args.shape
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_clipped.tif'
  logger = shared.setup_logger('clip', args.verbose)
  _clip.clip(
    input=input,
    shape=shape,
    output=output,
    crs=args.crs,
    logger=logger,
  )

def convert_shape():
  import smart_hab.convert_shape as _convert_shape
  p = argparse.ArgumentParser(prog='convert_shape', description='Convert Esri/Fiona/Pyogrio shape file to GeoJSON')
  p.add_argument('-i', '--input', help='Source shape path', required=True)
  p.add_argument('-o', '--output', help='Output GeoJSON path')
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)', default='EPSG:4326')
  p.add_argument('-f', '--format', help='Output format', default='geojson', choices=['geojson'])
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  output = pathlib.Path(args.cwd) / args.output if args.output else input.with_suffix(args.format)
  logger = shared.setup_logger('convert_shape', args.verbose)
  if (output.suffix != '.geojson'):
    raise RuntimeError(f'Unsupported output format: {args.format}')
  _convert_shape.convert_shape(
    input=input,
    output=output,
    crs=args.crs,
    logger=logger,
  )

def kmeans_classify():
  import smart_hab.kmeans_classify as _kmeans_classify
  p = argparse.ArgumentParser(prog='kmeans_classify', description='Assign K-Means clusters classes to a raster band')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-k', '--clusters', help='Cluster centers path (from kmeans_fit)', required=True)
  p.add_argument('-o', '--output', help='Raster destination path', required=True)
  p.add_argument('-b', '--band', help='Band selection', type=int)
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  clusters = pathlib.Path(args.cwd) / args.clusters
  output = pathlib.Path(args.cwd) / args.output
  logger = shared.setup_logger('kmeans_classify', args.verbose)
  _kmeans_classify.kmeans_classify(
    input=input,
    clusters=clusters,
    output=output,
    band=args.band,
    logger=logger,
  )
  
def kmeans_fit():
  import smart_hab.kmeans_fit as _kmeans_fit
  p = argparse.ArgumentParser(prog='kmeans_fit', description='Fit K-Means clusters to a single band of one or more input rasters')
  p.add_argument('-i', '--input', nargs='+', help='Raster source path(s)', required=True)
  p.add_argument('-o', '--output', help='Clusters destination path', required=True)
  p.add_argument('-b', '--band', help='Band selection', type=int)
  p.add_argument('-c', '--clusters', help='Number of clusters', type=int)
  p.add_argument('-t', '--times', help='Number of times to run K-Means', type=int)
  p.add_argument('-r', '--random', help='Random state for K-Means', type=int)
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input = [pathlib.Path(args.cwd) / p for p in args.input]
  output = pathlib.Path(args.cwd) / args.output
  logger = shared.setup_logger('kmeans_fit', args.verbose)
  return _kmeans_fit.kmeans_fit(
    input=input,
    output=output,
    band=args.band,
    clusters=args.clusters,
    times=args.times,
    random=args.random,
    logger=logger,
  )

def mask():
  import smart_hab.mask as _mask
  p = argparse.ArgumentParser(prog='mask', description='Mask raster with UDM2 file')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-u', '--udm2', help='Source UDM2 path', required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)')
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int, default=[3, 6])
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  udm2 = pathlib.Path(args.cwd) / args.udm2
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_masked.tif'
  logger = shared.setup_logger('mask', args.verbose)
  _mask.mask(
    input=input,
    udm2=udm2,
    output=output,
    crs=args.crs,
    bands=args.bands,
    logger=logger,
  )

def means():
  import smart_hab.means as _means
  from rasterio.enums import Resampling
  p = argparse.ArgumentParser(prog='means', description='Compute mean raster from multiple input rasters')
  p.add_argument('-i', '--input', nargs='+', help='Input raster path(s)', required=True)
  p.add_argument('-o', '--output', help='Output raster path', required=True)
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int)
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)')
  p.add_argument('-r', '--resampling', help='Resampling method', default='bilinear', choices=[e.name for e in Resampling])
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  input_paths = [pathlib.Path(args.cwd) / p for p in args.input]
  output_path = pathlib.Path(args.cwd) / args.output
  logger = shared.setup_logger('means', args.verbose)
  resampling = getattr(Resampling, args.resampling.lower())
  _means.means(
    inputs=input_paths,
    output=output_path,
    bands=args.bands,
    crs=args.crs,
    logger=logger,
    resampling=resampling,
  )

def plot():
  import smart_hab.plot as _plot
  # parser
  p = argparse.ArgumentParser(prog='plot', description='Plot raster to PNG')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination image path')
  # parser mode
  g = p.add_mutually_exclusive_group()
  g.add_argument('-g', '--grayscale', metavar='BAND', dest='bands', nargs=1, type=int, help='Plot grayscale image', default=[1])
  g.add_argument('-r', '--rgb', metavar='BAND', dest='bands', nargs=3, type=int, help='Plot RGB image')
  p.add_argument_group(g)
  # parser extras
  o = p.add_argument_group(description='Extra arguments')
  o.add_argument('-a', '--alpha', help='Alpha transparency for NoData values', type=float, default=0.0)
  o.add_argument('-f', '--filter', metavar=('LOW', 'HIGH'), help='Robust normalization percentile filter', type=float, nargs=2, default=[0.5, 99.5])
  o.add_argument('-d', '--dpi', help='Plot resolution', type=int, default=300)
  o.add_argument('-c', '--cmap', help='Plot color map for grayscale images', default='viridis')
  o.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  o.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument_group(o)
  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}.png'
  logger = shared.setup_logger('plot', args.verbose)
  if len(args.bands) not in (1, 3):
    raise ValueError(f'Invalid band selection: {args.bands}. Must be 1 or 3 bands.')
  _plot.plot(
    input=input,
    output=output,
    bands=tuple(args.bands),
    alpha=args.alpha,
    filter=(args.filter[0], args.filter[1]),
    dpi=args.dpi,
    cmap=args.cmap,
    logger=logger,
  )

def norm_diff():
  import smart_hab.norm_diff as _norm_diff
  NDCI = [7,6] # NDCI = (Red Edge, Red)
  NDVI = [8,6] # NDVI = (NIR, RED) 
  p = argparse.ArgumentParser(prog='norm_diff', description='Normalize difference between two bands')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-b', '--bands', help='Band selection', nargs=2, type=int, required=True)
  p.add_argument('-o', '--output', help='Output raster path')
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)')
  p.add_argument('-f', '--filter', metavar=('LOW', 'HIGH'), help='Robust normalization percentile filter', type=float, nargs=2, default=[1.0, 99.0])
  p.add_argument('-d', '--dtype', help='Output data type', choices=shared.dtypes, default='uint16')
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument('--ndci', help='Calculate NDCI', dest='bands', action='store_const', const=NDCI)
  p.add_argument('--ndvi', help='Calculate NDVI', dest='bands', action='store_const', const=NDVI)
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  new_name = 'norm_diff'
  if args.bands == NDCI: new_name = 'ndci'
  if args.bands == NDVI: new_name = 'ndvi'
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}_{new_name}.tif'
  _norm_diff.norm_diff(
    input=input,
    bands=(args.bands[0], args.bands[1]),
    new_name=new_name,
    output=output,
    crs=args.crs,
    filter=(args.filter[0], args.filter[1]),
    dtype=args.dtype,
    logger = shared.setup_logger('norm_diff', args.verbose)
  )

def select_bands():
  import smart_hab.select_bands as _select_bands
  args = _select_bands.parse_args()
  _select_bands.select_bands(args)

def subtract():
  import smart_hab.subtract as _subtract
  from rasterio.enums import Resampling
  p = argparse.ArgumentParser(prog='subtract', description='Subtract one raster from another')
  p.add_argument('-i', '--input', nargs=2, help='Source raster paths', required=True)
  p.add_argument('-o', '--output', help='Output raster path', required=True)
  p.add_argument('-b', '--bands', help='Band selection', nargs='+', type=int)
  p.add_argument('-c', '--crs', help='Target CRS (e.g. EPSG:4326)')
  p.add_argument('-r', '--resampling', help='Resampling method', default='bilinear', choices=[e.name for e in Resampling])
  p.add_argument('-v', '--verbose', help='Display extra information', action='store_true', default=False)
  p.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  args = p.parse_args()
  inputs = (
    pathlib.Path(args.cwd) / args.input[0],
    pathlib.Path(args.cwd) / args.input[1],
  )
  output = pathlib.Path(args.cwd) / args.output
  logger = shared.setup_logger('subtract', args.verbose)
  resampling = getattr(Resampling, args.resampling.lower())
  _subtract.subtract(
    inputs=inputs,
    output=output,
    bands=args.bands,
    crs=args.crs,
    logger=logger,
    resampling=resampling,
  )
