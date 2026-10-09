# Existing Vegetation Lidar Workflows

This repository contains R-based lidar workflows developed to support existing-vegetation and forest-structure projects. The current scripts cover foundational point-cloud processing, grid-metric generation, individual tree detection and segmentation, and lidar-informed field-sample allocation.

The repository is a collection of working analysis scripts rather than an R package or a single end-to-end application. Paths, coordinate-system units, processing parameters, and available computing resources should be reviewed before a script is run on a new acquisition.

## Current workflows

### 1. Basic processing

[Basic lidar processing](01_basic_processing/README.md) provides the common preparation steps used for a lidar acquisition:

- create LAX spatial indexes;
- generate digital elevation models (DEMs);
- normalize point-cloud elevations to height above ground; and
- create canopy height models (CHMs).

The workflow uses the `lidR` catalog engine to process tiled LAS or LAZ data and write spatially organized outputs.

### 2. Grid metrics

[Grid-based lidar metrics](02_grid_metrics/README.md) calculates raster metrics from normalized LAS or LAZ files. The current workflow includes:

- height-distribution metrics;
- intensity metrics; and
- vertical-strata metrics.

Chunk-level results are written as raster tiles and can be combined into acquisition-wide GeoTIFF products.

### 3. Individual tree detection and segmentation

[Individual tree detection and segmentation](03_tree_detection/README.md) detects treetops and delineates crowns with a marker-controlled watershed workflow. It produces:

- treetop points;
- crown polygons;
- canopy height model tiles; and
- optional segmented LAS files whose points carry a `treeID` attribute.

The workflow uses buffered catalog processing to reduce edge effects and assigns ownership of each detected tree according to the chunk containing its treetop.

### 4. Lidar-informed field sampling

The [ABA modeling folder](04_ABA_modeling) currently contains project-specific work for stratifying lidar-derived metrics and allocating field plots. The [Sitka sampling script](04_ABA_modeling/sgsR_Sitka.R) uses precomputed structural metrics with `sgsR` to develop strata, allocate samples, and create FIA-style plot clusters.

These materials support sampling design and field-plot allocation; they do not yet provide a complete area-based model fitting, validation, and prediction pipeline.

## Typical processing sequence

The general order for the documented lidar workflows is:

1. Create LAX indexes and inspect the input catalog.
2. Generate a terrain model.
3. Normalize the point cloud.
4. Create CHMs and grid metrics from the normalized data.
5. Run individual tree detection and crown segmentation when tree-level products are needed.
6. Use selected lidar metrics to support stratification and field-sample allocation.

Some steps can be run independently when the required inputs already exist. Consult each workflow README for its input requirements and processing details.

## General requirements

The workflows are written in R and primarily use the following packages:

- `lidR`
- `terra`
- `sf`
- `future`
- `dplyr`

Individual workflows require additional packages described in their READMEs or package-loading sections. Some dependencies, such as `lidRmetrics`, may be installed from GitHub rather than CRAN.

## Before running a workflow

- Confirm that all input files use a consistent and appropriate projected coordinate reference system.
- Check whether horizontal and vertical values are measured in meters or feet.
- Update file paths, worker counts, buffers, resolutions, and height filters for the acquisition.
- Test the workflow on a small subset before processing the full catalog.
- Review intermediate and final products for tile-edge effects, missing outputs, unrealistic heights, and incomplete processing.
- Avoid running an entire script at once when it contains separate processing stages intended to be run and reviewed individually.

Large lidar acquisitions can require substantial memory, storage, and processing time. Increasing the number of parallel workers can increase memory use and does not always improve overall performance.

## Repository status

The basic-processing, grid-metrics, and tree-detection folders contain the most complete and reusable workflows in the repository. The ABA materials are more project-specific and remain under active development. Parameters and hard-coded paths should be treated as examples rather than universal defaults.
