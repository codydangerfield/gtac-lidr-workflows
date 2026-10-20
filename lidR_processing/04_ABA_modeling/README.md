# ABA Site Placement and lidar Plot Metrics

This folder contains the site-placement and plot-metric workflows for area-based modeling (ABA). [`sgsR_SitePlacement.R`](sgsR_SitePlacement.R) creates a forested, public, accessible sampling frame, allocates sample centers among lidar strata, and builds FIA-style plot clusters. [`lidR_PlotMetrics.R`](lidR_PlotMetrics.R) summarizes lidar returns within field plots and exports plot-level metrics.

The site-placement script writes potential sampling locations for field crews. The plot-metrics script is configured separately to post process the plots that the field crews actually collect; update its geodatabase path and layer to the field data containing `PlotID` values after sampling.

## Site placement (`sgsR_SitePlacement.R`)

The site-placement script uses `zq90_plus2` and `rumple_index` grid rasters to define strata across the forested extent of the lidar acquisition and select sampling locations. Its key steps are:

1. Align the two metric rasters and mask them to the forested-area boundary before calculating strata.
2. Cap each metric at its 99.99th-percentile value and retain cells with valid values for both metrics.
3. Stack the metrics and use `sgsR::strat_quantiles()` to divide each metric into four quantiles, creating 16 combined strata.
4. Calculate each stratum's population proportion from the full forested-area stratification raster. These weights are calculated before applying public-land and access-zone masks, so they represent the forest population rather than only the eligible sampling area.
5. Crop and mask the stratification raster to public land and the configured surface-corrected access zone.
6. Use `sgsR::sample_strat()` to select stratum-weighted center plots, with the road/trail network, minimum-distance, and inner/outer buffer constraints.
7. Keep candidate centers 20–242 m (~0.15 mile) from the access network, then create three cluster plots around each center in a triangular FIA-style sample design. The cluster plots are 120 ft N, SE, and SW from the center placed .
8. Remove points that are closer than 120 ft, favoring the more frequent stratum when resolving conflicts, recheck access distance and strata, extract the metric values, and write the sample points to a file geodatabase.

### Site-placement inputs and settings

Edit the **Inputs** and **Outputs** sections near the top of `sgsR_SitePlacement.R` for the project:

| Setting | Purpose | Current default |
| --- | --- | --- |
| `root_dir` | Root folder for input data and outputs | `E:/lidar_Project/SiteSelection` |
| `zq90_plus2_path`, `rumple_index_path` | Grid metric rasters used to build the population | Files under `lidar_Metrics/` |
| `forested_area_path` | Boundary used to define the forested population | `Inputs/Forested_Area.gdb` |
| `public_land_gdb_path` | Public-land boundary | `Inputs/Public_Land.gdb` |
| `access_gdb_path`, `access_zone_path` | Road/trail network and eligible access zone | Files under `Inputs/` |
| `nstrata_zq90`, `nstrata_rumple` | Number of quantile classes per metric | 4 each (16 combined strata) |
| `n_samp` | Requested number of center plots | 125 |
| `mindist` | Minimum spacing used by stratified sampling, in map units | 300 |

The script assumes projected data with distances in meters. Verify raster alignment, coordinate reference systems, and units before processing. The population metric raster and full-population strata raster are intended to be generated once; the script includes commented read-from-disk alternatives for later runs. Recalculate the stratum weights if the forest mask or metric rasters change.

### Site-placement outputs

The configured outputs are written under `root_dir/Outputs/`:

- `mraster_zq90plus2_rumple.tif` — aligned, forest-masked metric stack.
- `sraster_population_16_strata.tif` — combined strata over the full forested population.
- `sraster_sampling_area_16_strata.tif` — strata restricted to public land and the access zone.
- `Sampling_Points.gdb` — sampled and clustered plot locations with extracted metric values.

### Site-placement packages and run notes

`sgsR_SitePlacement.R` installs and loads `lidR`, `sgsR`, `terra`, `sf`, `ggplot2`, and `mapview`. Review the paths and distance settings, then run the script. On the first run, the active raster-building sections create the metric stack and population strata. For later runs, the script includes commented options to load those saved rasters instead; use those options when the underlying metric rasters and forest mask have not changed.

## Plot-level lidar metrics

[`lidR_PlotMetrics.R`](lidR_PlotMetrics.R) calculates lidar metrics for field plots from a height-normalized LAS/LAZ catalog. It summarizes returns inside each circular plot area and writes one row of metrics per plot to a dated CSV.

## Relationship to the grid-metrics workflow

[`lidR_PlotMetrics.R`](lidR_PlotMetrics.R) is the plot-level companion to [`lidRmetrics.R`](../02_grid_metrics/lidRmetrics.R). Both workflows use `lidR` and `lidRmetrics` to describe lidar structure. The grid workflow summarizes points in raster cells; this workflow summarizes points within field-plot radii and exports a table keyed by plot.

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
| `ctg_folder` | Folder containing normalized LAS/LAZ files | `D:/lidar_Project/Data/LAS/Normalized` |
| `root_dir` | Root folder for plot metrics and clipped plot point clouds | `D:/lidar_Project/GroundPlots/CollectedPlots` |
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

## Plot-metrics packages

The script installs missing CRAN packages and loads:

- `lidR`, `sf`, `mapview`, `dplyr`, and `vroom`
- `Lmoments`, `lmom`, `moments`, and `geometry`, used by selected `lidRmetrics` functions
- [`lidRmetrics`](https://github.com/ptompalski/lidRmetrics), installed from GitHub if it is not already available

## Running the plot-metrics script

1. Confirm the input paths, plot layer, plot radius, and point filters.
2. Confirm that the plot layer has `PlotID` values and a projected CRS compatible with the catalog.
3. Open `lidR_PlotMetrics.R` in RStudio and run the script.
4. Review the generated CSV and plot LAS/LAZ files, including plot IDs, metric columns, missing values, and point coverage.

This workflow does not set up future-based parallel processing for `plot_metrics()`. The script comments note that future-based parallel processing can slow this plot workflow.
