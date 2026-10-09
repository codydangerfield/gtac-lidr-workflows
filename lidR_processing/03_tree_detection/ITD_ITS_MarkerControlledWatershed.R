###############################################################################
# Script Name: Lidar Individual Tree Detection and Segmentation
# Description:
#   Detects individual treetops and delineates tree crowns from normalized
#   LAS/LAZ point clouds using a marker-controlled watershed workflow. The
#   script creates a canopy height model (CHM), detects treetops with a
#   variable-window local maximum filter, segments crowns with ForestTools,
#   assigns crown IDs to lidar points, and writes spatial outputs by catalog
#   chunk.
#
# Processing steps:
#   1. Create and smooth a 0.5-unit CHM for each buffered catalog chunk
#   2. Detect treetops with lidR::locate_trees() and a variable window
#   3. Delineate crown polygons with ForestTools::mcws()
#   4. Export crowns, treetops, cropped CHMs, and optionally segmented LAS files
#   5. Merge crown polygons into an acquisition-wide output
#   6. Optionally rerun standalone CHM and treetop workflows
#
# Inputs:
#   - Height-normalized LAS/LAZ tiles in a consistent projected CRS
#   - Point classifications and height units appropriate for configured filters
#
# Outputs:
#   - Crown polygons in GeoPackage files
#   - Optional segmented LAS files containing a treeID attribute
#   - Treetop points in GeoPackage files
#   - Smoothed CHM tiles in GeoTIFF files
#   - Merged crown delineations
#
# Requirements:
#   - R packages: terra, sf, future, ForestTools, dplyr, lidR, future.apply,
#     and progressr
#
# Notes:
#   - Review the worker count, paths, buffer sizes, height filters, CHM
#     resolution, local-maximum window, and minimum crown height before use.
#   - Run the script one section at a time and inspect intermediate products.
#   - Restart and processed-chunk settings are acquisition-specific and should
#     not be reused without checking the current LAScatalog order.
#
# Author: Cody Dangerfield
# Developed for: USFS Lidar Forest Structure Projects
# Last Updated: October 9, 2026
###############################################################################

# ---- 0 User inputs ----
folder <- "E:/LAS/Normalized"
output_folder <- file.path(folder, "ITD_ITS")
cores <- 12
export_las <- TRUE

# ---- 1 Install and load libraries ----
list_of_packages <- c(
  "terra", "sf", "future", "ForestTools", "dplyr", "lidR",
  "future.apply", "progressr"
)

new_packages <- list_of_packages[
  !(list_of_packages %in% installed.packages()[, "Package"])
]

if (length(new_packages) > 0) {
  install.packages(
    new_packages,
    dependencies = TRUE,
    repos = "https://cloud.r-project.org"
  )
}

loaded_packages <- vapply(
  list_of_packages,
  require,
  logical(1),
  character.only = TRUE
)

if (!all(loaded_packages)) {
  stop(
    "Unable to load required packages: ",
    paste(names(loaded_packages)[!loaded_packages], collapse = ", "),
    call. = FALSE
  )
}

# ---- 2 Parallel setup ----
plan(multisession, workers = cores, gc = TRUE)

# ---- 3 Marker-Controlled Watershed Segmentation Functions ----

mcws_segmentation <- function(chunk){
  las <- readLAS(chunk)
  if (is.empty(las)) return(NULL)

  # I would already import this raster, but currently you can not use SpatRasters with future without throwing an error
  chm <- rasterize_canopy(las, res = 0.5, algorithm = p2r(subcircle=0.25, na.fill = knnidw(k=10, p=2, rmax = 1.5)))
  w <- matrix(1, 3, 3)
  chm <- terra::focal(chm, w, fun = median, na.rm = TRUE) #to fill holes

  f <- function(x) {x * 0.01+ 3}
  ttops_chunk_sf <- locate_trees(chm, lmf(f))

  # exit if no trees
  if (nrow(ttops_chunk_sf) == 0L){
    warning("No trees", call. = FALSE)
    return(NULL)
  }

  # Segment crowns as polygons
  crowns <- ForestTools::mcws(
    ttops_chunk_sf,
    chm,
    minHeight = 2,
    format = "polygon",
    IDfield = "treeID"
  )
  # Subset to chunk extent to ensure no edge effects
  bbox <- sf::st_as_sfc(sf::st_bbox(chunk))
  ttops_subset <- sf::st_filter(
    ttops_chunk_sf,
    bbox,
    .predicate = sf::st_intersects
  )

  if (nrow(ttops_subset) == 0L){
    warning("No trees", call. = FALSE)
    return(NULL)
  }

  crowns_subset <- crowns %>%
    dplyr::filter(treeID %in% ttops_subset$treeID)

  segmented_las <- NULL
  if (export_las) {
    segmented_las <- merge_spatial(
      las,
      crowns_subset,
      attribute = "treeID"
    )
    segmented_las <- add_lasattribute(
      segmented_las,
      name = "treeID",
      desc = "mcws TreeID"
    )

    # LAS files are written out based on tree id rather than  by tile extent.
    # Keep all points assigned to crowns whose treetops occur in the unbuffered
    # chunk, including crown points that extend into the chunk buffer. Because
    # each treetop belongs to only one core chunk, a tree is exported only once.
    segmented_las <- filter_poi(segmented_las, !is.na(treeID))
    st_crs(segmented_las) <- st_crs(ctg)
  }

  gc()


  # Crop raster output to the unbuffered chunk extent. Crown polygons are
  # retained in full when their treetop falls inside the core chunk.
  chm_subset <- terra::crop(chm, terra::ext(sf::st_bbox(chunk)))
  
  ## Might add a section where tree metrics are generated for each tree in future iterations.
  ## Might add crown geometry metrics in future iterations. 
  # CrownMetrics <- crown_metrics(las, .stdmetrics, geom = "concave", concavity = 2)
  # CrownMetrics <- CrownMetrics %>%st_drop_geometry()
  #
  # crowns_subset<-crowns_subset %>%
  #   left_join(CrownMetrics, by="treeID")

  return(list(
    crowns = crowns_subset,
    points = segmented_las,
    treetops = ttops_subset,
    chm = chm_subset
  ))


}

