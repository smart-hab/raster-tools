import pathlib
import tempfile
from typing import Optional, cast

import pydantic
from fastapi import (
    APIRouter,
    Depends,
    FastAPI,
    File,
    HTTPException,
    Query,
    Request,
    UploadFile,
)
from rasterio.enums import Resampling

from . import fn
from .about import RasterInfo, ShapeInfo
from .shared import Dtype, setup_logger


class FileResponse(pydantic.BaseModel):
    output: str


class Context:
    def __init__(self, tmp_dir: pathlib.Path):
        self.tmp_dir = tmp_dir


def get_context(request: Request) -> Context:
    tmp_dir = getattr(request.app.state, "tmp_dir", None)
    assert isinstance(tmp_dir, pathlib.Path), "Temporary directory not set in app state"
    return Context(tmp_dir=tmp_dir)


router = APIRouter()


@router.post("/about")
async def about(
    input: UploadFile = File(...),
    verbose: bool = Query(False),
) -> ShapeInfo | RasterInfo:
    if not input.filename:
        raise HTTPException(status_code=400, detail="Input file must have a filename")
    suffix = pathlib.Path(input.filename).suffix.lower()
    logger = setup_logger("about_http", verbose)
    match suffix:
        case ".shp" | ".geojson":
            return fn.about_shape(input=input.file, logger=logger)
        case ".tif" | ".tiff":
            return fn.about_raster(input=input.file, logger=logger)
        case _:
            raise HTTPException(status_code=400, detail=f"Unsupported file format: {suffix}")


@router.post("/clip")
async def clip(
    input: UploadFile = File(...),
    shape: UploadFile = File(...),
    crs: Optional[str] = Query(None),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("clip_http", verbose)
    fn.clip(input=input.file, shape=shape.file, output=output, crs=crs, logger=logger)
    return FileResponse(output=str(output))


@router.post("/convert_shape")
async def convert_shape(
    input: UploadFile = File(...),
    crs: Optional[str] = Query(None),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".geojson") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("convert_shape_http", verbose)
    fn.convert_shape(input=input.file, output=output, crs=crs, logger=logger)
    return FileResponse(output=str(output))


@router.post("/kmeans_classify")
async def kmeans_classify(
    input: UploadFile = File(...),
    clusters: UploadFile = File(...),
    band: int = Query(1),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("kmeans_classify_http", verbose)
    fn.kmeans_classify(
        input=input.file,
        clusters=clusters.file,
        output=output,
        band=band,
        logger=logger,
    )
    return FileResponse(output=str(output))


@router.post("/kmeans_fit")
async def kmeans_fit(
    input: list[UploadFile] = File(...),
    band: int = Query(1),
    clusters: int = Query(6),
    times: int = Query(5),
    random: int | None = Query(None),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    logger = setup_logger("kmeans_fit_http", verbose)
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".npy") as tmp:
        output = pathlib.Path(tmp.name)
    fn.kmeans_fit(
        input=list(x.file for x in input),
        output=output,
        band=band,
        clusters=clusters,
        times=times,
        random=random,
        logger=logger,
    )
    return FileResponse(output=str(output))


@router.post("/mask")
async def mask(
    input: UploadFile = File(...),
    udm2: UploadFile = File(...),
    bands: list[int] = Query([3, 6]),
    crs: Optional[str] = Query(None),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("mask_http", verbose)
    fn.mask(
        input=input.file,
        udm2=udm2.file,
        output=output,
        bands=bands,
        crs=crs,
        logger=logger,
    )
    return FileResponse(output=str(output))


@router.post("/means")
async def means(
    input: list[UploadFile] = File(...),
    bands: Optional[list[int]] = Query(None),
    crs: Optional[str] = Query(None),
    resampling: str = Query("bilinear"),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("means_http", verbose)
    fn.means(
        input=[f.file for f in input],
        output=output,
        bands=bands,
        crs=crs,
        logger=logger,
        resampling=getattr(Resampling, resampling.lower()),
    )
    return FileResponse(output=str(output))


@router.post("/plot")
async def plot(
    input: UploadFile = File(...),
    bands: tuple[int] | tuple[int, int, int] = Query((1,)),
    alpha: float = Query(0.0),
    filter: tuple[float, float] = Query((0.5, 99.5)),
    dpi: int = Query(300),
    cmap: str = Query("viridis"),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".png") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("plot_http", verbose)
    match bands:
        case (band,):
            fn.plot1(
                input=input.file,
                output=output,
                band=band,
                alpha=alpha,
                filter=filter,
                dpi=dpi,
                cmap=cmap,
                logger=logger,
            )
        case (red, green, blue):
            fn.plot3(
                input=input.file,
                output=output,
                bands=(red, green, blue),
                alpha=alpha,
                filter=filter,
                dpi=dpi,
                cmap=cmap,
                logger=logger,
            )
        case _:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid band selection: ({bands}). Must be 1 or 3 bands.",
            )
    return FileResponse(output=str(output))


@router.post("/norm_diff")
async def norm_diff(
    input: UploadFile = File(...),
    bands: tuple[int, int] = Query(...),
    new_name: str = Query("norm_diff"),
    crs: Optional[str] = Query(None),
    filter: tuple[float, float] = Query((1.0, 99.0)),
    dtype: Dtype = Query("uint16"),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("norm_diff_http", verbose)
    fn.norm_diff(
        input=input.file,
        bands=bands,
        new_name=new_name,
        output=output,
        crs=crs,
        filter=filter,
        dtype=dtype,
        logger=logger,
    )
    return FileResponse(output=str(output))


@router.post("/subtract")
async def subtract(
    input: tuple[UploadFile, UploadFile] = File(...),
    bands: Optional[list[int]] = Query(None),
    crs: Optional[str] = Query(None),
    resampling: str = Query("bilinear"),
    verbose: bool = Query(False),
    context: Context = Depends(get_context),
) -> FileResponse:
    with tempfile.NamedTemporaryFile(delete=False, dir=context.tmp_dir, suffix=".tif") as tmp:
        output = pathlib.Path(tmp.name)
    logger = setup_logger("subtract_http", verbose)
    fn.subtract(
        input=(input[0].file, input[1].file),
        output=output,
        bands=bands,
        crs=crs,
        logger=logger,
        resampling=getattr(Resampling, resampling.lower()),
    )
    return FileResponse(output=str(output))


def server() -> None:
    import argparse
    import os
    import uvicorn
    from fastapi.middleware.cors import CORSMiddleware

    # command line arguments
    p = argparse.ArgumentParser(
        prog="norm_diff", description="Normalize difference between two bands"
    )
    p.add_argument(
        "--host",
        type=str,
        help="Host to bind to (default: 127.0.0.1)",
        default="127.0.0.1",
    )
    p.add_argument("--port", type=int, help="Port to bind to (default: 8000)", default=8000)
    p.add_argument("--tmp-dir", help="Temporary directory (default: ./tmp)", default="tmp")
    args = p.parse_args()
    # temporary directory
    tmp_dir = pathlib.Path(os.getcwd()) / cast(str, args.tmp_dir)
    assert tmp_dir.exists() and tmp_dir.is_dir(), f"Temporary directory does not exist: {tmp_dir}"
    # fastapi server

    app = FastAPI()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "http://localhost:8001",
        ],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.tmp_dir = tmp_dir
    app.include_router(router)
    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    server()
