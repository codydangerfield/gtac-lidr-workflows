###############################################################################
# Script Name: lasR Noise and Ground Reclassification with DTM Generation
# Description:
#   Demonstrates a high-performance lasR pipeline that removes existing noise,
#   detects additional statistical outliers, classifies ground, creates digital
#   terrain models (DTMs), and writes cleaned LAZ files.
#
#   lasR is a newer lidar-processing package built around a high-performance
#   C++ engine. It chains operations into optimized pipelines and generally
#   uses less memory than workflows that load point clouds into R objects. When
#   lasR and lidR provide equivalent operations, lasR will generally be the
#   faster option for large production workflows.
#
#   Review the current lasR documentation for current functionality and tutorials 
#   as the package is actively developing: https://r-lidar.github.io/lasR/index.html
#
# Processing steps:
#   1. Read each LAS/LAZ file through a lasR pipeline
#   2. Remove points already classified as noise
#   3. Detect additional noise with statistical outlier removal (SOR)
#   4. Remove the newly classified noise points
#   5. Classify ground with Progressive TIN Densification (PTD)
#   6. Generate a DTM and write the cleaned point cloud
#
# Inputs:
#   - LAS/LAZ files in a consistent projected CRS
#
# Outputs:
#   - Cleaned and ground-classified LAZ files
#   - DTM raster tiles
#
# Requirements:
#   - R package: lasR
#   - lasR is installed from the R-lidar R-universe, not CRAN
#
# Notes:
#   - Noise and ground-classification parameters are acquisition-specific.
#     Validate results on representative tiles before processing a full catalog.
#   - SOR values k = 15 and m = 3 provide a relatively conservative filter.
#   - The DTM resolution and PTD distance use the point cloud's CRS units.
#   - Choose a worker count appropriate for available CPU, memory, storage
#     speed, and the number and size of input files.
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing the input LAS/LAZ files
input_folder <- "D:/Lidar_Project/LAS"

# Output directories for cleaned point clouds and DTM raster tiles
output_folder <- "D:/Lidar_Project/lasR_Output"
dem_folder <- file.path(output_folder, "DEM")

# Number of files lasR may process concurrently
n_cores <- 8

# Classification and DTM parameters
noise_sor_k <- 15
noise_sor_m <- 3
ptd_angle <- 45
ptd_distance <- 2
dem_resolution <- 0.5

# ---- 1 Install and load lasR ----
if (!requireNamespace("lasR", quietly = TRUE)) {
  install.packages(
    "lasR",
    repos = c(
      "https://r-lidar.r-universe.dev",
      "https://cloud.r-project.org"
    )
  )
}

library(lasR)

# ---- 2 Prepare output directories ----
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
dir.create(dem_folder, recursive = TRUE, showWarnings = FALSE)

# ---- 3 Build the lasR processing pipeline ----
pipeline <- reader() +
  normalize() +
  # Write cleaned and ground-classified LAZ files.
  write_las(file.path(output_folder, "*_Normalized.laz"))

# ---- 4 Execute the pipeline ----
exec(
  pipeline,
  on = input_folder,
  ncores = n_cores,
  progress = TRUE
)
