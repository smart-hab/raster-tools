"""
Main entry for the smart_hab package
"""

from .about import RasterInfo, ShapeInfo
from .fn import (
    about_raster,
    about_shape,
    clip,
    convert_shape,
    equal,
    kmeans_classify,
    kmeans_fit,
    mask,
    means,
    norm_diff,
    plot1,
    plot3,
    subtract,
)

__all__ = [
    # types
    "RasterInfo",
    "ShapeInfo",
    # functions
    "about_raster",
    "about_shape",
    "clip",
    "convert_shape",
    "equal",
    "kmeans_classify",
    "kmeans_fit",
    "mask",
    "means",
    "norm_diff",
    "plot1",
    "plot3",
    "subtract",
]
