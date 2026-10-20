###############################################################################
# Script Name: Lidar Plot Metrics for Area-Based Modeling
# Description:
#   Calculates plot-level lidar metrics for field inventory plots using a
#   height-normalized LAS/LAZ catalog. Metrics are calculated for first and all
#   returns and exported as a tabular dataset for area-based modeling (ABA).
#
# Processing steps:
#   1. Read field-plot locations and a normalized LAS/LAZ catalog
#   2. Transform plot locations to the catalog coordinate reference system
#   3. Filter noise, withheld points, and points outside the height range
#   4. Calculate height, percentile, dispersion, canopy-density, L-moment,
#      percentage-above-threshold, and rumple metrics for each plot
#   5. Remove selected point-count and minimum/maximum height fields
#   6. Export the plot-level metrics to a dated CSV file
#
# Inputs:
#   - Height-normalized LAS/LAZ files in a consistent projected CRS
#   - Field-plot point locations containing a PlotID field
#   - Plot radius in meters
#
# Outputs:
#   - Dated CSV file containing plot-level lidar metrics
#   - Plot-level LAS files written to the configured output directory
#
# Requirements:
#   - R packages: lidR, lidRmetrics, sf, mapview, dplyr, vroom, Lmoments,
#     lmom, moments, and geometry
#
# Notes:
#   - Do not use future-based parallel processing with plot_metrics(); it can
#     slow this workflow.
#   - Review the catalog filter and maximum-height threshold before use. The
#     current filter removes classes 7 and 18, negative heights, withheld
#     points, and points above 115 meters.
#   - Verify that the plot radius and catalog horizontal units are compatible.
#
# Author: Cody Dangerfield
# Last Updated: October 13, 2026
###############################################################################

## ---- User Inputs ----

# Directory containing the normalized LAS/LAZ catalog
ctg_folder <- "D:/Lidar_Project/Data/LAS/Normalized"

# Root directory containing the field-plot data. The plot-metrics CSV and
# clipped LAS files for individual plots will also be written here.
root_dir <- "D:/Lidar_Project/GroundPlots/CollectedPlots"

# Field-plot data source
plots_gdb <- file.path(
  root_dir,
  "Collected_Plots.gdb"
)
# You can use st_layers(plots_gdb) to list the layers in the geodatabase and identify the correct layer name for your plots.
plots_layer <- "Collected_Plots_2026"

# Plot radius in meters; 8.01624 m is approximately a 1/20-acre plot
plot_radius <- 8.01624

# Output locations
output_plot_metrics <- file.path(
  root_dir,
  paste0("Plot_Metrics_", format(Sys.Date(), "%Y%m%d"), ".csv")
)
plot_las_output <- file.path(root_dir, "Plot_LAS_Files", "{PlotID}")

## ---- Install & Load Packages ----
# Lmoments, lmom, moments, and geometry are installed explicitly because
# lidRmetrics uses them for selected metrics but does not declare all of them
# as package dependencies.
cran_packages <- c(
  "lidR", "sf", "mapview", "dplyr", "vroom",
  "Lmoments", "lmom", "moments", "geometry"
)

missing_cran_packages <- cran_packages[
  !vapply(cran_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_cran_packages) > 0) {
  install.packages(
    missing_cran_packages,
    repos = "https://cloud.r-project.org",
    dependencies = TRUE
  )
}

# lidRmetrics is not on CRAN, so install it and its dependencies from GitHub.
if (!requireNamespace("lidRmetrics", quietly = TRUE)) {
  message("lidRmetrics not found. Installing from GitHub...")
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", repos = "https://cloud.r-project.org")
  }
  remotes::install_github(
    "ptompalski/lidRmetrics",
    dependencies = TRUE,
    upgrade = "never"
  )
}

invisible(lapply(cran_packages, library, character.only = TRUE))

# Set mapview basemaps to Esri World Imagery, Esri World Topo Map, USGS USTopo, and OpenStreetMap
mapviewOptions(basemaps = c("Esri.WorldImagery", "Esri.WorldTopoMap", "USGS.USTopo", "OpenStreetMap"))

## ---- Read Field Plots and LAS Catalog ----
plots <- st_read(plots_gdb, layer = plots_layer)

## Filtering plot data to include only PlotID 
plots <- plots |>
  dplyr::select(c(PlotID)) |>
  st_zm()

# Read the catalog of LAS/LAZ files to be clipped
ctg <- readLAScatalog(folder = ctg_folder)
plot(ctg)
plot(ctg, map =T) +
  mapview(
    plots,
    col.regions = "red",
    color = "red",
    alpha.regions = 0.6,
    lwd = 1,
    layer.name = "Plots",
    legend = FALSE
  ) 

## Projecting the plots to match the CRS of the LAS catalog
plots <- st_transform(plots, st_crs(ctg))

