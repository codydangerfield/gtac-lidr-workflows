###############################################################################
# Script Name: Lidar Acquisition Date Extraction
# Description:
#   Extracts the minimum and maximum GPS time from each LAS/LAZ catalog tile
#   and writes a tile-footprint polygon containing the acquisition date,
#   flight start time, and flight end time. The individual footprint files are
#   then merged into one file geodatabase.
#
# Processing steps:
#   1. Read the LAS/LAZ catalog with only the GPS-time attribute
#   2. Process first returns and extract each tile's GPS-time range
#   3. Create and write a bounding-box footprint for each tile
#   4. Read the footprint files in parallel and merge them
#   5. Write the merged footprints to a file geodatabase
#
# Inputs:
#   - LAS/LAZ files containing valid GPS time values
#
# Outputs:
#   - One GeoPackage footprint for each catalog tile
#   - One merged file geodatabase containing all footprints and dates
#
# Requirements:
#   - R packages: lidR, sf, future, future.apply, and progressr
#
# Notes:
#   - This script was developed to estimate acquisition dates when the lidar
#     vendor did not supply them. Use vendor-provided acquisition-date products
#     whenever they are available.
#   - The time conversion assumes adjusted standard GPS time: LAS GPS time plus
#     1 billion seconds, measured from the GPS epoch of 1980-01-06 UTC.
#   - GPS time does not include leap seconds. Verify converted timestamps
#     against acquisition documentation when exact UTC time is important.
#   - Review the worker counts based on available processors and memory.
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing the LAS/LAZ files
folder <- "D:/Lidar_Project/LAS"

# Output directory and merged geodatabase name
output_folder <- file.path(dirname(folder), "AcquisitionDates")
output_gdb <- "AcquisitionDates.gdb"

# Parallel workers used for catalog processing and footprint merging
workers <- 8

# ---- 1 Install and load libraries ----
list_of_packages <- c(
  "lidR", "sf", "future", "future.apply", "progressr"
)

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

# ---- 2 Configure and inspect the LAS catalog ----
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
options(future.globals.maxSize = Inf)
plan(multisession, workers = workers, gc = TRUE)

ctg <- readLAScatalog(folder = folder, select = "t")
plot(ctg, map = TRUE)
plot(ctg, chunk_pattern = TRUE)
opt_filter(ctg) <- "-keep_first"
opt_chunk_buffer(ctg) <- 0
opt_progress(ctg) <- TRUE
opt_output_files(ctg) <- file.path(output_folder, "{*}_footprint")
summary(ctg)

ctg@output_options$drivers$sf$extension <- ".gpkg"
ctg@output_options$drivers$sf$param$append <- FALSE

# ---- 3 Extract acquisition dates and tile footprints ----
acquisition_dates_extraction <- function(las) {
  if (is.empty(las)) {
    return(NULL)
  }
  
  # Extract GPS time range
  t_min <- min(las@data$gpstime, na.rm = TRUE)
  t_max <- max(las@data$gpstime, na.rm = TRUE)
  
  # Convert the tile bounding box to a polygon
  footprint_geom <- sf::st_as_sfc(sf::st_bbox(las))

  # Attach the converted acquisition timestamps to the footprint
  footprint <- sf::st_sf(
    acquisition_date = format(as.POSIXct(t_min + 1e9, origin = "1980-01-06", tz = "UTC"), "%Y-%m-%d"),
    flight_start = as.POSIXct(t_min + 1e9, origin = "1980-01-06", tz = "UTC"),
    flight_end = as.POSIXct(t_max + 1e9, origin = "1980-01-06", tz = "UTC"),
    geometry = footprint_geom
  )

  footprint
}

# Process the catalog and write one footprint GeoPackage per tile
catalog_map(ctg, acquisition_dates_extraction)

# ---- 4 Merge footprint outputs ----
plan(multisession, workers = workers, gc = TRUE)

file_list <- list.files(
  output_folder,
  pattern = "\\.gpkg$",
  full.names = TRUE
)

if (length(file_list) == 0L) {
  stop("No footprint GeoPackage files were found to merge.", call. = FALSE)
}

handlers("txtprogressbar")

with_progress({
  p <- progressor(steps = length(file_list))
  list_of_sf_objects <- future_lapply(file_list, function(file) {
    sf_object <- st_read(file, quiet = TRUE)
    p()
    sf_object
  })
})

footprints <- do.call(rbind, list_of_sf_objects)
st_write(
  footprints,
  file.path(output_folder, output_gdb),
  append = FALSE
)

# ---- 5 Cleanup ----
plan(sequential)
