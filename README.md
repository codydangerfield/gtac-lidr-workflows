# Existing Vegetation Modeling Scripts

This repository contains general R scripts used during lidar processing and existing vegetation modeling. The scripts support the preparation of lidar-derived data, the extraction of predictor variables, and the development of classification and regression models for vegetation mapping and forest-structure analysis.

The repository is organized around three broad areas of work:

## Lidar processing

The [lidar processing workflows](lidR_processing/README.md) include scripts for preparing and analyzing point-cloud data. Current workflows cover basic processing, grid-metric generation, individual tree detection and crown segmentation, and lidar-informed field-sample allocation.

## Zonal statistics

Zonal-statistics scripts will summarize lidar, spectral, terrain, and other raster predictors within reference polygons or sampling units. These summaries can be used to assemble training and validation data for existing vegetation models.

## Random forest modeling

Random forest scripts will support both classification and regression tasks, including:

- classification of categorical vegetation attributes;
- prediction of continuous forest-structure attributes;
- model training and validation; and
- generation of spatial prediction products.

## Repository status

This repository is under active development. The lidar-processing workflows are currently the most developed portion of the repository. Zonal-statistics and random forest workflows will be added and documented as they are prepared for general use.

The scripts are working analysis tools rather than an R package or a single end-to-end application. Before running a script, review its paths, input requirements, coordinate-system assumptions, measurement units, processing parameters, and computing requirements.
