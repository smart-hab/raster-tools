import argparse
import json
import os
from pathlib import Path
from typing import cast

from . import fn
from .shared import Dtype, dtypes, setup_logger


def about() -> None:
    # parser
    p = argparse.ArgumentParser(prog="info", description="Display raster or shape file info")
    p.add_argument("-i", "--input", help="Source raster or shape path", required=True)
    p.add_argument(
        "-p",
        "--property",
        help="Display specific property (e.g. crs, bounds, bands, dimensions, shape, etc.)",
    )
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    # args
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    suffix = input.suffix.lower()
    logger = setup_logger("about", cast(bool, args.verbose))
    # info
    match suffix:
        case ".shp" | ".geojson":
            info = fn.about_shape(input=input, logger=logger)
        case ".tif" | ".tiff":
            info = fn.about_raster(input=input, logger=logger)
        case _:
            raise RuntimeError(f"Unsupported file format: {suffix}")
    # property
    if args.property:
        info = info.get(cast(str, args.property), None)
        if info is None:
            raise RuntimeError(f"Property not found: {args.property}")
    # output
    print(json.dumps(info, indent=2))


def clip() -> None:
    p = argparse.ArgumentParser(prog="clip", description="Clip raster with shape file")
    p.add_argument("-i", "--input", help="Source raster path", required=True)
    p.add_argument("-s", "--shape", help="Source shape path", required=True)
    p.add_argument("-o", "--output", help="Destination raster path")
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    shape = Path(args.cwd) / cast(str, args.shape)
    output = (
        Path(args.cwd) / cast(str, args.output)
        if args.output
        else input.parent / f"{input.stem}_clipped.tif"
    )
    logger = setup_logger("clip", cast(bool, args.verbose))
    fn.clip(
        input=input,
        shape=shape,
        output=output,
        crs=args.crs,
        logger=logger,
    )


def convert_shape() -> None:
    p = argparse.ArgumentParser(
        prog="convert_shape",
        description="Convert Esri/Fiona/Pyogrio shape file to GeoJSON",
    )
    p.add_argument("-i", "--input", help="Source shape path", required=True)
    p.add_argument("-o", "--output", help="Output GeoJSON path")
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument("-f", "--format", help="Output format", default="geojson", choices=["geojson"])
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    assert args.format == "geojson", f"Unsupported output format: {args.format}"
    input = Path(args.cwd) / cast(str, args.input)
    output = (
        Path(args.cwd) / cast(str, args.output) if args.output else input.with_suffix(args.format)
    )
    logger = setup_logger("convert_shape", cast(bool, args.verbose))
    fn.convert_shape(
        input=input,
        output=output,
        crs=cast(str | None, args.crs),
        logger=logger,
    )


def kmeans_classify() -> None:
    p = argparse.ArgumentParser(
        prog="kmeans_classify",
        description="Assign K-Means clusters classes to a raster band",
    )
    p.add_argument("-i", "--input", help="Source raster path", required=True)
    p.add_argument("-k", "--clusters", help="Cluster centers path (from kmeans_fit)", required=True)
    p.add_argument("-o", "--output", help="Raster destination path", required=True)
    p.add_argument("-b", "--band", help="Band selection", type=int, default=1)
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    clusters = Path(args.cwd) / cast(str, args.clusters)
    output = Path(args.cwd) / cast(str, args.output)
    logger = setup_logger("kmeans_classify", cast(bool, args.verbose))
    fn.kmeans_classify(
        input=input,
        clusters=clusters,
        output=output,
        band=cast(int, args.band),
        logger=logger,
    )


def kmeans_fit() -> None:
    p = argparse.ArgumentParser(
        prog="kmeans_fit",
        description="Fit K-Means clusters to a single band of one or more input rasters",
    )
    p.add_argument("-i", "--input", nargs="+", help="Raster source path(s)", required=True)
    p.add_argument("-o", "--output", help="Clusters destination path", required=True)
    p.add_argument("-b", "--band", help="Band selection", type=int, default=1)
    p.add_argument("-c", "--clusters", help="Number of clusters", type=int, default=6)
    p.add_argument("-t", "--times", help="Number of times to run K-Means", type=int, default=5)
    p.add_argument("-r", "--random", help="Random state for K-Means", type=int)
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    input = [Path(args.cwd) / cast(str, p) for p in args.input]
    output = Path(args.cwd) / cast(str, args.output)
    logger = setup_logger("kmeans_fit", cast(bool, args.verbose))
    fn.kmeans_fit(
        input=input,
        output=output,
        band=cast(int, args.band),
        clusters=cast(int, args.clusters),
        times=cast(int, args.times),
        random=cast(int | None, args.random),
        logger=logger,
    )


