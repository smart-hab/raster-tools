import argparse
import matplotlib.pyplot as plt
import numpy
import os
import pathlib
import smart_hab.shared as shared
import typing

class Args(typing.NamedTuple):
  input: pathlib.Path
  output: pathlib.Path
  bands: list[int]
  alpha: float
  filter: tuple[float, float]
  dpi: int
  cmap: str
  verbose: bool

def parse_args() -> Args:
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
  o.add_argument('-v', '--verbose', help='Show extra information', action='store_true', default=False)
  o.add_argument('-w', '--cwd', help='Working directory', default=os.getcwd())
  p.add_argument_group(o)
  # args
  args = p.parse_args()
  input = pathlib.Path(args.cwd) / args.input
  output = pathlib.Path(args.cwd) / args.output if args.output else input.parent / f'{input.stem}.png'
  return Args(
    input=input,
    output=output,
    bands=args.bands,
    alpha=args.alpha,
    filter=(args.filter[0], args.filter[1]),
    dpi=args.dpi,
    cmap=args.cmap,
    verbose=args.verbose,
  )

def main(args: Args) -> None:  

  # logger
  logger = shared.setup_logger('plot', args.verbose)

  # load raster
  logger.info(f'Loading raster... {args.input}')
  raster = shared.load_raster(args.input)
  raster_bands = shared.raster_bands(raster)

  # plot
  match len(args.bands):

    # plot grayscale
    case 1:
      band_name = raster_bands.get(args.bands[0], str(args.bands[0]))
      logger.info(f'Selecting band... {band_name}')
      # select band
      gray = raster.sel(band=args.bands[0]).squeeze()
      # normalize
      gray = shared.raster_robust_norm(gray, low=args.filter[0], high=args.filter[1])
      # plot
      width = round(raster.sizes['x'] / args.dpi, 2)
      height = round(raster.sizes['y'] / args.dpi, 2)
      logger.info(f'Plotting grayscale image ... {band_name} {width}x{height}@{args.dpi} {args.cmap}')
      fig, ax = plt.subplots(figsize=(width, height))
      plt.title(f'{args.input.name} ({band_name})', fontsize=6)
      ax.set_axis_off()
      # color map axis
      im = ax.imshow(gray, cmap=args.cmap)
      fig.colorbar(im, ax=ax, fraction=0.05)
      # save
      logger.info(f'Saving image... {args.output}')
      plt.savefig(args.output, bbox_inches='tight', dpi=args.dpi)
      plt.close()
      
    # plot RGB
    case 3:
      band_name = tuple(raster_bands.get(b, str(b)) for b in args.bands)
      logger.info(f'Selecting band... {band_name}')
      # select bands
      vr = raster.sel(band=args.bands[0]).squeeze()
      vg = raster.sel(band=args.bands[1]).squeeze()
      vb = raster.sel(band=args.bands[2]).squeeze()
      # normalize
      nr = shared.raster_robust_norm(vr, low=args.filter[0], high=args.filter[1])
      ng = shared.raster_robust_norm(vg, low=args.filter[0], high=args.filter[1])
      nb = shared.raster_robust_norm(vb, low=args.filter[0], high=args.filter[1])
      # stack
      rgb = numpy.stack([nr, ng, nb], axis=-1)
      # alpha
      nodata = (nr == 0) | (ng == 0) | (nb == 0)
      alpha = numpy.where(nodata, args.alpha, 1.0)
      # plot
      width = round(raster.sizes['x'] / args.dpi, 2)
      height = round(raster.sizes['y'] / args.dpi, 2)
      logger.info(f'Plotting true color image ... {band_name} {width}x{height}@{args.dpi} {args.cmap}')
      fig, ax = plt.subplots(figsize=(width, height))
      plt.title(f'{args.input.name} ({', '.join(band_name)})', fontsize=6)
      ax.set_axis_off()
      plt.imshow(rgb, alpha=alpha)
      # save
      logger.info(f'Saving image... {args.output}')
      plt.savefig(args.output, bbox_inches='tight', dpi=args.dpi)
      plt.close()

    # invalid band selection
    case _:
      raise ValueError(f'Invalid band selection: {args.bands}. Must be 1 or 3 bands.')
    
  # done
  logger.info(f'Done')
