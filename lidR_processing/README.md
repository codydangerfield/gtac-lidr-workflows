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

The [ABA modeling folder](04_ABA_modeling) contains workflows for extracting
plot-level lidar metrics, stratifying lidar-derived metrics, and allocating
field plots. The [plot-metrics script](04_ABA_modeling/lidR_PlotMetrics.R)
calculates structural metrics for field-plot locations, while the
[sampling script](04_ABA_modeling/sgsR_SitePlacement.R) uses precomputed
structural metrics with `sgsR` to develop strata, allocate samples, and create
FIA-style plot clusters.

These materials support plot-level metric extraction, sampling design, and
field-plot allocation; they do not yet provide a complete area-based model
fitting, validation, and prediction pipeline.

### 5. Supplementary lidar utilities

The [lidar utilities folder](05_lidar_utilities/README.md) contains optional
scripts for acquisition-specific data preparation, repair, quality control, and
specialized processing. These scripts are not required for every acquisition,
but they may be useful when vendor products are incomplete, metadata need to be
corrected, classifications require additional work, or outputs from multiple
acquisitions must share a common grid.

Current utilities include:

- [noise and ground reclassification](05_lidar_utilities/lidR_Reclassify_Noise_Ground.R),
	with examples for statistical outlier removal and PTD, PMF, or MCC ground
	classification;
- [high-performance noise, ground, and DTM processing with lasR](05_lidar_utilities/lasR_Reclassify_Noise_Ground_DEM.R),
	which chains equivalent operations into an optimized processing pipeline;
- [overwriting CRS metadata](05_lidar_utilities/lidR_AssignCRS.r) when every
	file requires correction;
- [checking and assigning missing CRS metadata](05_lidar_utilities/lidR_CheckCRS_AssignCRS.R)
	while preserving files whose headers already contain a CRS;
- [selecting LAScatalog tiles by area of interest](05_lidar_utilities/%E2%81%AFlidR_catalog_intersect_example.R)
	with `catalog_intersect()` before running a catalog operation;
- [grid-snapped pixel metrics](05_lidar_utilities/lidR_grid_snapped_grid_metrics.R),
	which use an existing raster as the `pixel_metrics()` template so separately
	processed acquisitions share the same origin, resolution, and cell
	alignment; and
- [acquisition-date extraction](05_lidar_utilities/lidR_AcquistionDates.R) from
	LAS GPS time when a vendor-supplied acquisition-date product is unavailable.

The CRS utilities modify metadata only; they do not transform point
coordinates. The acquisition-date utility is a fallback and should not replace
authoritative vendor products when those products are available. Review the
[utilities documentation](05_lidar_utilities/README.md) before using any of
these scripts.

`lasR` is a newer, performance-oriented companion to `lidR`. When both packages
provide equivalent operations, `lasR` will generally process large datasets
faster and with lower memory use. `lidR` remains preferable when greater
algorithm choice, customization, partial catalog processing, restart controls,
or interactive inspection is required.

## Typical processing sequence

The general order for the documented lidar workflows is:

1. Create LAX indexes and inspect the input catalog.
2. Generate a terrain model.
3. Normalize the point cloud.
4. Create CHMs and grid metrics from the normalized data.
5. Run individual tree detection and crown segmentation when tree-level products are needed.
6. Use selected lidar metrics to support stratification and field-sample allocation.

Some steps can be run independently when the required inputs already exist. Consult each workflow README for its input requirements and processing details.

Supplementary utilities can be inserted before or during this sequence as
needed. For example, CRS metadata should be repaired before spatial processing,
noise and ground classifications should be reviewed before terrain modeling or
normalization, and a shared reference grid should be selected before generating
metrics that will be mosaicked across multiple acquisitions.

## General requirements

The workflows are written in R and primarily use the following packages:

- `lidR`
- `terra`
- `sf`
- `future`
- `dplyr`
- `mapview`

Individual workflows require additional packages described in their READMEs or
package-loading sections. Some dependencies are not distributed through CRAN:
`lidRmetrics` is installed from GitHub, and `lasR` is installed from the
R-lidar R-universe.

## Before running a workflow

- Confirm that all input files use a consistent and appropriate projected coordinate reference system.
- Check whether horizontal and vertical values are measured in meters or feet.
- Update file paths, worker counts, buffers, resolutions, and height filters for the acquisition.
- Test the workflow on a small subset before processing the full catalog.
- Review intermediate and final products for tile-edge effects, missing outputs, unrealistic heights, and incomplete processing.
- Use the configured `mapview` basemaps to inspect catalog coverage and spatial
	relationships when a script calls `plot(ctg, map = TRUE)`.
- Avoid running an entire script at once when it contains separate processing stages intended to be run and reviewed individually.

Large lidar acquisitions can require substantial memory, storage, and processing time. Increasing the number of parallel workers can increase memory use and does not always improve overall performance.

## Repository status

This repository is under active development. Some scripts or processing steps
may not be applicable to every area of interest or lidar acquisition. The
repository is not intended to provide exhaustive documentation of the `lidR`
package. Instead, it synthesizes scripts, functions, and processing patterns
that are frequently used to process lidar data in R.

All parameters and hard-coded paths should be treated as examples rather than
universal defaults. Parameters may require fine-tuning for each user's area of
interest, lidar acquisition specifications, point density, coordinate units,
terrain, vegetation structure, computing resources, and intended outputs.
Consult the official package documentation and acquisition metadata when
adapting these workflows.
