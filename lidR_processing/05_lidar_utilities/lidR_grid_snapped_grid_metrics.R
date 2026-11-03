###############################################################################
# Script: Grid-Snapped Pixel/Grid Metrics
# Description:
#   Demonstrates how to calculate pixel-level lidar metrics using an existing
#   raster as the grid template for pixel_metrics(). The example calculates
#   rumple index, but the same approach can be used for any metric expression supported by pixel_metrics().
#
#   A shared reference grid is especially useful when metrics are generated
#   separately for multiple lidar acquisitions. If each acquisition creates its
#   own default grid, the grid origin and extent are derived independently from
#   that acquisition's bounding box. Even when cell sizes match, adjacent
#   outputs may not have coincident cell boundaries.
#
#   Using the same reference raster for every acquisition preserves a common
#   CRS, grid origin, cell size, and cell alignment. The resulting metric tiles
#   can therefore be mosaicked without resampling, which avoids altering metric
#   values, grid geometry, or effective spatial resolution.
#
# Processing steps:
#   1. Read and inspect a normalized LAS/LAZ catalog
#   2. Read an existing raster that defines the desired output grid
#   3. Verify that the catalog and reference raster use the same CRS
#   4. Retain surface points and calculate rumple index with pixel_metrics(). Change to another metric expression as needed.
#   5. Write metric rasters aligned to the reference grid
#
# Inputs:
#   - Height-normalized LAS/LAZ files in a consistent projected CRS
#   - A reference raster with the desired CRS, origin, resolution, and alignment
#
# Outputs:
#   - Grid-aligned rumple-index raster tiles
#
# Requirements:
#   - R packages: lidR, future, sf, and raster
#
# Notes:
#   - Use the same reference raster for every acquisition that will be mosaicked.
#   - The output metric raster will have the same cell resolution as the
#     reference raster.
#   - The reference raster establishes the grid geometry; it does not transform
#     point coordinates. The LAS/LAZ catalog and raster must use the same CRS.
#   - Set the chunk buffer in the catalog CRS units. A buffer reduces edge
#     effects when metrics are calculated near source-tile boundaries.
#   - The rumple-index calculation is an example. Replace the metric expression
#     inside pixel_metrics() to calculate another grid-aligned metric.
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing normalized LAS/LAZ files
folder <- "D:/Lidar_Project/LAS/Normalized"

# Existing raster that defines the output grid
reference_raster_path <- "D:/Lidar_Project/Reference/reference_grid_5m.tif"

# Directory and filename template for metric outputs
output_folder <- "D:/Lidar_Project/Metrics/Rumple"
output_template <- file.path(output_folder, "{*}_rumple_5m")

# Parallel processing and catalog settings
n_workers <- 12
chunk_buffer <- 30

# ---- 1 Install and load libraries ----
list_of_packages <- c("lidR", "future", "sf", "raster")
new_packages <- list_of_packages[
  !vapply(list_of_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(new_packages) > 0) {
  install.packages(
    new_packages,
    dependencies = TRUE,
    repos = "https://cloud.r-project.org"
  )
}

invisible(lapply(list_of_packages, library, character.only = TRUE))

options(future.globals.maxSize = Inf)
plan(multisession, workers = n_workers, gc = TRUE)
# Set mapview basemaps to Esri World Imagery, Esri World Topo Map, USGS USTopo, and OpenStreetMap
mapviewOptions(basemaps = c("Esri.WorldImagery", "Esri.WorldTopoMap", "USGS.USTopo", "OpenStreetMap"))

# ---- 2 Configure and inspect the LAS catalog ----
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)

ctg <- readLAScatalog(folder = folder)
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)

opt_chunk_buffer(ctg) <- chunk_buffer
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld"
opt_output_files(ctg) <- output_template
opt_progress(ctg) <- TRUE
summary(ctg)

ctg@output_options$drivers$Raster$param$overwrite <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

# ---- 3 Read and validate the reference grid ----
ref_raster <- raster(reference_raster_path)

if (is.na(st_crs(ctg)) || is.na(st_crs(ref_raster))) {
  stop("The catalog and reference raster must both have a valid CRS.", call. = FALSE)
}

if (st_crs(ctg) != st_crs(ref_raster)) {
  stop(
    "The catalog and reference raster use different coordinate systems.",
    call. = FALSE
  )
}

# ---- 4 Calculate metrics on the reference grid ----
grid_rumple_index <- function(las, ref_raster) {
  las <- filter_surfacepoints(las, 1)
  pixel_metrics(las, ~rumple_index(X, Y, Z), ref_raster)
}

metrics <- catalog_map(ctg, grid_rumple_index, ref_raster)

# ---- 5 Cleanup ----
plan(sequential)

