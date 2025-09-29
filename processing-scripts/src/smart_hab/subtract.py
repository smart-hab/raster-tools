import logging
import pathlib
import typing

import rioxarray
import xarray
from rasterio.enums import Resampling

from . import shared


def subtract(
    input: tuple[pathlib.Path | typing.BinaryIO, pathlib.Path | typing.BinaryIO],
    output: pathlib.Path,
    bands: list[int] | None,
    crs: str | None,
    logger: logging.Logger,
    resampling: Resampling,
) -> None:
    # load first raster
    try:
        logger.info(f"Loading base raster... {input[0]}")
        r1 = rioxarray.open_rasterio(input[0])
    except Exception as e:
        raise RuntimeError(f"Could not read raster file: {input[0]}") from e
    if not isinstance(r1, xarray.DataArray):
        raise RuntimeError(f"Raster does not contain DataArray: {input[0]}")
    if not crs:
        logger.info(f"Target CRS set to: {shared.rio(r1).crs}")
        crs = shared.rio(r1).crs
    if shared.rio(r1).crs != crs:
        logger.info(f"Reprojecting CRS... {shared.rio(r1).crs} -> {crs}")
        r1 = shared.rio(r1).reproject(crs, resampling=resampling)
    if bands:
        r1 = r1.sel(band=bands)

    # load second raster
    try:
        logger.info(f"Loading subtraction raster... {input[1]}")
        r2 = rioxarray.open_rasterio(input[1])
    except Exception as e:
        raise RuntimeError(f"Could not read raster file: {input[1]}") from e
    if not isinstance(r2, xarray.DataArray):
        raise RuntimeError(f"Raster does not contain DataArray: {input[1]}")
    if shared.rio(r2).crs != crs:
        logger.info(f"Reprojecting CRS... {shared.rio(r2).crs} -> {crs}")
        r2 = shared.rio(r2).reproject(crs, resampling=resampling)
    if bands:
        r2 = r2.sel(band=bands)

    # align
    logger.info("Aligning rasters...")
    r2 = shared.rio(r2).reproject_match(r1, resampling=resampling)

    # subtract
    logger.info("Subtracting rasters...")
    diff_raster = r1 - r2

    # determine new band names
    try:
        long_name = typing.cast(tuple[str, ...] | None, r1.attrs.get("long_name", None))
        bands = typing.cast(list[int], r1.coords["band"].values)
        if long_name and len(long_name) == len(bands):
            selection = set(bands)
            long_name = tuple(name for (band, name) in zip(bands, long_name) if band in selection)
    except Exception:
        long_name = None

    # update attributes
    diff_raster.attrs.update(
        {
            "description": f"Computed difference between {input[0].name} and {input[1].name}",
            "input_files": list(map(str, input)),
            "long_name": long_name,
            "processing_date": shared.timestamp(),
        }
    )

    # write to disk
    logger.info(f"Saving difference raster... {output}")
    shared.rio(diff_raster).to_raster(output, compress="lzw")