## lidR catalog options for processing
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld -drop_z_above 115"

## Export plot-level LAS files for each plot to a subdirectory within the root directory
opt_output_files(ctg) <- plot_las_output


## ---- Height Statistics Func ----

elev_metrics <- function(x, y, z,
                             zmin = NA,
                             threshold = c(2),
                             dz = 1,
                             interval_count = 10,
                             zintervals = c(0, 0.5, 1, 2, 4, 8, 16, 32, 48, 64),
                             pixel_size = 1) {

  # ----------------------------
  # 1. ORIGINAL metrics_custom
  # ----------------------------
  m_percab  <- lidRmetrics::metrics_percabove(z=z, threshold = threshold)
  m_rumple  <- lidRmetrics::metrics_rumple(x = x, y = y, z = z, pixel_size = pixel_size)


  if (is.na(zmin)) {
    m_basic   <- lidRmetrics::metrics_basic(z=z)
    m_prctls  <- lidRmetrics::metrics_percentiles(z=z)
    m_disp    <- lidRmetrics::metrics_dispersion(z=z, dz=dz)
    m_candens <- lidRmetrics::metrics_canopydensity(z=z, interval_count = interval_count)
    m_lmom    <- lidRmetrics::metrics_Lmoments(z=z)
    m_lad     <- lidRmetrics::metrics_lad(z=z)
    # m_int     <- metrics_interval(z=z, zintervals = zintervals)

  } else {
    # Add z > zmin versions of same metrics
    zmin <- zmin
    zmin_label <- paste0("_plus", zmin)

    m_basic_filtered   <- lidRmetrics::metrics_basic(z=z, zmin=zmin)
    names(m_basic_filtered) <- paste0(names(m_basic_filtered), zmin_label)

    m_prctls_filtered  <- lidRmetrics::metrics_percentiles(z=z, zmin=zmin)
    names(m_prctls_filtered) <- paste0(names(m_prctls_filtered), zmin_label)

    m_percab_filtered  <- lidRmetrics::metrics_percabove(z=z, threshold = threshold, zmin=zmin)
    names(m_percab_filtered) <- paste0(names(m_percab_filtered), zmin_label)

    m_disp_filtered    <- lidRmetrics::metrics_dispersion(z=z, dz=dz, zmin=zmin)
    names(m_disp_filtered) <- paste0(names(m_disp_filtered), zmin_label)

    m_candens_filtered <- lidRmetrics::metrics_canopydensity(z=z, interval_count = interval_count, zmin = zmin)
    names(m_candens_filtered) <- paste0(names(m_candens_filtered), zmin_label)

    m_lmom_filtered    <- lidRmetrics::metrics_Lmoments(z=z, zmin=zmin)
    names(m_lmom_filtered) <- paste0(names(m_lmom_filtered), zmin_label)

    # m_lad_filtered     <- lidRmetrics::metrics_lad(z=z, zmin=zmin)
    # names(m_lad_filtered) <- paste0(names(m_lad_filtered), zmin_label)

    # m_int_filtered    <- metrics_interval(z=z, zmin=zmin, zintervals = zintervals)
    # names(m_int_filtered) <- paste0(names(m_int_filtered), zmin_label)
  }

  # ----------------------------
  # 2. COMBINE ALL METRICS
  # ----------------------------

  if (is.na(zmin)) {
    m <- c(m_basic, m_prctls, m_percab, m_disp, m_candens, m_lmom,  m_rumple)

  } else {
    m <- c(m_basic_filtered, m_prctls_filtered, m_percab, m_disp_filtered, m_candens_filtered, m_lmom_filtered,  m_rumple)
  }

  return(m)
}

## Running plot_metrics to calculate height statistics for each plot in the field-plot dataset for both first and all returns.
Plot_Metrics <- plot_metrics(ctg,  ~elev_metrics(X, Y,
      Z, zmin = 2), plots, radius = plot_radius,
  by_echo = c("first", "all"))

## Renaming the column names of the plot metrics table to replace periods with underscores
colnames(Plot_Metrics)<-gsub("\\.", "_", colnames(Plot_Metrics))

## Removing the geometry column from the plot metrics table to prepare for export
Plot_Metrics_tble<-Plot_Metrics %>%
  st_drop_geometry()
dim(Plot_Metrics)


## Drop point counts or min/max variables 
Plot_Metrics_tble <- Plot_Metrics_tble |>
  dplyr::select(-c(n_plus2, n_plus2_first, zmax_plus2, zmin_plus2, zmax_plus2_first, zmin_plus2_first)) 

## Print the column names of the plot metrics table
colnames(Plot_Metrics_tble)

## Export the plot metrics table to a CSV file
vroom_write(Plot_Metrics_tble, output_plot_metrics, delim = ",")
