import argparse
import geopandas as gpd
import rasterio
import sys
import json
import pathlib

def parse_args():
  p = argparse.ArgumentParser(prog='convert_shape', description='Convert Esri/Fiona/Pyogrio shape file to GeoJSON')
  p.add_argument('shape', help='Shape file path')
  p.add_argument('-a', '--auto', help='Automatically output to <filename.format>', default=False, action='store_true')
  p.add_argument('-c', '--crs', help='Output CRS', default='EPSG:4326')
  p.add_argument('-f', '--format', help='Output format', default='geojson', choices=['geojson'])
  p.add_argument('-v', '--verbose', help='Display information during conversion', default=False, action='store_true')
  p.add_argument('-w', '--cwd', help='Working directory', default='.')
  return p.parse_args()

# run
def main(args):
  # src
  src = pathlib.Path(args.cwd) / args.shape

  # format
  if (args.format != 'geojson'):
    raise RuntimeError(f'Unsupported output format: {args.format}')

  # crs
  try:
    target = rasterio.CRS.from_string(args.crs)
  except:
    raise RuntimeError(f'Coult not set target CRS: {args.crs}')

  # shape
  try:
    oldshape = gpd.read_file(src)
  except:
    raise RuntimeError(f'Could not read shape file: {src}')

  # conversion
  if (oldshape.crs != target):
    conversion = f'{oldshape.crs} -> {target}'
    oldshape.to_crs(target, inplace=True)
  else:
    conversion = f'{oldshape.crs}'
  
  # newshape
  try:
    newshape = json.loads(oldshape.to_json())
  except:
    raise RuntimeError(f'Could not read geometry coordinates of dataframe')
  
  # geojson
  geojson = json.dumps(newshape)
  
  # auto output
  if (args.auto):
    try:
      dest = pathlib.Path(src).with_suffix(f'.{args.format}')
      if (args.verbose): print(f'{src} -> {dest} [{conversion}]', file=sys.stderr)
      with open(dest, 'w') as file:
        file.write(geojson)
    except:
      raise RuntimeError(f'Could not write to file: {dest}')

  # stdout
  else:
    if (args.verbose): print(f'{src} [{conversion}]', file=sys.stderr)
    print(geojson, end=None)
