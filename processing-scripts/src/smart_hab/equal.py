import logging
import pathlib
import typing

import numpy

from . import shared


def equal(
    input: tuple[pathlib.Path | typing.BinaryIO, pathlib.Path | typing.BinaryIO],
    bands: list[int] | None,
    data_only: bool,
    logger: logging.Logger,
) -> bool:
    """Compare two rasters. Returns True when they match, False on the first difference found."""

    # load rasters
    logger.info(f"Loading base raster... {input[0]}")
    src1 = shared.load_raster(input[0])
    logger.info(f"Loading comparison raster... {input[1]}")
    src2 = shared.load_raster(input[1])

    # shape check
    if src1.shape != src2.shape:
        logger.error(f"raster shape mismatch: {src1.shape} != {src2.shape}")
        return False

    # geoawareness checks
    if not data_only:
        rio1 = shared.rio(src1)
        rio2 = shared.rio(src2)

        # compare crs
        crs1 = str(rio1.crs)
        crs2 = str(rio2.crs)
        if crs1 != crs2:
            logger.error(f"raster CRS mismatch: {crs1} != {crs2}")
            return False

        # compare transforms
        transform1 = tuple(rio1.transform())
        transform2 = tuple(rio2.transform())
        if transform1 != transform2:
            logger.error(f"raster transforms mismatch: {transform1} != {transform2}")
            return False

    # compare bands
    if not bands:
        bands = list(shared.raster_bands(src1).keys())
    for band in bands:
        arr1 = src1.sel(band=band).values
        arr2 = src2.sel(band=band).values
        if not numpy.array_equal(arr1, arr2):
            logger.error(f"raster data mismatch in band {band}")
            return False

    # all checks passed
    logger.info("rasters are equal")
    return True
