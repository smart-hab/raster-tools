# processing-scripts

### how to use this repo

Create python virtual environment:

```none
python3 -m venv .venv
```

Activate the environment:

```none
source .venv/bin/activate
```

Upgrade pip (optional):

```none
pip install --upgrade pip
```

Install python dependencies:

```none
pip install geopandas rasterio shapely rioxarray
```

Use the included python scripts:

```none
python planet_preprocessing.py
```

## convert-shape.py

```none
convert-shape [-h] [-a] [-c CRS] [-f {geojson}] [-v] [-w CWD] shape

Convert Esri/Fiona/Pyogrio shape file to GeoJSON

positional arguments:
  shape                 Shape file path

options:
  -h, --help            show this help message and exit
  -a, --auto            Automatically output to <filename.format>
  -c, --crs CRS         Output CRS
  -f, --format {geojson}
                        Output format
  -v, --verbose         Display information during conversion
  -w, --cwd CWD         Working directory
```

Activate the environment:

```none
source .venv/bin/activate
```

Run the script on a target shape file:

```none
python convert-shape.py /Volumes/Data/Shapefiles/LakeOkechobee.shp
```

(Optional) Use the `-a` flag to automatically name the output file. This will create `LakeOkeechobee.geojson` in the same directory as the input:

```none
python convert-shape.py -a /Volumes/Data/Shapefiles/LakeOkechobee.shp
```

(Optional) Use `>` to arbitrarily set the destination:

```none
python convert-shape.py /Volumes/Data/Shapefiles/LakeOkechobee.shp > /Volumes/Data/GeoJSON/LakeOkeechobee.geojson
```

