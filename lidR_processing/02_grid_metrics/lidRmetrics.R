###############################################################################
# Script Name: LiDAR Grid Metrics
# Description:
#   Calculates grid-based LiDAR metrics from normalized LAS/LAZ data using lidR,
#   lidRmetrics, and terra. Metrics are computed at user-defined resolution,
#   written as tiles to an output directory, then mosaicked into final rasters.
#
# Default file organization 
#
# └── Normalized/
#   └── FirstOrder_Metrics_20m/
#       ├── elev/
#       │   ├── tiles/
#       │   ├── Lkurt_plus2_20METERS.tif
#       │   └── Lkurt_plus2_first_20METERS.tif
#       ├── intensity/
#       │   ├── tiles/
#       │   ├── imean_20METERS.tif
#       │   └── imean_first_20METERS.tif
#       └── strata/
#           ├── tiles/
#           ├── strata_2to4M_kurtosis_20METERS.tif
#           └── strata_2to4M_kurtosis_first_20METERS.tif
#  
# Requirements:
#   - Normalized LAS/LAZ tiles
#   - R packages: lidR, lidRmetrics, terra, future, mapview, leaflet, moments,
#     lmom, Lmoments, geometry
#   - lidRmetrics auto-installs from GitHub if missing
#
# Author: Cody Dangerfield
# Developed for: USFS LiDAR Forest Structure Projects
###############################################################################

## ---- Install & Load Packages ----
required_pkgs <- c(
  "lidR", "future", "terra", "leaflet", "mapview", "moments", "lmom",
  "Lmoments", "geometry"
)

new_pkgs <- required_pkgs[!(required_pkgs %in% installed.packages()[,"Package"])]
if (length(new_pkgs) > 0) {
  install.packages(new_pkgs, repos = "https://cloud.r-project.org")
}

# Install lidRmetrics if missing
if (!requireNamespace("lidRmetrics", quietly = TRUE)) {
  message("lidRmetrics not found. Installing from GitHub...")
  if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools", repos = "https://cloud.r-project.org")
  }
  devtools::install_github("ptompalski/lidRmetrics", upgrade = "never")
}

library(lidR)
library(lidRmetrics)
library(future)
library(terra)
library(mapview)
library(leaflet)
library(moments)
library(lmom)

plan(multisession, workers = 3)

## ---- USER INPUT ----
resolution <- 20 # Resolution of your grid metrics
input_dir  <- "D:/temp/Normalized" # Pathway to your las/laz files 
output_dir <- "D:/temp/Normalized" # Output of grid metrics and tiles *I would leave the same as input unless you need it in a different parent directory 


zmin <- 2 #minimum height at which elev metrics will be calculated *THIS DOES NOT INCLUDE % ABOVE 2 M OR % ABOVE THE MEAN

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---- lidR Restart Methods (examples) ----
## If your catalog processing crashes, you can restart from a specific chunk
## or re-run only unprocessed chunks. Place these lines where appropriate:
##   - above pixel_metrics()

## Option 1: For overall restarts
# opt_restart(ctg) <- 50 # number of the chunk that failed

## Option 2: To run specific LAS files/chunks
# ctg$processed <- FALSE
# ctg$processed[c(50:58, 64:550)] <- TRUE # Specify chunks to reprocess

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

    m_lad_filtered     <- lidRmetrics::metrics_lad(z=z, zmin=zmin)
    names(m_lad_filtered) <- paste0(names(m_lad_filtered), zmin_label)

    # m_int_filtered    <- metrics_interval(z=z, zmin=zmin, zintervals = zintervals)
    # names(m_int_filtered) <- paste0(names(m_int_filtered), zmin_label)
  }

  # ----------------------------
  # 2. COMBINE ALL METRICS
  # ----------------------------

  if (is.na(zmin)) {
    m <- c(m_basic, m_prctls, m_percab, m_disp, m_candens, m_lmom, m_lad,  m_rumple)

  } else {
    m <- c(m_basic_filtered, m_prctls_filtered, m_percab, m_disp_filtered, m_candens_filtered, m_lmom_filtered, m_lad_filtered,  m_rumple)
  }

  return(m)
}


## ---- HEIGHT METRICS ----
ctg <- readLAScatalog(folder = input_dir)
plot(ctg, map = T)
plot(ctg, chunk_pattern = TRUE)

opt_chunk_buffer(ctg)<-30
opt_filter(ctg) <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld -drop_z_above 115"
opt_progress(ctg)<-T
opt_output_files(ctg) <- paste0(output_dir, "/FirstOrder_Metrics","_", resolution, "m/elev/tiles/", "{*}_elev","_", resolution, "m")
summary(ctg)

ctg@output_options$drivers$Raster$param$overwrite <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

elev_grid_metrics<-pixel_metrics(ctg, ~elev_metrics(X, Y,
      Z, zmin = zmin),
  res = resolution,
  by_echo = c("first", "all"))

