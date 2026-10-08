# Lidar Grid Metrics

This folder contains an R workflow for calculating lidar metrics at the pixel level from normalized LAS or LAZ point clouds. The metrics describe vegetation height, point-return intensity, and the vertical distribution of returns. They can be used as predictor variables for area-based modeling (ABA), forest-structure mapping, and other raster analyses.

## Script

- [lidR first-order grid metrics workflow](lidRmetrics.R)

## Processing workflow

The script processes a `lidR` LAScatalog in three independent sections:

1. **Height metrics** — calculates standard height statistics and additional canopy-structure metrics with `lidRmetrics`.
2. **Intensity metrics** — calculates standard intensity statistics with `stdmetrics_i()`.
3. **Strata metrics** — summarizes returns within predefined vertical height strata.

Each section:

1. reads the normalized LAS/LAZ catalog;
2. applies point filters;
3. calculates metrics at the configured grid resolution;
4. writes tiled GeoTIFF outputs;
5. mosaics the tiles with a vrt file; and
6. writes one final GeoTIFF for each metric.

The three metric sections do not depend on one another and may be run separately. Run the script one section at a time rather than executing the entire file at once.

## Input requirements

- Height-normalized LAS or LAZ files.
- A consistent projected coordinate reference system (CRS).
- Valid return-number, classification, and intensity attributes.
- Sufficient storage for temporary metric tiles and final GeoTIFFs.

The workflow assumes heights and grid dimensions are measured in meters. The default height thresholds, strata labels, folder names, and output filenames use meter-based values. Modify these values and labels before processing data stored in feet or other units.

## R packages

The workflow uses:

- `lidR`
- [`lidRmetrics`](https://github.com/ptompalski/lidRmetrics)
- `future`
- `terra`
- `mapview`
- `leaflet`
- `moments`
- `lmom`
- `Lmoments`
- `geometry`

Missing CRAN packages are installed automatically. If [`lidRmetrics`](https://github.com/ptompalski/lidRmetrics) is unavailable, the script installs `devtools` when needed and then installs the package from its GitHub repository.

## User configuration

Review the **USER INPUT** section before processing a new acquisition:

| Parameter | Purpose |
| --- | --- |
| `resolution` | Output grid-cell size. The default is 20 meters. |
| `input_dir` | Folder containing normalized LAS/LAZ files. |
| `output_dir` | Parent folder where metric outputs are written. |
| `zmin` | Minimum normalized height used for most height metrics. The default is 2 meters. |

Also review these settings in each processing section:

- `plan(multisession, workers = 3)` controls parallel workers.
- `opt_chunk_buffer(ctg) <- 30` sets the catalog buffer in CRS units.
- `-drop_class 7 18` removes low- and high-noise classes.
- `-drop_z_below 0` removes normalized points below zero.
- `-drop_z_above 115` removes normalized points above 115 units.
- `-drop_withheld` removes withheld points.

The 30-meter buffer and 115-meter maximum height are acquisition-specific defaults. Adjust them for the CRS units, vegetation, point density, available memory, and analysis objectives.

## Height metrics

The `elev_metrics()` function uses `lidRmetrics` to calculate:

- basic height statistics;
- height percentiles;
- percentage-above-threshold metrics;
- dispersion metrics;
- canopy-density metrics;
- L-moments;
- leaf-area-density metrics; and
- rumple index.

When `zmin` is set, most height-distribution metrics are calculated only from points above that height and receive a suffix such as `_plus2`. Percentage-above-threshold and rumple metrics are calculated separately and are not restricted by `zmin` in the combined output.

Metrics are calculated for both first returns and all returns through `by_echo = c("first", "all")`.

## Intensity metrics

Intensity metrics are calculated with `stdmetrics_i()` for first returns and all returns. Meaningful comparisons require consistent intensity calibration and acquisition conditions. Raw intensity values may not be directly comparable among flight lines, sensors, acquisition dates, or vendors unless the data have been appropriately calibrated.

## Strata metrics

The `StrataMetrics()` function divides normalized returns into these height ranges:

- 0–0.5 m
- 0.5–1 m
- 1–2 m
- 2–4 m
- 4–8 m
- 8–16 m
- 16–32 m
- 32–48 m
- 48–64 m
- greater than 64 m

For each stratum, the script calculates:

- coefficient of variation;
- kurtosis;
- proportion of returns above 0 m;
- skewness;
- standard deviation; and
- total return count.

Empty or sparsely populated grid cells may produce `NA`, `NaN`, or undefined distribution statistics. Review these outputs before modeling.

## Output organization

With a 20-meter resolution, outputs follow this general structure:

```text
<output_dir>/
└── FirstOrder_Metrics_20m/
    ├── elev/
    │   └── tiles/
    │       ├── <source>_elev_20m_*.tif
    │       └── pixel_metrics.vrt
    ├── intensity/
    │   └── tiles/
    │       └── <source>_intensity_20m_*.tif
    ├── strata/
    │   └── tiles/
    │       └── <source>_strata_20m_*.tif
    └── <metric_name>_20METERS.tif
```

The `tiles` directories contain intermediate catalog outputs. Final mosaicked metric rasters are written directly beneath the `FirstOrder_Metrics_<resolution>m` folder.

## Recommended use

1. Confirm that the input point clouds are height normalized.
2. Set `resolution`, `input_dir`, `output_dir`, and `zmin`.
3. Review the parallel-worker count, catalog buffer, point filters, and height thresholds.
4. Inspect the catalog summary and plots for coverage, gaps, overlaps, CRS, and chunk layout.
5. Run the height, intensity, or strata section needed for the analysis.
6. Confirm that tile files were created before mosaicking.
7. Inspect the final rasters for seams, missing cells, extreme values, and unexpected `NA` values.
8. Reset the future plan to sequential processing when finished if additional nonparallel work will be performed in the same R session.

## Restarting interrupted processing

The script includes examples for restarting catalog processing with `opt_restart()` or marking selected catalog entries as already processed. Add the appropriate restart option immediately before `pixel_metrics()` in the section being resumed. Verify catalog order and existing tile outputs before skipping chunks.

## Quality-control considerations

Review:

- normalization quality and ground values near zero;
- CRS and measurement units;
- point classifications and noise;
- maximum-height filtering;
- return-number and intensity attributes;
- tile completeness and mosaic seams;
- cells with insufficient returns;
- extreme or undefined statistical values; and
- consistency of metric names and units before ABA modeling.

Metric settings are acquisition-specific. Grid resolution, minimum height, strata boundaries, filters, and buffer size should be selected according to point density, forest structure, plot size, model objectives, and available computing resources.
