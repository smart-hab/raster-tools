from typing import TypedDict, Any, Hashable, BinaryIO
from . import shared
import logging
import pathlib


class ShapeInfo(TypedDict):
    crs: str
    bounds: tuple[float, float, float, float]
    geometry: str


class RasterInfo(TypedDict):
    attributes: dict[str, Any]
    bands: dict[int, str]
    bounds: tuple[float, float, float, float]
    crs: str
    dimensions: tuple[str, ...]
    dtype: str
    nodata: float | None
    pixels: int
    resolution: tuple[float, float]
    shape: tuple[int, ...]
    size_mb: float
    transform: tuple[float, ...]


def about_shape(
    input: pathlib.Path | BinaryIO,
    logger: logging.Logger,
) -> ShapeInfo:
    logger.info(f"Loading shape... {input}")
    shape = shared.load_shape(input)
    bounds = shape.bounds
    return {
        "crs": str(shape.crs),
        "bounds": (
            float(bounds.minx[0]),
            float(bounds.miny[0]),
            float(bounds.maxx[0]),
            float(bounds.maxy[0]),
        ),
        "geometry": str(shape.geometry.type[0]),
    }


def about_raster(
    input: pathlib.Path | BinaryIO,
    logger: logging.Logger,
) -> RasterInfo:
    logger.info(f"Loading raster... {input}")
    raster = shared.load_raster(input)
    rio = shared.rio(raster)
    return {
        "attributes": serialize_raster_attributes(raster.attrs),
        "bands": shared.raster_bands(raster),
        "bounds": rio.bounds(),
        "crs": str(rio.crs),
        "dimensions": tuple(map(str, raster.dims)),
        "dtype": str(raster.dtype),
        "nodata": float(rio.nodata) if rio.nodata is not None else None,
        "pixels": raster.size,
        "resolution": rio.resolution(),
        "shape": tuple(raster.shape),
        "size_mb": raster.nbytes / (1024 * 1024),
        "transform": tuple(rio.transform()),
    }


def serialize_raster_attributes(attrs: dict[Hashable, Any]) -> dict[str, Any]:
    d: dict[str, Any] = dict()
    for k, v in attrs.items():
        if isinstance(v, (int, float, str)):
            d[str(k)] = v
        elif isinstance(v, (list, tuple)):
            d[str(k)] = [x if isinstance(x, (int, float)) else str(x) for x in v]
        else:
            d[str(k)] = str(v)
    return d
