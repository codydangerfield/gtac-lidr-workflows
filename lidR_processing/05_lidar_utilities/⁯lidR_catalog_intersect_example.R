###############################################################################
# Script Name: LAScatalog Spatial Selection with catalog_intersect()
# Description:
#   Demonstrates how to use lidR::catalog_intersect() to select LAScatalog
#   tiles that intersect an area of interest (AOI). The selected catalog is then
#   used in an example terrain-rasterization workflow.
#
#   This script is intended primarily as an example of catalog selection. The
#   same approach can be applied before other LAScatalog operations when only a
#   portion of an acquisition needs to be processed or reprocessed.
#
# Processing steps:
#   1. Read and inspect the complete LAS/LAZ catalog
#   2. Read and transform an AOI to the catalog CRS
#   3. Use catalog_intersect() to flag intersecting catalog tiles for processing
#   4. Review the selected tiles and AOI on an interactive map
#   5. Generate DEMs for the selected portion of the catalog as an example
#
# Inputs:
#   - A tiled LAS/LAZ catalog in a projected CRS
#   - A polygon AOI that identifies the area to process
#
# Outputs:
#   - Example DEM raster tiles for catalog tiles intersecting the AOI
#
# Requirements:
#   - R packages: lidR, sf, future, and mapview
#
# Notes:
#   - catalog_intersect() selects catalog tiles that intersect the AOI; it does
#     not clip point data exactly to the AOI boundary.
#   - Tiles crossing the AOI boundary remain complete catalog tiles during
#     selection. Use an appropriate clipping workflow when exact AOI geometry
#     is required in the output.
#   - Replace the DEM example with another LAScatalog operation as needed.
#   - Review all paths, CRS units, buffers, filters, and raster resolution
#     before adapting this example to a new acquisition.
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing the LAS/LAZ catalog
folder <- "D:/Lidar_Project/LAS"

# Polygon area of interest used to select intersecting catalog tiles
aoi_path <- "D:/Lidar_Project/AOI/processing_area.gpkg"

# Example DEM output directory and processing settings
output_folder <- file.path(dirname(folder), "DEM")
n_workers <- 3
chunk_buffer <- 30
dem_resolution <- 1

# ---- 1 Install and load libraries ----
list_of_packages <- c("lidR", "sf", "future", "mapview")
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

# ---- 2 Read the catalog and area of interest ----
ctg <- readLAScatalog(folder = folder)
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)

if (is.na(st_crs(ctg))) {
  stop("The LAScatalog must have a valid CRS before spatial selection.", call. = FALSE)
}

aoi <- st_read(aoi_path)
aoi <- st_transform(aoi, crs = st_crs(ctg))

# ---- 3 Select catalog tiles intersecting the AOI ----
# flag_processed retains the catalog structure and flags nonintersecting tiles
# as already processed so subsequent catalog operations skip them.
ctg_selected <- catalog_intersect(
  ctg,
  aoi,
  subset = "flag_processed"
)

plot(ctg_selected, chunk_pattern = TRUE)
plot(ctg_selected, map = TRUE) +
  mapview(
    aoi,
    color = "red",
    col.regions = "red",
    alpha.regions = 0.5,
    layer.name = "Area of interest"
  )

# ---- 4 Example: create DEMs for the selected catalog tiles ----
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
opt_chunk_buffer(ctg_selected) <- chunk_buffer
opt_filter(ctg_selected) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld"
opt_output_files(ctg_selected) <- file.path(
  output_folder,
  paste0("{*}_DEM_", dem_resolution)
)
opt_progress(ctg_selected) <- TRUE
summary(ctg_selected)

ctg_selected@output_options$drivers$Raster$param$overwrite <- TRUE
ctg_selected@output_options$drivers$SpatRaster$param$overwrite <- TRUE

rasterize_terrain(
  ctg_selected,
  res = dem_resolution,
  algorithm = tin()
)

# ---- 5 Cleanup ----
plan(sequential)
