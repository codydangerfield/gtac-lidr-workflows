# ---- LiDAR Normalization and Canopy Height Model Workflow ----
# Description:
# This script processes raw LiDAR point cloud data to:
#   1. Create .lax spatial index files
#   2. Generate Digital Elevation Models (DEMs)
#   3. Normalize the LiDAR point cloud to ground
#   4. Produce a Canopy Height Model (CHM)
#
# Outputs include normalized LAS files, DEM rasters, and CHMs
# for further processing (e.g., tree detection and segmentation).
# 
# Run the script one section at a time.
# Avoid running the entire script with Ctrl+A followed by Ctrl+Enter.
#
# Author: Cody Dangerfield
# Last Updated: September 17, 2026

# ---- Install and load libraries ----
cran_packages <- c("sf", "terra", "raster", "future", "mapview")
missing_cran_packages <- cran_packages[
  !vapply(cran_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_cran_packages) > 0) {
  install.packages(missing_cran_packages, repos = "https://cloud.r-project.org")
}

if (!requireNamespace("lidR", quietly = TRUE)) {
  install.packages(
    "lidR",
    repos = c("https://r-lidar.r-universe.dev", "https://cloud.r-project.org")
  )
}

library(lidR)
library(future)
library(sf)
library(raster)
library(terra)
library(mapview)

# ---- USER CONFIGURATION ----
# Modify these parameters as needed
n_workers <- 8          # Number of parallel workers
buffer_size <- 30        # Buffer size for processing chunks (adjust based on CRS units: meters or feet)
dem_resolution <- 1      # DEM resolution (adjust based on CRS units: meters or feet)
chm_resolution <- 1    # CHM resolution (adjust based on CRS units: meters or feet)
max_height <- 115        # Maximum tree height filter (adjust based on CRS units: meters or feet) 115 m ~ 377 ft

# ---- Define LAS/LAZ input folder ----
folder <- "D:/LAS"

# ---- Setup parallel processing ----
options(future.globals.maxSize = Inf)
plan(multisession, workers = n_workers, gc = TRUE)

# ---- lidR Restart Methods (examples) ----
## If your catalog processing crashes, you can restart from a specific chunk
## or re-run only unprocessed chunks. Place these lines where appropriate:

##   - above lidR:::catalog_laxindex(ctg)
##   - above rasterize_terrain()
##   - above normalize_height()
##   - above rasterize_canopy()

## Option 1: For overall restarts
# opt_restart(ctg) <- 50 # number of the chunk that failed

## Option 2: To run specific LAS files/chunks
# ctg$processed <- FALSE
# ctg$processed[c(50:58, 64:550)] <- TRUE # Specify chunks to reprocess

# ---- Create .lax files ----
ctg <- readLAScatalog(folder = folder)
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)
opt_chunk_buffer(ctg) <- 0
opt_progress(ctg) <- TRUE
summary(ctg)

# Example of restarting the catalog engine:
## Option 1: For overall restarts
# opt_restart(ctg) <- 50 # number of the chunk that failed

## Option 2: To run specific LAS files/chunks
# ctg$processed <- FALSE
# ctg$processed[c(50:58, 64:550)] <- TRUE # Specify chunks to reprocess

lidR:::catalog_laxindex(ctg)

# ---- Create DEMs ----
ctg <- readLAScatalog(folder = folder)
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)

# Detect CRS units for consistent naming
catalog_crs <- st_crs(ctg)
if (is.na(catalog_crs)) {
  stop(
    "The CRS of the LAS catalog is NA. Check the catalog CRS and assign one before continuing. ",
    "Quick fix: st_crs(ctg) <- ####  # Replace #### with the correct EPSG code.",
    call. = FALSE
  )
}

crs_units <- catalog_crs$units_gdal
if(crs_units %in% c("meter", "metre")) {
  unit_suffix <- paste0(gsub("\\.", "p", dem_resolution), "m")
} else if(crs_units == "US survey foot" || crs_units == "foot") {
  unit_suffix <- paste0(gsub("\\.", "p", dem_resolution), "ft")
} else {
  unit_suffix <- paste0(gsub("\\.", "p", dem_resolution), "units")
}

opt_chunk_buffer(ctg) <- buffer_size
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld"
opt_output_files(ctg) <- paste0(folder, "/DEM/", "{*}_DEM_", unit_suffix)
opt_progress(ctg) <- TRUE
summary(ctg)

ctg@output_options$drivers$Raster$param$overwrite <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

rasterize_terrain(ctg, res = dem_resolution, algorithm = tin())

# ---- Normalize Point Cloud ----
ctg <- readLAScatalog(folder = folder)
plot(ctg, chunk_pattern = TRUE)
plot(ctg, map = TRUE)

opt_chunk_buffer(ctg) <- buffer_size
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld"
opt_progress(ctg) <- TRUE
opt_output_files(ctg) <- paste0(folder, "/Normalized/", "{*}_Normalized")
ctg@output_options$drivers$LAS$param <- list(index = TRUE) ## Enable LAS indexing for faster access
summary(ctg)

normalized <- normalize_height(ctg, tin())


# ---- Create CHM ----
ctg <- readLAScatalog(folder = paste0(folder, "/Normalized"))
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)

# Detect CRS units for consistent naming
catalog_crs <- st_crs(ctg)
if (is.na(catalog_crs)) {
  stop(
    "The CRS of the LAS catalog is NA. Check the catalog CRS and assign one before continuing. ",
    "Quick fix: st_crs(ctg) <- ####  # Replace #### with the correct EPSG code.",
    call. = FALSE
  )
}

crs_units <- catalog_crs$units_gdal
if(crs_units %in% c("meter", "metre")) {
  unit_suffix <- paste0(gsub("\\.", "p", chm_resolution), "m")
} else if(crs_units == "US survey foot" || crs_units == "foot") {
  unit_suffix <- paste0(gsub("\\.", "p", chm_resolution), "ft")
} else {
  unit_suffix <- paste0(gsub("\\.", "p", chm_resolution), "units")
}
opt_chunk_buffer(ctg) <- buffer_size
opt_filter(ctg) <- paste0("-drop_class 7 18 -drop_z_below 0 -drop_z_above ", max_height, " -drop_withheld")
opt_output_files(ctg) <- paste0(folder, "/Normalized/CHM/", "{*}_CHM_", unit_suffix)
opt_progress(ctg) <- TRUE
summary(ctg)

ctg@output_options$drivers$Raster$param$overwrite <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

chm <- rasterize_canopy(
  ctg,
  res = chm_resolution,
  algorithm = p2r(
    subcircle = chm_resolution / 2,
    na.fill = knnidw(k = 10, p = 2, rmax = 2)
  )
)


# ---- Cleanup ----
plan(sequential)  # Reset to sequential processing





