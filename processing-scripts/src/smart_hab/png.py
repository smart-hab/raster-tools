import argparse
import matplotlib.pyplot as plt
import os
import pathlib
import smart_hab.shared as shared

def parse_args():
  p = argparse.ArgumentParser(prog='png', description='Convert raster to PNG')
  p.add_argument('-i', '--input', help='Source raster path', required=True)
  p.add_argument('-o', '--output', help='Destination image path')

  g = p.add_mutually_exclusive_group()
  g.add_argument('-l', '--list', help='Show list of available bands', action='store_true')
  g.add_argument('-g', '--grayscale', metavar='BAND', help='Generate grayscale image', type=int, default=1)
  g.add_argument('-r', '--rgb', metavar='BAND', nargs=3, type=int, help='Generate RGB image')
  p.add_argument_group(g)

  o = p.add_argument_group(description='Extra arguments')
  o.add_argument('-s', '--size', metavar=('WIDTH', 'HEIGHT'), help='Plot size', type=int, nargs=2, default=[10, 10])
  o.add_argument('-d', '--dpi', help='Plot resolution', type=int, default=300)
  o.add_argument('-c', '--cmap', help='Plot color map for grayscale images', default='viridis')
  o.add_argument('-v', '--verbose', help='Show extra information', action='store_true', default=False)
  o.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument_group(o)
  return p.parse_args()

def main(args):  

  # logger
  logger = shared.setup_logger('png', args.verbose)

  # load raster
  args.input = pathlib.Path(args.cwd) / args.input
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input)
  raster_bands = shared.raster_bands(raster)

  # list and exit
  if args.list:
    for (band, name) in raster_bands.items():
      print(f"Band {band}: {name}")
    exit(0)

  # plot
  if args.rgb:
    band = args.rgb
    band_name = tuple(raster_bands.get(b, str(b)) for b in band)
  else:
    band = args.grayscale
    band_name = raster_bands.get(args.grayscale, str(args.grayscale))
  logger.info(f'Plotting band(s)... {band_name}')
  dataset = raster.sel(band=band)
  fig, ax = plt.subplots(figsize=(args.size[0], args.size[1]))
  ax.set_axis_off()
  dataset.plot.imshow(cmap=args.cmap, ax=ax)
  
  # output
  if not args.output:
    args.output = args.input.parent / f'{args.input.stem}.png'
  else:
    args.output = pathlib.Path(args.cwd) / args.output  
  try:
    logger.info(f'Saving PNG: {args.output}')
    plt.savefig(args.output, bbox_inches="tight", dpi=args.dpi)
    plt.close()
  except Exception as e:
    raise RuntimeError(f'Could not save image: {args.output}') from e

if __name__ == '__main__':
  args = parse_args()
  main(args)
