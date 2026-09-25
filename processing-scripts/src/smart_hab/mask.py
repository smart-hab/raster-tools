import logging
import pathlib
import typing

import rasterio
from rasterio.enums import Resampling

from . import shared


def mask(
    input: pathlib.Path | typing.BinaryIO,
    udm2: pathlib.Path | typing.BinaryIO,
    output: pathlib.Path,
    crs: str | None,
    bands: list[int],
    logger: logging.Logger,
) -> None:
    # load raster
    logger.info(f"Loading raster... {input}")
    raster_sat = shared.load_raster(input, crs)

    # load mask using input raster CRS
    logger.info(f"Loading UDM2... {udm2}")
    raster_udm = shared.load_raster(udm2, shared.rio(raster_sat).crs)
    udm_bands = shared.raster_bands(raster_udm)

    # align — Planet's UDM2 shares the raster's grid (the clipped raster is a window of it, which
    # xarray aligns by coordinate), but Sentinel-2's MSK_CLASSI is 60 m against a 10 m raster
    sat_rio, udm_rio = shared.rio(raster_sat), shared.rio(raster_udm)
    if udm_rio.resolution() != sat_rio.resolution():
        logger.info("Resampling mask onto raster grid...")
        raster_udm = udm_rio.reproject_match(raster_sat, resampling=Resampling.nearest)

    # mask
    for band in bands:
        band_name = udm_bands[band]
        if not band_name:
            raise RuntimeError(f"Band {band} not found in raster")
        logger.info(f"Masking band {band_name}...")
        raster_sat = raster_sat.where(~raster_udm.sel(band=band).astype(bool))

    # save
    logger.info(f"Saving masked raster... {output}")
    shared.rio(raster_sat).to_raster(output, dtype=rasterio.uint16, compress="lzw")

    # done
    logger.info("Done")
