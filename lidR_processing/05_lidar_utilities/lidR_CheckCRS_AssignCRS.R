###############################################################################
# Script: Check and Assign Missing LAS/LAZ Coordinate Reference Systems
# Description:
#   Checks the coordinate reference system (CRS) stored in each LAS/LAZ header.
#   Files with an existing CRS are skipped. Files with missing CRS metadata are
#   copied to a new directory, assigned the selected CRS, and written with a
#   LAX spatial index.
#
# WARNING:
#   This script assigns CRS metadata only; it does not reproject or transform
#   point coordinates. Assigning an incorrect CRS will cause the data to appear
#   in the wrong location and may invalidate subsequent spatial analysis. Use
#   this script only when the coordinates already use the target CRS but the
#   CRS metadata is missing.
#
#   Confirm the correct CRS from authoritative acquisition metadata or vendor
#   documentation. Preserve the original LAS/LAZ files and inspect the outputs.
#
# Processing steps:
#   1. Find LAS and LAZ files in the configured input directory
#   2. Read each file header in parallel and check its CRS
#   3. Skip files whose headers already contain CRS metadata
#   4. Assign the selected CRS to files with missing CRS metadata
#   5. Write corrected copies and LAX indexes to the output directory
#
# Inputs:
#   - LAS/LAZ files whose coordinates already use the target CRS
#   - Either a reference LAS/LAZ file with the correct CRS or an authoritative
#     target EPSG code
#
# Outputs:
#   - Corrected copies of files that were missing CRS metadata
#   - A LAX spatial index for every successfully written output file
#
# Requirements:
#   - R packages: lidR, sf, foreach, and doParallel
#
# Author: Cody Dangerfield
# Last Updated: November 3, 2026
###############################################################################

# ---- 0 User inputs ----

# Directory containing the LAS/LAZ files to check
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

# ---- 2 Define the missing-CRS repair function ----
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

  results <- foreach(
    file = files,
    .packages = c("lidR", "sf")
  ) %dopar% {
    las_header <- tryCatch(readLASheader(file), error = function(e) NULL)
    if (is.null(las_header)) {
      return(paste("Could not read header:", basename(file)))
    }

    header_crs <- tryCatch(st_crs(las_header), error = function(e) NA)
    if (!is.na(header_crs)) {
      return(paste("Skipped (header CRS exists):", basename(file)))
    }

    las <- tryCatch(readLAS(file), error = function(e) NULL)
    if (is.null(las)) {
      return(paste("Could not read file:", basename(file)))
    }

    # Assign CRS metadata only; point coordinates are not transformed.
    st_crs(las) <- crs
    out_file <- file.path(out_folder, basename(file))
    writeLAS(las, out_file, index = TRUE)
    paste("Assigned missing CRS and wrote file:", basename(file))
  }

  cat(paste(results, collapse = "\n"))
}

# ---- 3 Select the target CRS ----

# Option 1: Copy the CRS from the reference LAS/LAZ file
sample_las_header <- readLASheader(sample_las_path)
target_crs <- st_crs(sample_las_header)

# Option 2: Comment out Option 1 above and uncomment this line to use the EPSG
# code defined in the User inputs section.
# target_crs <- st_crs(epsg_code)

if (is.na(target_crs)) {
  stop("The selected target CRS is missing or invalid.", call. = FALSE)
}

# ---- 4 Assign missing CRS metadata and write corrected copies ----
fix_catalog_crs_parallel(folder, target_crs, out_folder, n_cores = n_cores)



