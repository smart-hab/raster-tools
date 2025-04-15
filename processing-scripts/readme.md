# processing-scripts

### how to use this repo

Clone the repo

```none
https://github.com/smart-hab/processing-scripts.git
```

Change branch to `pypackage`

```none
cd processing-scripts
git checkout pypackage
```

In your project, create python virtual environment:

```none
cd /path/to/myproject
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

Install the processing-scripts python package:

```none
pip install -e /path/to/processing-scripts
```

Use the included python scripts:

```none
clip --help
convert_shape --help
mask --help
norm_diff --help
png --help
select_bands --help
```


