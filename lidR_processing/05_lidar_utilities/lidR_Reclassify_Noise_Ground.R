###############################################################################
# Script Name: Reclassify Lidar Noise and Ground Points
# Description:
#   Applies statistical outlier removal (SOR) and a selected ground-
#   classification algorithm to a LAS/LAZ catalog. Users can process the whole
#   catalog or spatially subset it to tiles intersecting an area of interest.
#
# WARNING:
#   Noise and ground classification parameters are acquisition-specific.
#   Aggressive filtering can remove valid canopy returns, while conservative
#   filtering can leave noise unclassified. Review the vendor report, inspect
#   representative tiles, and validate output classifications before using
#   them in terrain, canopy, or forest-metric workflows.
#
# Processing steps:
#   1. Read and inspect the LAS/LAZ catalog
#   2. Optionally select catalog tiles intersecting an AOI
#   3. Classify SOR outliers as noise and remove them from the output
#   4. Classify ground using the selected lidR algorithm
#   5. Remove processing-buffer points and write reclassified tiles
#
# Inputs:
#   - LAS/LAZ files in a consistent projected CRS
#   - Optional AOI for selecting only intersecting catalog tiles
#
# Outputs:
#   - LAS/LAZ files with reclassified ground points and filtered noise
#
# Requirements:
#   - R packages: lidR, sf, and future
#
# Notes:
#   - SOR values k = 15 and m = 3 provide a relatively conservative filter.
#     CloudCompare defaults to k = 6 and m = 1, which is more
#     aggressive.
#   - Large swaths of vendor-missed noise may require manual editing or more
#     aggressive filtering, which also increases the risk of removing valid
#     canopy returns. Apply reclassification methods carefully.
#   - PTD, PMF, and MCC examples are provided because all three have worked
#     reasonably
#     well in prior workflows. The lidR authors recommend PTD for ground
#     classification. In prior tests, PTD processed data approximately eight
#     times faster, although it showed a greater tendency to classify low
#     vegetation as ground on steep terrain. PMF and MCC were less prone to
#     extending the ground classification into vegetation, but they performed
#     less consistently on steep slopes, sometimes produced interpolation
#     artifacts, and could smooth over fine-scale topographic variation. MCC was
#     modestly faster than PMF in those tests. Performance and classification
#     quality will vary with terrain, vegetation, point density, and parameter
#     selection. Users will need to fine-tune these methods and determine which
#     is most appropriate for their acquisition.
#   - General PTD starting ranges for forested, mountainous terrain are
#     res = 10-20, angle = 40-70 degrees, and distance = 0.25-3 CRS units.
#     These are starting points, not universal settings.
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Input and output directories
folder <- "D:/Lidar_Project/LAS"
output_folder <- "D:/Lidar_Project/LAS_Reclassified"

# Parallel processing and catalog settings
n_workers <- 8

# ---- 1 Install and load libraries ----
list_of_packages <- c("lidR", "sf", "future")
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
plan(multisession, workers = n_workers, gc = TRUE)
# Set mapview basemaps to Esri World Imagery, Esri World Topo Map, USGS USTopo, and OpenStreetMap
mapviewOptions(basemaps = c("Esri.WorldImagery", "Esri.WorldTopoMap", "USGS.USTopo", "OpenStreetMap"))

# ---- 2 Define the noise and ground classification function ----
noise_ground_classification <- function(chunk) {
  las <- readLAS(chunk)
  if (is.empty(las)) {
    return(NULL)
  }

  # ---- Noise Classification ----
  # Noise classification: k = neighbors; m = standard-deviation multiplier
  noise_sor_k <- 15
  noise_sor_m <- 3

  # Classify SOR outliers as noise, then omit those points from the output.
  las <- classify_noise(las, sor(k = noise_sor_k, m = noise_sor_m))
  las <- filter_poi(las, Classification != LASNOISE)

  # ---- Ground Classification ----
  # PTD is active by default. To use another method, comment out this call and
  # uncomment an alternative below. These examples are not an exhaustive list
  # of the ground-classification algorithms supported by lidR.
  # Progressive TIN Densification parameters (active example)
  ptd_resolution <- 15
  ptd_angle <- 45
  ptd_distance <- 2
  ptd_spacing <- 0.25

  # Progressive TIN Densification
  las <- classify_ground(
    las,
    ptd(
      res = ptd_resolution,
      angle = ptd_angle,
      distance = ptd_distance,
      spacing = ptd_spacing,
      verbose = TRUE
    ),
    last_returns = TRUE
  )

  # Alternative Multiscale Curvature Classification parameters
  # mcc_scale <- 1.5
  # mcc_threshold <- 0.3

  # Multiscale Curvature Classification
  # las <- classify_ground(
  #   las,
  #   mcc(mcc_scale, mcc_threshold),
  #   last_returns = TRUE
  # )

  # Alternative Progressive Morphological Filter parameters
  # pmf_window_sizes <- seq(3, 12, 3)
  # pmf_thresholds <- seq(
  #   0.1,
  #   1.5,
  #   length.out = length(pmf_window_sizes)
  # )

  # Progressive Morphological Filter
  # las <- classify_ground(
  #   las,
  #   pmf(ws = pmf_window_sizes, th = pmf_thresholds),
  #   last_returns = TRUE
  # )

  # Exclude points loaded only to provide processing context at chunk edges.
  filter_poi(las, buffer == 0)
}

# ---- 3 Read and optionally subset the LAS catalog ----
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
ctg <- readLAScatalog(folder = folder)
plot(ctg, map = TRUE)

# By default, process the entire catalog.
ctg_processing <- ctg

# To reprocess only tiles intersecting an AOI, uncomment and update this block.
# catalog_intersect() spatially selects catalog tiles; it does not clip points
# to the AOI boundary. The optional buffer includes neighboring context.
# classification_aoi <- st_read("D:/Lidar_Project/AOI/reclassification_aoi.gpkg")
# classification_aoi <- st_transform(classification_aoi, crs = st_crs(ctg))
# classification_aoi <- st_buffer(classification_aoi, dist = 20)
# ctg_processing <- catalog_intersect(
#   ctg,
#   classification_aoi,
#   subset = "flag_processed"
# )

plot(ctg_processing, chunk_pattern = TRUE)
plot(ctg_processing, map = TRUE)

# ---- 4 Configure and process the selected catalog ----
opt_chunk_buffer(ctg_processing) <- 30
opt_filter(ctg_processing) <-
  "-drop_class 7 18 -drop_z_below 0 -drop_withheld"
opt_output_files(ctg_processing) <- file.path(output_folder, "{*}")
opt_progress(ctg_processing) <- TRUE

processing_options <- list(need_buffer = TRUE, automerge = FALSE)
catalog_apply(
  ctg_processing,
  noise_ground_classification,
  .options = processing_options
)

# ---- 5 Cleanup ----
plan(sequential)