# Create a VRT mosaic from all individual elevation tiles
elev_tiles_dir <- paste0(
  output_dir, "/FirstOrder_Metrics_", resolution, "m/elev/tiles"
)

file_list <- list.files(
  elev_tiles_dir,
  pattern = "\\.tif$",
  full.names = TRUE,
  recursive = FALSE
)

if (length(file_list) == 0) {
  stop("No elevation metric TIFF tiles found in: ", elev_tiles_dir)
}

vrt_path <- file.path(elev_tiles_dir, "pixel_metrics.vrt")
terra::vrt(file_list, filename = vrt_path, overwrite = TRUE)

metrics <- terra::rast(vrt_path)
names(metrics) <- names(terra::rast(file_list[1]))

writeRaster(
  metrics,
  filename = paste0(
    output_dir, "/FirstOrder_Metrics_", resolution, "m/",
    gsub("\\.", "_", names(metrics)), "_", resolution, "METERS.tif"
  ),
  overwrite = TRUE
)

## ---- Intensity Metrics ----
ctg <- readLAScatalog(folder = input_dir)
plot(ctg, chunk_pattern = TRUE)
plot(ctg, map = TRUE)

opt_chunk_buffer(ctg)  <- 30
opt_filter(ctg)        <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld -drop_z_above 115"
opt_progress(ctg)      <- TRUE
opt_output_files(ctg)  <- paste0(
  output_dir, "/FirstOrder_Metrics_", resolution, "m/intensity/tiles/",
  "{*}_intensity_", resolution, "m"
)

ctg@output_options$drivers$Raster$param$overwrite     <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

intensity_metrics <- pixel_metrics(
  ctg,
  ~stdmetrics_i(Intensity, Z, Classification, ReturnNumber),
  res = resolution,
  by_echo = c("first", "all")
)

# Mosaic intensity tiles
file_list <- list.files(
  paste0(output_dir, "/FirstOrder_Metrics_", resolution, "m/intensity/tiles"),
  pattern = "tif$",
  full.names = TRUE,
  recursive = FALSE
)

metrics <- terra::sprc(file_list)
metrics <- mosaic(metrics)

writeRaster(
  metrics,
  filename = paste0(
    output_dir, "/FirstOrder_Metrics_", resolution, "m/",
    gsub("\\.", "_", names(metrics)), "_", resolution, "METERS.tif"
  ),
  overwrite = TRUE
)