def mask() -> None:
    p = argparse.ArgumentParser(prog="mask", description="Mask raster with UDM2 file")
    p.add_argument("-i", "--input", help="Source raster path", required=True)
    p.add_argument("-u", "--udm2", help="Source UDM2 path", required=True)
    p.add_argument("-o", "--output", help="Output raster path")
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument("-b", "--bands", help="Band selection", nargs="+", type=int, default=[3, 6])
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    udm2 = Path(args.cwd) / cast(str, args.udm2)
    output = (
        Path(args.cwd) / cast(str, args.output)
        if args.output
        else input.parent / f"{input.stem}_masked.tif"
    )
    logger = setup_logger("mask", cast(bool, args.verbose))
    fn.mask(
        input=input,
        udm2=udm2,
        output=output,
        crs=cast(str | None, args.crs),
        bands=cast(list[int], args.bands),
        logger=logger,
    )


def means() -> None:
    from rasterio.enums import Resampling

    p = argparse.ArgumentParser(
        prog="means", description="Compute mean raster from multiple input rasters"
    )
    p.add_argument("-i", "--input", nargs="+", help="Input raster path(s)", required=True)
    p.add_argument("-o", "--output", help="Output raster path", required=True)
    p.add_argument("-b", "--bands", help="Band selection", nargs="+", type=int)
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument(
        "-r",
        "--resampling",
        help="Resampling method",
        default="bilinear",
        choices=[e.name for e in Resampling],
    )
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    input = [Path(args.cwd) / cast(str, p) for p in args.input]
    output = Path(args.cwd) / cast(str, args.output)
    logger = setup_logger("means", cast(bool, args.verbose))
    resampling = getattr(Resampling, cast(str, args.resampling).lower())
    assert isinstance(resampling, Resampling), f"Invalid resampling method: {args.resampling}"
    fn.means(
        input=input,
        output=output,
        bands=cast(list[int] | None, args.bands),
        crs=cast(str | None, args.crs),
        logger=logger,
        resampling=resampling,
    )


def plot() -> None:
    # parser
    p = argparse.ArgumentParser(prog="plot", description="Plot raster to PNG")
    p.add_argument("-i", "--input", help="Source raster path", required=True)
    p.add_argument("-o", "--output", help="Destination image path")
    # parser mode
    g = p.add_mutually_exclusive_group()
    g.add_argument(
        "-g",
        "--grayscale",
        metavar="BAND",
        dest="bands",
        nargs=1,
        type=int,
        help="Plot grayscale image",
        default=[1],
    )
    g.add_argument(
        "-r",
        "--rgb",
        metavar="BAND",
        dest="bands",
        nargs=3,
        type=int,
        help="Plot RGB image",
    )
    # parser extras
    o = p.add_argument_group("Extra arguments")
    o.add_argument(
        "-a",
        "--alpha",
        help="Alpha transparency for NoData values",
        type=float,
        default=0.0,
    )
    o.add_argument(
        "-f",
        "--filter",
        metavar=("LOW", "HIGH"),
        help="Robust normalization percentile filter",
        type=float,
        nargs=2,
        default=[0.5, 99.5],
    )
    o.add_argument("-d", "--dpi", help="Plot resolution", type=int, default=300)
    o.add_argument("-c", "--cmap", help="Plot color map for grayscale images", default="viridis")
    o.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    o.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    # args
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    output = (
        Path(args.cwd) / cast(str, args.output)
        if args.output
        else input.parent / f"{input.stem}.png"
    )
    logger = setup_logger("plot", cast(bool, args.verbose))
    match cast(list[int], args.filter):
        case [low, high]:
            filter = (low, high)
        case _:
            raise RuntimeError(f"Invalid filter range: ({args.filter}). Must be two values.")
    match cast(list[int], args.bands):
        case [band]:
            fn.plot1(
                input=input,
                output=output,
                band=band,
                alpha=cast(float, args.alpha),
                filter=filter,
                dpi=cast(int, args.dpi),
                cmap=cast(str, args.cmap),
                logger=logger,
            )
        case [red, green, blue]:
            fn.plot3(
                input=input,
                output=output,
                bands=(red, green, blue),
                alpha=cast(float, args.alpha),
                filter=filter,
                dpi=cast(int, args.dpi),
                cmap=cast(str, args.cmap),
                logger=logger,
            )
        case _:
            raise RuntimeError(f"Invalid band selection: ({args.bands}). Must be 1 or 3 bands.")


