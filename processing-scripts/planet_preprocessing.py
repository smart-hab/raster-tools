# -*- coding: utf-8 -*-
"""
Created on Mon Jan 29 15:33:43 2024

This file is meant to be used for planet preprocessing.
Information for files will be brought in here, then incorporated to create
A cropped raster highlighting chlorophyll

@author: cathe
"""
#%% State inputs that will be set up through app here

bandselection = "8b" # or 4b, or RGB, or**** NONE OR CUSTOM

input_path = "/Users/cathe/data/LakeSimcoe"
save_dir = "/Users/cathe/data/LakeSimcoeOutput"
ce_path = "/Users/cathe/data/LakeSimcoe.geojson"

date_list = False
vi = True
ci = True
udmmask = True

#%% Import all relevent packages

import geopandas as gpd
import os
import pathlib
import rasterio as rio
import re
import rioxarray as rxr
import shapely

#%% Define Functions and variables

crs_wgs84 = rio.CRS.from_string('EPSG:4326')

def get_date(filename: str):
  m = re.search(r"-(\d{8})-", filename)
  if not m: raise ValueError(f"Could not extract date from {filename}")
  return m.group(1)

def band_specification(bs):
    # Can add other band specifications: RGB, etc
    if bs == "8b":
        bl = ["coastal_blue","blue","green_I","green","yellow","red","red_edge","nir"]
        bnos = [0,1,2,3,4,5,6,7]
    if bs == "4b":
        bl = ["blue","green","red", "nir"]
        bnos = [1,3,5,7]
    if bs == "RGB":
        bl = ["blue","green","red"]
        bnos = [1,3,5]
 
    return bl,bnos

def import_meta(path):
    with rio.open(path) as src:
        meta = src.meta.copy()
 
    # Save time and get to the right crs
    meta.update({
        'crs': crs_wgs84
        })
 
    return(meta)

def import_udm(path, rast):
    imported_udm = rxr.open_rasterio(path).astype(bool)
    shadow_mask = imported_udm[3,:,:]
    cloud_mask  = imported_udm[6,:,:]
    mask = shadow_mask + cloud_mask
    rast.rio.mask = mask
    del mask
    del imported_udm
    del shadow_mask
    del cloud_mask
    return(rast)
 

def import_bands(path, bn):
    imported_rast = rxr.open_rasterio(path)
    wanted_bands = imported_rast[bn,:,:]
    return(wanted_bands)

def import_shapefile(path):
    ce = gpd.read_file(path)
    print('crop extent imported. Shapefile crs: ', ce.crs)
    return(ce)

def import_json(path):
    features = gpd.read_file(path)
    return(features)

def ndvi_calc(ras):
    red = ras[5,:,:]
    nir = ras[7,:,:]
    # Get NDVI if selected
    ndvi = (nir-red)/(nir + red)
    ndvi = (ndvi) * 10000
    return ndvi
 
def ndci_calc(ras):
    red = ras[5,:,:]
    red_edge = ras[6,:,:]
    # Calculate ndci
    ndci = (red_edge - red)/(red_edge + red)
    ndci = (ndci) * 10000
    return ndci

def test_RI(ras): # Needs land fully clipped to work I think
    cb = norm_band(ras[0,:,:])
    green1 = norm_band(ras[2,:,:])
    blue = norm_band(ras[1,:,:])
    green = norm_band(ras[4,:,:])
    norm510 = norm_band((20/41 * blue)/(21/41 * green1))
    ri_test = (((norm510/green)-cb)/((norm510/green)+cb)) * 10000
    return ri_test

def reproject_raster(ras, meta, crs):
    # reproject raster to project crs
    input_crs = ras.rio.crs
    transform, width, height = rio.warp.calculate_default_transform(input_crs, crs, ras.shape[1], ras.shape[2], *ras.rio.bounds())
    kwargs = meta.copy()
 
    kwargs.update({
        'crs': crs,
        'transform': transform,
        'width': width,
        'height': height})
 
    return(ras, kwargs)

