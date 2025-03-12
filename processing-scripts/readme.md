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

This script converts a Fiona/Pyogrio shape file to GeoJSON

Activate the environment:

```none
source .venv/bin/activate
```

Run the script on a target shape file

```none
python convert-shape.py /Volumes/Data/shapefiles/lake_okeechobee.shp
```

By default the output goes to standard output, you can redirect it to a file using `>`

```none
python convert-shape.py /Volumes/Data/shapefiles/lake_okeechobee.shp > /Volumes/Data/shapefiles/lake_okechobee.geojson
```

