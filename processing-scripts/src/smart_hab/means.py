import logging
import pathlib
import typing

import rioxarray
import xarray
from rasterio.enums import Resampling

from . import shared


def means(
    input: typing.Sequence[pathlib.Path | typing.BinaryIO],
    output: pathlib.Path,
    bands: list[int] | None,
    crs: str | None,
    logger: logging.Logger,
    resampling: Resampling,
) -> None:
    # invariant
    count = len(input)
    assert count > 1, "At least two input rasters are required to compute the mean."

    # load rasters
    rasters: list[xarray.DataArray] = []
    for i, file in enumerate(input):
        try:
            logger.info(f"Loading raster {i + 1}/{count}... {file}")
            r = rioxarray.open_rasterio(file)
        except Exception as e:
            raise RuntimeError(f"Could not read raster file: {file}") from e
        if not isinstance(r, xarray.DataArray):
            raise RuntimeError(f"Raster does not contain DataArray: {file}")
        if not crs:
            logger.info(f"Target CRS set to first raster: {shared.rio(r).crs}")
            crs = shared.rio(r).crs
        if shared.rio(r).crs != crs:
            logger.info(f"Reprojecting CRS... {shared.rio(r).crs} -> {crs}")
            r = shared.rio(r).reproject(crs, resampling=resampling)
        if bands:
            r = r.sel(band=bands)
        rasters.append(r)

    # intersection
    logger.info("Computing spatial intersection...")
    bounds_list = [shared.rio(r).bounds() for r in rasters]

    intersection = (
        max(b[0] for b in bounds_list),  # left (minx)
        max(b[1] for b in bounds_list),  # bottom (miny)
        min(b[2] for b in bounds_list),  # right (maxx)
        min(b[3] for b in bounds_list),  # top (maxy)
    )

    valid_intersection = intersection[0] < intersection[2] and intersection[1] < intersection[3]
    assert valid_intersection, "No spatial overlap found between input rasters!"

    # clip to intersection
    for i, r in enumerate(rasters):
        logger.info(f"Clipping raster {i + 1}/{count}...")
        rasters[i] = shared.rio(r).clip_box(*intersection)

    # align
    logger.info(f"Aligning raster 1/{count}...")  # first raster is reference
    for i, r in enumerate(rasters[1:], start=1):
        logger.info(f"Aligning raster {i + 1}/{count}...")
        rasters[i] = shared.rio(r).reproject_match(rasters[0], resampling=resampling)

    # stack and compute mean
    stacked = xarray.concat(rasters, dim="raster")
    mean_raster = stacked.mean(dim="raster", skipna=True)

    # determine new band names
    try:
        long_name = typing.cast(tuple[str, ...] | None, rasters[0].attrs.get("long_name", None))
        bands = typing.cast(list[int], rasters[0].coords["band"].values)
        if long_name and len(long_name) == len(bands):
            selection = set(bands)
            long_name = tuple(name for (band, name) in zip(bands, long_name) if band in selection)
    except Exception:
        long_name = None

    # update attributes
    mean_raster.attrs.update(
        {
            "description": f"Mean of {count} rasters",
            "input_files": list(map(str, input)),
            "long_name": long_name,
            "processing_date": shared.timestamp(),
        }
    )

    # write to disk
    logger.info(f"Saving mean raster... {output}")
    shared.rio(mean_raster).to_raster(output, compress="lzw")