def norm_diff() -> None:
    NDCI = [7, 6]  # NDCI = (Red Edge, Red)
    NDVI = [8, 6]  # NDVI = (NIR, RED)
    p = argparse.ArgumentParser(
        prog="norm_diff", description="Normalize difference between two bands"
    )
    p.add_argument("-i", "--input", help="Source raster path", required=True)
    p.add_argument("-b", "--bands", help="Band selection", nargs=2, type=int, required=True)
    p.add_argument("-o", "--output", help="Output raster path")
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument(
        "-f",
        "--filter",
        metavar=("LOW", "HIGH"),
        help="Robust normalization percentile filter",
        type=float,
        nargs=2,
        default=[1.0, 99.0],
    )
    p.add_argument("-d", "--dtype", help="Output data type", choices=dtypes, default="uint16")
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    p.add_argument("--ndci", help="Calculate NDCI", dest="bands", action="store_const", const=NDCI)
    p.add_argument("--ndvi", help="Calculate NDVI", dest="bands", action="store_const", const=NDVI)
    args = p.parse_args()
    input = Path(args.cwd) / cast(str, args.input)
    new_name = "norm_diff"
    if args.bands == NDCI:
        new_name = "ndci"
    if args.bands == NDVI:
        new_name = "ndvi"
    output = (
        Path(args.cwd) / cast(str, args.output)
        if args.output
        else input.parent / f"{input.stem}_{new_name}.tif"
    )
    match cast(list[int], args.bands):
        case [a, b]:
            bands = (a, b)
        case _:
            raise RuntimeError(f"Invalid band selection: ({args.bands}). Must be 2 bands.")
    match cast(list[float], args.filter):
        case [low, high]:
            filter = (low, high)
        case _:
            raise RuntimeError(f"Invalid filter range: ({args.filter}). Must be two values.")
    logger = setup_logger("norm_diff", cast(bool, args.verbose))
    assert args.dtype in dtypes, f"Invalid data type: {args.dtype}"
    fn.norm_diff(
        input=input,
        bands=bands,
        new_name=new_name,
        output=output,
        crs=cast(str | None, args.crs),
        filter=filter,
        dtype=cast(Dtype, args.dtype),
        logger=logger,
    )


def subtract() -> None:
    from rasterio.enums import Resampling

    p = argparse.ArgumentParser(prog="subtract", description="Subtract one raster from another")
    p.add_argument("-i", "--input", nargs=2, help="Source raster paths", required=True)
    p.add_argument("-o", "--output", help="Output raster path", required=True)
    p.add_argument("-b", "--bands", help="Band selection", nargs="+", type=int)
    p.add_argument("-c", "--crs", help="Target CRS (e.g. EPSG:4326)")
    p.add_argument(
        "-r",
        "--resampling",
        help="Resampling method",
        default="bilinear",
        choices=[e.name for e in Resampling],
    )
    p.add_argument(
        "-v",
        "--verbose",
        help="Display extra information",
        action="store_true",
        default=False,
    )
    p.add_argument("-w", "--cwd", help="Working directory", default=os.getcwd())
    args = p.parse_args()
    match cast(list[str], args.input):
        case [a, b]:
            input = (
                Path(args.cwd) / a,
                Path(args.cwd) / b,
            )
        case _:
            raise RuntimeError(f"Invalid input files: ({args.input}). Must be two files.")
    output = Path(args.cwd) / cast(str, args.output)
    logger = setup_logger("subtract", cast(bool, args.verbose))
    resampling = getattr(Resampling, cast(str, args.resampling).lower())
    assert isinstance(resampling, Resampling), f"Invalid resampling method: {args.resampling}"
    fn.subtract(
        input=input,
        output=output,
        bands=cast(list[int] | None, args.bands),
        crs=cast(str | None, args.crs),
        logger=logger,
        resampling=resampling,
    )
