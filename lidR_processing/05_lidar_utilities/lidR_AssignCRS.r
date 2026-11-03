###############################################################################
# Script: Overwrite LAS/LAZ Coordinate Reference System
# Description:
#   Copies LAS/LAZ files to a new directory and unconditionally replaces the
#   coordinate reference system (CRS) metadata in every output file. Files are
#   processed in parallel, and a LAX spatial index is written with each output.
#
# WARNING:
#   This script OVERWRITES the CRS metadata assigned to each output point
#   cloud. It does not reproject or transform point coordinates. Assigning an
#   incorrect CRS will cause the data to appear in the wrong location and may
#   invalidate subsequent spatial analysis. Use this script only when the
#   coordinates are already expressed in the target CRS and the existing CRS
#   metadata is missing or incorrect.
#
#   Always confirm the correct CRS from authoritative acquisition metadata or
#   vendor documentation. Write to a separate output directory, inspect the
#   results, and preserve the original LAS/LAZ files.
#
# Processing steps:
#   1. Find LAS and LAZ files in the configured input directory
#   2. Read each point-cloud file in parallel
#   3. Replace its CRS metadata without changing XYZ coordinates
#   4. Write the updated file and a LAX index to the output directory
#
# Inputs:
#   - LAS/LAZ files whose coordinates already use the target CRS
#   - Either a reference LAS/LAZ file with the correct CRS or an authoritative
#     target EPSG code
#
# Outputs:
#   - Copies of the LAS/LAZ files with replaced CRS metadata
#   - A LAX spatial index for every successfully written output file
#
# Requirements:
#   - R packages: lidR, sf, foreach, and doParallel
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing the LAS/LAZ files with missing or incorrect CRS metadata
folder <- "D:/Lidar_Project/LAS"

# Separate directory for corrected copies; do not use the input directory
out_folder <- "D:/Lidar_Project/LAS_CRS_Corrected"

# Choose one CRS source below. Comment out the unused option.

# Option 1: Copy the CRS from a reference LAS/LAZ file
sample_las_path <- "D:/Lidar_Project/Reference/reference.laz"

# Option 2: Specify the authoritative EPSG code directly
# epsg_code <- 2255

# Number of parallel workers
n_cores <- 4

# ---- 1 Install and load libraries ----
list_of_packages <- c("lidR", "sf", "foreach", "doParallel")
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

# ---- 2 Define the CRS-overwrite function ----
fix_catalog_crs_parallel <- function(folder, crs, out_folder, n_cores = 4) {
  if (normalizePath(folder, mustWork = TRUE) ==
      normalizePath(out_folder, mustWork = FALSE)) {
    stop(
      "The output directory must be different from the input directory.",
      call. = FALSE
    )
  }

  if (is.na(crs)) {
    stop("The target CRS is missing or invalid.", call. = FALSE)
  }

  if (!dir.exists(out_folder)) {
    dir.create(out_folder, recursive = TRUE)
  }

  files <- list.files(folder, pattern = "\\.la[sz]$", full.names = TRUE)

  if (length(files) == 0L) {
    stop("No LAS or LAZ files were found in the input directory.", call. = FALSE)
  }

  cl <- makeCluster(n_cores)
  on.exit(stopCluster(cl), add = TRUE)
  registerDoParallel(cl)

  results <- foreach(f = files, .packages = c("lidR", "sf")) %dopar% {
    las <- tryCatch(readLAS(f), error = function(e) NULL)
    if (is.null(las)) {
      return(paste("Could not read file:", basename(f)))
    }

    # WARNING: Replace CRS metadata only; point coordinates are not transformed.
    st_crs(las) <- crs
    out_file <- file.path(out_folder, basename(f))
    writeLAS(las, out_file, index = TRUE)
    paste("Overwrote CRS metadata and wrote file:", basename(f))
  }

  # Print all results
  cat(paste(results, collapse = "\n"))
}

# ---- 3 Select the target CRS ----

# Option 1: Copy the CRS from the reference LAS/LAZ file
sample_las_header <- readLASheader(sample_las_path)
target_crs <- st_crs(sample_las_header)

# Option 2: Comment out Option 1 above and uncomment this line to use an EPSG
# code defined in the User inputs section.
# target_crs <- st_crs(epsg_code)

if (is.na(target_crs)) {
  stop("The selected target CRS is missing or invalid.", call. = FALSE)
}

# ---- 4 Overwrite the CRS metadata and write corrected copies ----
fix_catalog_crs_parallel(folder, target_crs, out_folder, n_cores = n_cores)



