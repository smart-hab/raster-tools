import glob
import logging
import os
import pathlib

import numpy
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject

# The 13 Sentinel-2 L1C bands, in spectral order — note B8A sits between B08 and B09.
# L1C is used rather than L2A because atmospheric correction drops B10.
BAND_ORDER = [
    "B01",  # coastal aerosol   443 nm   60 m
    "B02",  # blue              490 nm   10 m
    "B03",  # green             560 nm   10 m
    "B04",  # red               665 nm   10 m
    "B05",  # red edge          705 nm   20 m
    "B06",  # red edge          740 nm   20 m
    "B07",  # red edge          783 nm   20 m
    "B08",  # NIR               842 nm   10 m
    "B8A",  # narrow NIR        865 nm   20 m
    "B09",  # water vapour      945 nm   60 m
    "B10",  # cirrus           1375 nm   60 m
    "B11",  # SWIR             1610 nm   20 m
    "B12",  # SWIR             2190 nm   20 m
]


def find_img_data(input: pathlib.Path) -> pathlib.Path:
    """Resolve an IMG_DATA directory from either a .SAFE root or an IMG_DATA path.

    Callers hand us whichever they have — the Swift app knows the .SAFE directory it just
    extracted, but not the granule name nested inside it.
    """
    if input.name == "IMG_DATA":
        return input
    matches = sorted(glob.glob(os.path.join(input, "GRANULE", "*", "IMG_DATA")))
    if not matches:
        raise RuntimeError(f"No GRANULE/*/IMG_DATA directory found under: {input}")
    if len(matches) > 1:
        raise RuntimeError(f"Expected exactly one granule, found {len(matches)}: {input}")
    return pathlib.Path(matches[0])


def find_band(img_data: pathlib.Path, band: str) -> pathlib.Path:
    matches = sorted(glob.glob(os.path.join(img_data, f"*_{band}.jp2")))
    if not matches:
        raise RuntimeError(f"Could not find band {band} in: {img_data}")
    return pathlib.Path(matches[0])


def s2_stack(
    input: pathlib.Path,
    output: pathlib.Path,
    reference_band: str,
    logger: logging.Logger,
) -> None:
    # locate bands
    img_data = find_img_data(input)
    logger.info(f"Reading bands... {img_data}")

    # reference grid — the bands come at 10/20/60 m, and everything is resampled onto the
    # reference band's grid so they can be written as a single multi-band raster.
    reference = find_band(img_data, reference_band)
    logger.info(f"Reference band {reference_band}... {reference.name}")
    with rasterio.open(reference) as ref:
        transform = ref.transform
        crs = ref.crs
        shape = (ref.height, ref.width)
    logger.info(f"Target grid: {shape[1]}x{shape[0]} {crs}")

    # stack
    count = len(BAND_ORDER)
    stacked = numpy.zeros((count, *shape), dtype=numpy.uint16)
    for i, band in enumerate(BAND_ORDER):
        path = find_band(img_data, band)
        with rasterio.open(path) as src:
            if src.transform == transform and src.shape == shape:
                logger.info(f"Reading band {i + 1}/{count} {band}... {path.name}")
                stacked[i] = src.read(1)
            else:
                logger.info(f"Resampling band {i + 1}/{count} {band}... {path.name}")
                reproject(
                    source=rasterio.band(src, 1),
                    destination=stacked[i],
                    src_transform=src.transform,
                    src_crs=src.crs,
                    dst_transform=transform,
                    dst_crs=crs,
                    resampling=Resampling.bilinear,
                )

    # output
    logger.info(f"Saving stacked raster... {output}")
    profile = {
        "driver": "GTiff",
        "height": shape[0],
        "width": shape[1],
        "count": count,
        "dtype": "uint16",
        "crs": crs,
        "transform": transform,
        "compress": "deflate",
    }
    with rasterio.open(output, "w", **profile) as dst:
        dst.descriptions = tuple(BAND_ORDER)
        dst.write(stacked)

    # done
    logger.info("Done")