def norm_band(band):
    normalized = (band - int(band.min()))/(int(band.max())-int(band.min()))
    return(normalized)

#%% Bring in files from directory
files = os.listdir(input_path)

# Check and see if geojson or shp
if ce_path.endswith('json'):
    print("Loading geojson")
    crop_extent = import_json(ce_path)
    crop_extent = crop_extent.to_crs(crs_wgs84)
else:
    print("Loading shapefile")
    # Import shapefile and get correct crs
    crop_extent = import_shapefile(ce_path)
    crop_extent = crop_extent.to_crs(crs_wgs84)

#%% Process imagery
for file in files:
    date = get_date(file)
    print("date", date)

    filepath = pathlib.Path(input_path) / file
    print("filepath", filepath)
 
    im_path = filepath / "files/composite.tif" # dayfiles[0]
    udm_path = filepath / "files/composite_udm2.tif" # dayfiles[1]
    meta_path = filepath / "files/composite_metadata.json" # glob.glob(input_path + file + '**/*composite_metadata.json', recursive=True)
    outTIF = pathlib.Path(save_dir) / f"{date}.tif"
    print("im_path", im_path, os.path.exists(im_path))
    print("udm_path", udm_path, os.path.exists(udm_path))
    print("meta_path", meta_path, os.path.exists(meta_path))
    print("outTIF", outTIF, os.path.exists(outTIF))
 
    # skip if output file already exists
    if os.path.exists(outTIF):
        print("skipping", outTIF)
        continue

    #%% Bring in raster bands with multiple combinations
 
    # Specify and set up what bands we are using
    bandnames, bandnos = band_specification(bandselection)
 
    meta = import_meta(im_path)
 
    # Bring in wanted raster bands
    rast_area = import_bands(im_path, bandnos)
 
    # Make sure the crs is correct
    rast_area = rast_area.rio.reproject(crs_wgs84)
 
    #print('Satellite crs:', rast_area.rio.crs)
    #print('Shapefile crs:', crop_extent.crs)
 
    # Filter out bad pixels, exclude all pixels that are not classified as clear
    if udmmask:
        rast_area = import_udm(udm_path, rast_area)
 
    # Clip to the lake extent
    print("Clipping...")
    rast_clipped = rast_area.rio.clip(crop_extent.geometry.apply(shapely.geometry.mapping))
 
    # Ensure raster is correctly reprojected
    rast_clipped, meta = reproject_raster(rast_clipped, meta, crs_wgs84)
 
    del rast_area
    #%% Calculate NDVI and/or NDCI before saving, add to layer
    print("Calculating bands for: ", date)
    rstack = []
    bands = bandselection
 
    for l in range(len(rast_clipped)):
        rstack.append(rast_clipped[l])
 
    if vi:
        rstack.append(ndvi_calc(rast_clipped))
        bandnames.append("ndvi")
        bands = bands + "_v"
 
    if ci:
        rstack.append(ndci_calc(rast_clipped))
        bandnames.append("ndci")
        bands = bands + "_c"
 
    rstack.append(test_RI(rast_clipped))
    bandnames.append("nRI")
    bands = bands + "_ri"
    meta.update({ 'count' : str(len(bandnames))})
 
    #%% Write new raster
    # Get metadata
    print("Preparing metadata.")
    meta['compress'] = 'lzw'
    meta['height'] = rstack[0].shape[0] #rast_clipped.shape[1]
    meta['width'] = rstack[0].shape[1]
 
 
    print("Writing data for ", date, ".")
    #rast_clipped.rio.to_raster(outTIF, driver='GTiff', compress='lzw')
    with rio.open(outTIF, 'w', **meta) as dst:
        for band_nr, layer in enumerate(rstack, start = 1):
            dst.write(layer.astype(rio.int16), band_nr)
 
    del rstack
    del rast_clipped
    print("File Saved.")
