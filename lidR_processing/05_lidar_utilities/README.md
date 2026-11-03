# Lidar Utilities

This folder contains supporting R scripts for inspecting, repairing, filtering,
and deriving information from LAS/LAZ point clouds. These utilities are intended
to complement the primary lidar-processing workflows. Review all paths,
coordinate systems, classifications, units, and algorithm parameters before
running a script on a new acquisition.

## Utility scripts

- [Acquisition date extraction](lidR_AcquistionDates.R) — estimates tile-level
  acquisition dates and flight-time ranges from LAS GPS time when the vendor did
  not supply an acquisition-date product. Use vendor-provided dates whenever
  they are available.
- [Overwrite CRS metadata](lidR_AssignCRS.r) — replaces CRS metadata for every
  output file using either a reference LAS/LAZ file or an EPSG code.
- [Check and assign missing CRS metadata](lidR_CheckCRS_AssignCRS.R) — assigns
  CRS metadata only to files whose headers do not already contain a CRS.
- [Noise and ground reclassification](lidR_Reclassify_Noise_Ground.R) — filters
  statistical outliers and classifies ground with PTD, PMF, or MCC.
- [Grid-snapped pixel metrics](lidR_grid_snapped_grid_metrics.R) — demonstrates
  how to supply an existing raster grid to `pixel_metrics()` so outputs from
  separate lidar acquisitions share the same cell alignment.
- [LAScatalog intersection example](%E2%81%AFlidR_catalog_intersect_example.R) —
  demonstrates how to use `catalog_intersect()` to process only catalog tiles
  that intersect an area of interest.

## Selecting catalog tiles with `catalog_intersect()`

The LAScatalog intersection example is intended to demonstrate the
`lidR::catalog_intersect()` functionality. It reads a complete LAS/LAZ catalog,
transforms a polygon area of interest to the catalog CRS, and flags intersecting
tiles for processing. The script then creates DEMs from the selected catalog as
an example, but the same selection approach can be used before other LAScatalog
operations.

With `subset = "flag_processed"`, the catalog structure is retained and tiles
outside the area of interest are flagged so subsequent catalog operations skip
them. The function selects intersecting catalog tiles; it does not clip point
data to the exact AOI boundary. Tiles crossing the boundary can therefore
contribute data outside the AOI. Use a separate clipping workflow when exact
output geometry is required.

## Grid-snapped pixel metrics

When metrics are generated separately for multiple lidar acquisitions, the
default output grid for each acquisition may be positioned independently to
fit that catalog's bounding box. Matching spatial resolutions alone do not
guarantee that the cell origins and boundaries coincide. Misaligned outputs
must be resampled before they can be combined, which can alter metric values
and grid geometry.

The reference-grid example passes an existing raster directly to
`pixel_metrics()`. Using the same reference raster for every acquisition gives
the outputs a common CRS, origin, cell size, and alignment. The resulting
metric rasters can be mosaicked without resampling or changing their effective
spatial resolution. Each output metric raster will have the same cell
resolution as the reference raster.

The included script calculates rumple index as an example. Other metric
expressions can be substituted inside `pixel_metrics()`. See the
[grid-metrics workflow](../02_grid_metrics/lidRmetrics.R) for additional lidar
metric expressions that can be adapted to the reference-grid approach. The
reference raster defines grid geometry only; it does not reproject the point
cloud. Confirm that the catalog and reference raster use the same projected CRS
before processing.

## Noise and ground reclassification

The reclassification script can be used to address noise or ground points that
were missed or incorrectly classified by the vendor. Review the existing
classifications and tune the algorithms for the acquisition and area of
interest before processing the complete dataset.

The script demonstrates how to use the `lidR` LAScatalog processing workflow on
the entire LAS/LAZ catalog or only the catalog tiles that intersect an area of
interest. The default assignment, `ctg_processing <- ctg`, processes the whole
catalog. To select tiles for reprocessing, use the included
[LAScatalog intersection example](%E2%81%AFlidR_catalog_intersect_example.R)
and assign its result to `ctg_processing`. This selects intersecting catalog
tiles; it does not clip output points to the exact AOI boundary.

The **User inputs** section contains the input and output directories, worker
count, and catalog chunk buffer. Noise- and ground-classification parameters
are defined inside `noise_ground_classification()`, immediately before the
corresponding classification calls. This keeps each algorithm and its tuning
parameters together.

### Noise classification

The script uses statistical outlier removal (SOR). Its starting parameters are
defined inside `noise_ground_classification()`:

```r
noise_sor_k <- 15
noise_sor_m <- 3
```

- `k` is the number of neighboring points used to evaluate each point.
- `m` is the standard-deviation multiplier used to identify outliers.

Values of `k = 15` and `m = 3` provide a relatively conservative filter.
CloudCompare defaults to `k = 6` and `m = 1`, which is more aggressive.
Conservative filtering reduces the risk of deleting legitimate canopy returns
but may leave some noise in the point cloud.

Large swaths of noise missed by the vendor may require manual editing or more
aggressive filtering. Aggressive settings can remove valid canopy returns,
especially in sparse or structurally complex vegetation. Test settings on
representative tiles and inspect the results before processing the full
acquisition.

### Ground-classification methods

Three ground-classification examples are included because they have performed
reasonably well in previous workflows:

1. **Progressive TIN Densification (PTD)** — the default and the method
   recommended by the `lidR` authors.
2. **Progressive Morphological Filter (PMF)**.
3. **Multiscale Curvature Classification (MCC)**.

PTD is active by default. To use PMF or MCC, comment out the PTD parameters and
classification call inside `noise_ground_classification()`, then uncomment the
parameters and classification call for the corresponding alternative. Only one
ground-classification call should be active. These are examples and not an
exhaustive list of the algorithms supported by `lidR`.

In previous tests, PTD processed data substantially faster and generally
performed better on steep terrain, but it showed a greater tendency to classify
low vegetation as ground. PMF and MCC were less prone to extending ground
classifications into vegetation, but they performed less consistently on steep
slopes, produced more interpolation artifacts, and could smooth fine-scale
topographic variation. MCC was modestly faster than PMF in those tests. Results
will vary with terrain, vegetation, point density, and parameter selection.

General PTD starting ranges for forested, mountainous terrain are:

| Parameter | Suggested starting range |
| --- | --- |
| `res` | 10–20 meters |
| `angle` | 40–70 degrees |
| `distance` | 0.25–3 meters |

These ranges assume a projected CRS measured in meters and are starting points
rather than universal recommendations. Convert the distance-based values when
working in another unit system. Point density, terrain complexity, scan
geometry, vegetation structure, and CRS units all affect suitable settings.

## CRS utility warning

The CRS utilities assign or replace CRS metadata; they do **not** transform XYZ
coordinates. Use them only when point coordinates are already expressed in the
target CRS. Confirm the CRS from authoritative vendor or acquisition
information, preserve the original files, and inspect corrected copies before
subsequent analysis.

## Recommended quality control

Before accepting reclassified or repaired outputs, review:

- horizontal and vertical CRS metadata and units;
- tile coverage and alignment;
- retained canopy returns and removed noise;
- ground classifications on steep slopes, ridges, drainage features, and dense
  vegetation;
- classification consistency across tile boundaries; and
- output file and LAX-index completeness.
