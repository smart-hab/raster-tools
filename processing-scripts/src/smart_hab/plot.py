from . import shared
import logging
import numpy
import matplotlib.pyplot as plt
import pathlib
import typing


def plot1(
    input: pathlib.Path | typing.BinaryIO,
    output: pathlib.Path,
    band: int,
    alpha: float,
    filter: tuple[float, float],
    dpi: int,
    cmap: str,
    logger: logging.Logger,
) -> None:
    # load raster
    logger.info(f"Loading raster... {input}")
    raster = shared.load_raster(input)
    raster_bands = shared.raster_bands(raster)

    # plot
    band_name = raster_bands.get(band, str(band))
    logger.info(f"Selecting band... {band_name}")
    # select band
    gray = raster.sel(band=band).squeeze()
    # normalize
    gray = shared.raster_robust_norm(gray, low=filter[0], high=filter[1])
    # plot
    width = round(raster.sizes["x"] / dpi, 2)
    height = round(raster.sizes["y"] / dpi, 2)
    logger.info(f"Plotting grayscale image ... {band_name} {width}x{height}@{dpi} {cmap}")
    fig, ax = plt.subplots(figsize=(width, height))
    plt.title(f"{input.name} ({band_name})", fontsize=6)
    ax.set_axis_off()
    # color map axis
    im = ax.imshow(gray, cmap=cmap)
    fig.colorbar(im, ax=ax, fraction=0.05)
    # save
    logger.info(f"Saving image... {output}")
    plt.savefig(output, bbox_inches="tight", dpi=dpi)
    plt.close()

    # done
    logger.info("Done")


def plot3(
    input: pathlib.Path | typing.BinaryIO,
    output: pathlib.Path,
    bands: tuple[int, int, int],
    alpha: float,
    filter: tuple[float, float],
    dpi: int,
    cmap: str,
    logger: logging.Logger,
) -> None:
    # load raster
    logger.info(f"Loading raster... {input}")
    raster = shared.load_raster(input)
    raster_bands = shared.raster_bands(raster)

    # plot
    band_name = tuple(raster_bands.get(b, str(b)) for b in bands)
    logger.info(f"Selecting band... {band_name}")
    # select bands
    vr = raster.sel(band=bands[0]).squeeze()
    vg = raster.sel(band=bands[1]).squeeze()
    vb = raster.sel(band=bands[2]).squeeze()
    # normalize
    nr = shared.raster_robust_norm(vr, low=filter[0], high=filter[1])
    ng = shared.raster_robust_norm(vg, low=filter[0], high=filter[1])
    nb = shared.raster_robust_norm(vb, low=filter[0], high=filter[1])
    # stack
    rgb = numpy.stack([nr, ng, nb], axis=-1)
    # alpha
    nodata = (nr == 0) | (ng == 0) | (nb == 0)
    alphadata = numpy.where(nodata, alpha, 1.0)
    # plot
    width = round(raster.sizes["x"] / dpi, 2)
    height = round(raster.sizes["y"] / dpi, 2)
    logger.info(f"Plotting true color image ... {band_name} {width}x{height}@{dpi} {cmap}")
    fig, ax = plt.subplots(figsize=(width, height))
    plt.title(f"{input.name} ({', '.join(band_name)})", fontsize=6)
    ax.set_axis_off()
    plt.imshow(rgb, alpha=alphadata)
    # save
    logger.info(f"Saving image... {output}")
    plt.savefig(output, bbox_inches="tight", dpi=dpi)
    plt.close()

    # done
    logger.info("Done")
