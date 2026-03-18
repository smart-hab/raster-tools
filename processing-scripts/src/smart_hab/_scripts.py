"""
This module contains functions to run bash scripts from the scripts/ directory.
"""

import subprocess
import sys
from pathlib import Path


def _run_bash_script(name: str, *args):
    """Run a bash script from the scripts directory."""
    script_path = Path(__file__).parent / "scripts" / name
    result = subprocess.run([str(script_path)] + list(args))
    sys.exit(result.returncode)


def preprocess():
    """Run the preprocess bash script."""
    _run_bash_script("preprocess", *sys.argv[1:])


def kmeans():
    """Run the kmeans bash script."""
    _run_bash_script("kmeans", *sys.argv[1:])


def preload_source_files():
    """Run the preload_source_files bash script."""
    _run_bash_script("preload_source_files", *sys.argv[1:])
