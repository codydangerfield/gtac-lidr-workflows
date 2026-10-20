# LiDAR Plot Metrics

This workflow calculates LiDAR metrics for field plots from a height-normalized LAS/LAZ catalog. It summarizes the returns inside each circular plot area and writes one row of metrics per plot to a dated CSV, for use in area-based modeling (ABA).

## Relationship to the grid-metrics workflow

[`lidR_PlotMetrics.R`](lidR_PlotMetrics.R) is the plot-level companion to [`lidRmetrics.R`](02_grid_metrics/lidRmetrics.R). Both workflows use `lidR` and `lidRmetrics` to describe LiDAR structure. The grid workflow summarizes points in raster cells; this workflow summarizes points within field-plot radii and exports a table keyed by plot.

The plot script currently calculates height-distribution metrics for first and all returns. It does not create pixel rasters or calculate the separate intensity and strata products described by the grid workflow.

## Processing workflow

The script:

1. Reads field-plot locations from a geodatabase and a normalized LAS/LAZ catalog.
2. Keeps the `PlotID` field, removes Z/M geometry dimensions, and projects plots to the catalog CRS.
3. Applies the catalog filters for noise classes, withheld points, and normalized height range.
4. Uses `lidR::plot_metrics()` to calculate metrics within the configured radius for first and all returns.
5. Writes plot-level LAS/LAZ files under `Plot_LAS_Files/` and exports a dated CSV without geometry.

## Inputs and configuration

Edit the **User Inputs** section near the top of `lidR_PlotMetrics.R` before running it:

| Setting | Purpose | Current default |
| --- | --- | --- |
| `ctg_folder` | Folder containing normalized LAS/LAZ files | `D:/Lidar_Project/Data/LAS/Normalized` |
| `root_dir` | Root folder for plot metrics and clipped plot point clouds | `D:/Lidar_Project/GroundPlots/CollectedPlots` |
| `plots_gdb` | Geodatabase containing the field plots | `Collected_Plots.gdb` under `root_dir` |
| `plots_layer` | Geodatabase layer containing the plot locations | `Collected_Plots_2026` |
| `plot_radius` | Radius, in meters, used to select returns around each plot | `8.01624` m (approximately a 1/20-acre plot) |

The plot layer must contain a `PlotID` field and point geometries. The plot locations are transformed to the catalog CRS, but the plot radius is interpreted in the catalog's horizontal units. Use a projected CRS in meters or adjust the radius to match the CRS units.

The LAS/LAZ data should be height normalized and use consistent horizontal units. Review point classifications, return attributes, normalization, and coverage before processing.

## Point filters

The script currently applies this `lidR` catalog filter:

```text
-drop_class 7 18 -drop_z_below 0 -drop_withheld -drop_z_above 115
```

It removes classes 7 and 18, withheld points, points below 0, and points above 115 height units. These are acquisition-specific defaults; adjust them for the data and analysis. The workflow assumes normalized heights and the default thresholds are in meters.

## Metrics calculated

The script calls its `elev_metrics()` function with `zmin = 2` and `threshold = 2`. For that configuration, it writes:

- Basic height statistics and height percentiles for returns above 2 m, with a `_plus2` suffix.
- Dispersion, canopy-density, and L-moment metrics for returns above 2 m, with a `_plus2` suffix.
- Percentage-above-threshold metrics and rumple index calculated from the full set of filtered returns, without the `_plus2` suffix.
- Metrics separately for first returns and all returns through `by_echo = c("first", "all")`.

Before CSV export, the script replaces periods in metric column names with underscores, drops geometry, and removes selected point-count and minimum/maximum height columns. Empty or sparsely sampled plots may produce missing or undefined statistics; inspect these values before modeling.

## Outputs

Outputs are written beneath `root_dir`:

```text
<root_dir>/
├── Plot_Metrics_YYYYMMDD.csv
└── Plot_LAS_Files/
    └── <PlotID>.*
```

The CSV filename includes the run date. The plot LAS/LAZ output path is configured with `opt_output_files()` and uses each plot's `PlotID` in its filename.

## R packages

The script installs missing CRAN packages and loads:

- `lidR`, `sf`, `mapview`, `dplyr`, and `vroom`
- `Lmoments`, `lmom`, `moments`, and `geometry`, used by selected `lidRmetrics` functions
- [`lidRmetrics`](https://github.com/ptompalski/lidRmetrics), installed from GitHub if it is not already available

## Running the script

1. Confirm the input paths, plot layer, plot radius, and point filters.
2. Confirm that the plot layer has `PlotID` values and a projected CRS compatible with the catalog.
3. Open `lidR_PlotMetrics.R` in RStudio and run the script.
4. Review the generated CSV and plot LAS/LAZ files, including plot IDs, metric columns, missing values, and point coverage.

This workflow does not set up future-based parallel processing for `plot_metrics()`. The script comments note that future-based parallel processing can slow this plot workflow.