## ---- STRATA METRICS ----
StrataMetrics <- function(z, r) {
  gt0 <- which(z > 0)
  s0  <- which(z > 0   & z < 0.5)
  s1  <- which(z > 0.5 & z < 1)
  s2  <- which(z > 1   & z < 2)
  s3  <- which(z > 2   & z < 4)
  s4  <- which(z > 4   & z < 8)
  s5  <- which(z > 8   & z < 16)
  s6  <- which(z > 16  & z < 32)
  s7  <- which(z > 32  & z < 48)
  s8  <- which(z > 48  & z < 64)
  s9  <- which(z > 64)

  gt0first = which(z > 0 & r == 1)
  s0first = which(z > 0 & z < 0.5 & r == 1)
  s1first = which(z > 0.5 & z < 1 & r == 1)
  s2first = which(z > 1 & z < 2 & r == 1)
  s3first = which(z > 2 & z < 4 & r == 1)
  s4first = which(z > 4 & z < 8 & r == 1)
  s5first = which(z > 8 & z < 16 & r == 1)
  s6first = which(z > 16 & z < 32 & r == 1)
  s7first = which(z > 32 & z < 48 & r == 1)
  s8first = which(z > 48 & z < 64 & r == 1)
  s9first = which(z > 64 & r == 1)

  metrics = list(
    strata_0p5to1M_CV = sd(z[s1])/mean(z[s1]),
    strata_0p5to1M_kurtosis = moments::kurtosis(z[s1]),
    strata_0p5to1M_return_proportion = length(z[s1]) / length(z[gt0]),
    strata_0p5to1M_skewness = moments::skewness(z[s1]),
    strata_0p5to1M_stddev = sd(z[s1]),
    strata_0p5to1M_total_return_cnt = length(z[s1]),
    strata_0to0p5M_CV = sd(z[s0])/mean(z[s0]),
    strata_0to0p5M_kurtosis = moments::kurtosis(z[s0]),
    strata_0to0p5M_return_proportion = length(z[s0]) / length(z[gt0]),
    strata_0to0p5M_skewness = moments::skewness(z[s0]),
    strata_0to0p5M_stddev = sd(z[s0]),
    strata_0to0p5M_total_return_cnt = length(z[s0]),
    strata_16to32M_CV = sd(z[s6])/mean(z[s6]),
    strata_16to32M_kurtosis = moments::kurtosis(z[s6]),
    strata_16to32M_return_proportion = length(z[s6]) / length(z[gt0]),
    strata_16to32M_skewness = moments::skewness(z[s6]),
    strata_16to32M_stddev = sd(z[s6]),
    strata_16to32M_total_return_cnt = length(z[s6]),
    strata_1to2M_CV = sd(z[s2])/mean(z[s2]),
    strata_1to2M_kurtosis = moments::kurtosis(z[s2]),
    strata_1to2M_return_proportion = length(z[s2]) / length(z[gt0]),
    strata_1to2M_skewness = moments::skewness(z[s2]),
    strata_1to2M_stddev = sd(z[s2]),
    strata_1to2M_total_return_cnt = length(z[s2]),
    strata_2to4M_CV = sd(z[s3])/mean(z[s3]),
    strata_2to4M_kurtosis = moments::kurtosis(z[s3]),
    strata_2to4M_return_proportion = length(z[s3]) / length(z[gt0]),
    strata_2to4M_skewness = moments::skewness(z[s3]),
    strata_2to4M_stddev = sd(z[s3]),
    strata_2to4M_total_return_cnt = length(z[s3]),
    strata_32to48M_CV = sd(z[s7])/mean(z[s7]),
    strata_32to48M_kurtosis = moments::kurtosis(z[s7]),
    strata_32to48M_return_proportion = length(z[s7]) / length(z[gt0]),
    strata_32to48M_skewness = moments::skewness(z[s7]),
    strata_32to48M_stddev = sd(z[s7]),
    strata_32to48M_total_return_cnt = length(z[s7]),
    strata_48to64M_CV = sd(z[s8])/mean(z[s8]),
    strata_48to64M_kurtosis = moments::kurtosis(z[s8]),
    strata_48to64M_return_proportion = length(z[s8]) / length(z[gt0]),
    strata_48to64M_skewness = moments::skewness(z[s8]),
    strata_48to64M_stddev = sd(z[s8]),
    strata_48to64M_total_return_cnt = length(z[s8]),
    strata_4to8M_CV = sd(z[s4])/mean(z[s4]),
    strata_4to8M_kurtosis = moments::kurtosis(z[s4]),
    strata_4to8M_return_proportion = length(z[s4]) / length(z[gt0]),
    strata_4to8M_skewness = moments::skewness(z[s4]),
    strata_4to8M_stddev = sd(z[s4]),
    strata_4to8M_total_return_cnt = length(z[s4]),
    strata_64M_plus_CV = sd(z[s9])/mean(z[s9]),
    strata_64M_plus_kurtosis = moments::kurtosis(z[s9]),
    strata_64M_plus_return_proportion = length(z[s9]) / length(z[gt0]),
    strata_64M_plus_skewness = moments::skewness(z[s9]),
    strata_64M_plus_stddev = sd(z[s9]),
    strata_64M_plus_total_return_cnt = length(z[s9]),
    strata_8to16M_CV = sd(z[s5])/mean(z[s5]),
    strata_8to16M_kurtosis = moments::kurtosis(z[s5]),
    strata_8to16M_return_proportion = length(z[s5]) / length(z[gt0]),
    strata_8to16M_skewness = moments::skewness(z[s5]),
    strata_8to16M_stddev = sd(z[s5]),
    strata_8to16M_total_return_cnt = length(z[s5])

  )

  return(metrics)
}

ctg <- readLAScatalog(folder = input_dir)
plot(ctg, chunk_pattern = TRUE)
plot(ctg, map = TRUE)

opt_chunk_buffer(ctg)  <- 30
opt_filter(ctg)        <- "-drop_class 7 18 -drop_z_below 0 -drop_withheld -drop_z_above 115"
opt_progress(ctg)      <- TRUE
opt_output_files(ctg)  <- paste0(output_dir, "/FirstOrder_Metrics_", resolution, "m/strata/tiles/", "{*}_strata_", resolution, "m")

ctg@output_options$drivers$Raster$param$overwrite     <- TRUE
ctg@output_options$drivers$SpatRaster$param$overwrite <- TRUE

strata_metrics <- pixel_metrics(
  ctg,
  ~StrataMetrics(Z, ReturnNumber),
  res = resolution,
  by_echo = c("first", "all")
)

# Mosaic strata tiles
file_list <- list.files(
  paste0(output_dir, "/FirstOrder_Metrics_", resolution, "m/strata/tiles"),
  pattern = "tif$",
  full.names = TRUE,
  recursive = FALSE
)

metrics <- terra::sprc(file_list)
metrics <- mosaic(metrics)

writeRaster(
  metrics,
  filename = paste0(
    output_dir, "/FirstOrder_Metrics_", resolution, "m/",
    gsub("\\.", "_", names(metrics)), "_", resolution, "METERS.tif"
  ),
  overwrite = TRUE
)