export_itd_its_products <- function(output_list, file, export_las = TRUE) {
  crowns_path <- paste0(file, "_crowns.gpkg")
  points_path <- paste0(file, "_points.las")
  treetops_path <- paste0(file, "_treetops.gpkg")
  chm_path <- paste0(file, "_chm.tif")

  sf::st_write(
    output_list$crowns,
    crowns_path,
    append = FALSE,
    quiet = TRUE
  )
  if (export_las) {
    lidR::writeLAS(output_list$points, points_path)
  }
  sf::st_write(
    output_list$treetops,
    treetops_path,
    append = FALSE,
    quiet = TRUE
  )
  terra::writeRaster(output_list$chm, chm_path, overwrite = TRUE)
}

export_itd_its_products_driver <- list(
  write = export_itd_its_products,
  extension = "",
  object = "output_list",
  path = "file",
  param = list(export_las = export_las))


# ---- 4 LAS catalog loading and parameterization ----
ctg <- readLAScatalog(folder=folder)
plot(ctg, chunk_pattern = TRUE)
plot(ctg, map = TRUE)
opt_chunk_buffer(ctg)<- 30
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_z_above 115 -drop_withheld"
opt_output_files(ctg) <- file.path(
  output_folder,
  "mcws_crowns",
  "{*}_mcws"
)

opt_progress(ctg)<-T

ctg@output_options$drivers$list <- export_itd_its_products_driver
ctg@output_options$drivers$sf$extension <- ".gpkg"
ctg@output_options$drivers$sf$param$append<- FALSE
ctg@output_options$drivers$Raster$param$overwrite <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

opt <- list(need_buffer = TRUE, automerge = FALSE)
plot(ctg, chunk_pattern = TRUE)

## lidR restart options if you need them
## Option 1: Overall restart of the catalog engine
# opt_restart(ctg) <- 350
## Option 2: Specific chunks to reprocess
# ctg$processed <- FALSE
# ctg$processed[c(108:111,134:137,161:164,189:192)] <- TRUE 

output <- catalog_apply(ctg, mcws_segmentation, .options = opt)

# ---- 5 Merge spatial output files in parallel ----
read_sf_files_parallel <- function(file_list, workers = cores) {
  if (length(file_list) == 0L) {
    stop("No GeoPackage files were found to merge.", call. = FALSE)
  }

  previous_plan <- future::plan()
  on.exit(future::plan(previous_plan), add = TRUE)
  plan(multisession, workers = workers)
  progressr::handlers("txtprogressbar")

  list_of_sf_objects <- progressr::with_progress({
    p <- progressr::progressor(steps = length(file_list))
    future.apply::future_lapply(file_list, function(file) {
      sf_object <- sf::st_read(file, quiet = TRUE)
      p()
      sf_object
    }, future.seed = TRUE)
  })

  sf::st_as_sf(dplyr::bind_rows(list_of_sf_objects))
}

# ---- 5a Merge crown outputs ----
crown_files <- list.files(
  file.path(output_folder, "mcws_crowns"),
  pattern = "_crowns\\.gpkg$",
  full.names = TRUE
)
mcws_crowns <- read_sf_files_parallel(crown_files)

sf::st_write(
  mcws_crowns,
  file.path(output_folder, "mcws_crowns", "mcwatershed_crown_delineation.gdb"),
  append = FALSE
)

# ---- 5b Merge treetop outputs ----
treetop_files <- list.files(
  file.path(output_folder, "mcws_crowns"),
  pattern = "_treetops\\.gpkg$",
  full.names = TRUE
)
mcws_treetops <- read_sf_files_parallel(treetop_files)

sf::st_write(
  mcws_treetops,
  file.path(output_folder, "mcws_crowns", "mcwatershed_treetops.gdb"),
  append = FALSE
)
