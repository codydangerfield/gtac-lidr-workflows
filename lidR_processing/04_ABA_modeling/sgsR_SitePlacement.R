################################################################################
# Script: sgsR_SitePlacement.R
# Purpose: 
#   - Stack selected lidar metrics into a population metric raster (mraster)
#   - Stratify the full population and calculate proportional stratum weights
#   - Restrict sampling to public land and a surface-corrected access zone
#   - Draw spatially balanced samples and create FIA-like plot clusters
#   - Extract lidar metrics and export the resulting sample points
# Inputs:
#   - Lidar metric rasters (zq90_plus2, rumple_index)
#   - Forest-population mask
#   - Access/road network
#   - Public-land boundary
#   - Surface-corrected access zone
# Outputs:
#   - Population metric and stratification rasters
#   - Sampling-area stratification raster
#   - Stratified sample points in a file geodatabase
# Author: Cody Dangerfield
# Date: 2026-02-25
################################################################################

# ---- 0 Install and load libraries ----
list_of_packages <- c(
  "lidR", "sgsR", "terra", "sf", "ggplot2", "mapview")

new_packages <- list_of_packages[!(list_of_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages, dependencies = TRUE)

lapply(list_of_packages, require, character.only = TRUE)


# ---- 1 Inputs ----

# Root directory containing the project inputs and outputs
root_dir <- "E:/Lidar_Project/SiteSelection"

# Lidar metrics and the forest mask defining the population of interest
zq90_plus2_path <- file.path(root_dir, "Lidar_Metrics/zq90_plus2.tif")
rumple_index_path <- file.path(root_dir, "Lidar_Metrics/rumple_index.tif")
forested_area_path <- file.path(root_dir, "Inputs/Forested_Area.gpkg")
forested_area_layer <- "Forested_Area"

# Sampling constraints
access_gdb_path <- file.path(root_dir, "Inputs/Access.gdb")
access_layer <- "Roads_Trails"

access_zone_path <- file.path(root_dir, "Inputs/Surface_Corrected_Access_Zone.gdb")
access_zone_layer <- "Roads_Trails_0p1miles_AccessZone"

public_land_gdb_path <- file.path(root_dir, "Inputs/Public_Land.gdb")
public_land_layer <- "Public_Land"

st_layers(access_gdb_path)
access <- st_read(access_gdb_path, layer = access_layer) %>%
  st_zm()

access_zone <- st_read(access_zone_path, layer = access_zone_layer) %>%
  st_zm()

public_land <- st_read(
  public_land_gdb_path,
  layer = public_land_layer) |>
  st_zm()

forested_area <- st_read(forested_area_path, layer = forested_area_layer)

# Number of strata for zq90_plus2
nstrata_zq90 <- 4

# Number of strata for rumple_index
nstrata_rumple <- 4 

# Total number of sample points to generate across all strata
n_samp <- 125
mindist <- 300

# ---- 2 Outputs ----  
out_mraster <- file.path(root_dir, "mraster_zq90plus2_rumple.tif")
out_sraster_population <- file.path(root_dir, "sraster_population_16_strata.tif")
out_sraster_sampling <- file.path(root_dir, "sraster_sampling_area_16_strata.tif")
out_gdb <- file.path(root_dir, "Sampling_Points.gdb")
out_gdb_layer <- "Sampling_Points_16_Strata"

# ---- 3 Create the population metric raster (run once) ----

# Comment this section after out_mraster has been generated.
zq90_plus2 <- rast(zq90_plus2_path)
rumple_index <- rast(rumple_index_path)

# Ensure rasters are aligned and have the same extent
zq90_plus2 <- resample(zq90_plus2, rumple_index)

# Restrict both metrics to the forested population before calculating
# thresholds, stacking the metrics, or creating population strata.
forested_area <- st_transform(forested_area, crs = st_crs(rumple_index))
forested_area_vect <- vect(forested_area)
zq90_plus2 <- mask(zq90_plus2, forested_area_vect)
rumple_index <- mask(rumple_index, forested_area_vect)

# Removing outlier values using 99.99th percentile as a threshold
(q99_99 <- global(zq90_plus2, quantile, probs=c(0.9999), na.rm=TRUE))
zq90_plus2[zq90_plus2 > q99_99[,1]]<-q99_99[,1]
(q99_99 <- global(rumple_index, quantile, probs=c(0.9999), na.rm=TRUE))
rumple_index[rumple_index > q99_99[,1]]<-q99_99[,1]

# Create a mask where both rasters have valid values
valid_mask <- !is.na(zq90_plus2) & !is.na(rumple_index)

# Apply the mask to both rasters
zq90_plus2 <- mask(zq90_plus2, valid_mask, maskvalues = FALSE)
rumple_index <- mask(rumple_index, valid_mask, maskvalues = FALSE)

# Stack the two rasters
mraster <- c(zq90_plus2, rumple_index)

names(mraster) <- c("zq90_plus2", "rumple_index")
plot(mraster)
writeRaster(mraster, out_mraster, overwrite = TRUE)

# ---- 3a Read an existing population metric raster ----

# Uncomment this line and comment out Section 3 after out_mraster exists.
# mraster <- rast(out_mraster)

names(mraster) <- c("zq90_plus2", "rumple_index")

# ---- 4 Create the full-population stratification raster (run once) ----

# Comment this section after out_sraster_population has been generated.
sraster_population <- strat_quantiles(
  mraster = mraster[[c(1, 2)]],
  nStrata = list(nstrata_zq90, nstrata_rumple),
  plot = TRUE,
  map = TRUE
) 

writeRaster(sraster_population, out_sraster_population, overwrite = TRUE)

# ---- 4a Read an existing full-population stratification raster ----

# Uncomment this line and comment out Section 4 after the raster exists.
# sraster_population <- rast(out_sraster_population)

# ---- 5 Calculate full-population stratum frequencies ----

# Calculate weights before restricting the stratification raster to public land
# and the accessible sampling area. This preserves the population distribution.
population_freq <- freq(sraster_population[[3]])
weights_vector <- population_freq$count / sum(population_freq$count)

# Previously calculated weights can be retained here for reference or reused
# when the full-population raster has not changed.
# weights_vector <- c(
#   0.194572222120284, 0.0502081708719826, 0.00433305381405942,
#   0.000886644772007747, 0.0351337444945187, 0.11645999989943,
#   0.0863698238802126, 0.0120363900993232, 0.0167193397488562,
#   0.0625946233128399, 0.101988891581477, 0.0686971037303119,
#   0.00357475191346267, 0.0207373973977167, 0.0573079892904634,
#   0.168379853073054
# )

# ---- 6 Restrict the stratification raster to the sampling area ----

# The access zone is assumed to represent surface-corrected travel distance
# from roads and trails and may also account for physical barriers.
access <- st_transform(access, crs = st_crs(mraster))
access_zone <- st_transform(access_zone, crs = st_crs(mraster))
public_land <- st_transform(public_land, crs = st_crs(mraster))

public_land_vect <- vect(public_land)
access_zone_vect <- vect(access_zone)

sraster_sampling <- crop(sraster_population, public_land_vect)
sraster_sampling <- mask(sraster_sampling, public_land_vect)
sraster_sampling <- crop(sraster_sampling, access_zone_vect)
sraster_sampling <- mask(sraster_sampling, access_zone_vect)

plot(sraster_sampling[[3]])
writeRaster(sraster_sampling, out_sraster_sampling, overwrite = TRUE)

# ---- 7 Draw center plots ----

pts_quantiles <- sample_strat(
  sraster = sraster_sampling[[3]],
  nSamp = n_samp,
  allocation = "manual",
  weights = weights_vector,
  access = access,
  mindist = mindist,
  buff_inner = 20,
  buff_outer = 242,
  plot = TRUE
)
mapview(pts_quantiles, zcol = "strata", alpha.regions = 1) + mapview(access) + mapview(access_zone)

# --- Remove plots too close or too far from access layer ---
# Calculate distance from each cluster to the nearest access feature
dist_to_access <- st_distance(pts_quantiles, access)
min_dist_to_access <- apply(dist_to_access, 1, min)

# Keep only those at least 20 m and at most 242 m (0.15 miles) from access
pts_quantiles <- pts_quantiles[min_dist_to_access >= 20 & min_dist_to_access <= 242, ]

# Add plot_id to the initial sample points
pts_quantiles$plot_id <- 1:nrow(pts_quantiles)

# ---- 8 Create FIA-like cluster plots ----
# Generate cluster points for each point in pts_quantiles
all_clusters_list <- lapply(1:nrow(pts_quantiles), function(i) {
  original_point <- pts_quantiles[i, ]
  
  # Create 3 copies of the original point to serve as the base for the new points
  new_points <- original_point[rep(1, 3), ]
  
  # Calculate new coordinates
  distance_m <- 120 * 0.3048
  coords <- st_coordinates(original_point)
  x <- coords[1]
  y <- coords[2]
  
  # Create and assign new geometries
  p_a <- st_point(c(x, y + distance_m))
  p_b <- st_point(c(x + distance_m * sin(pi/3), y - distance_m * cos(pi/3)))
  p_c <- st_point(c(x - distance_m * sin(pi/3), y - distance_m * cos(pi/3)))
  new_points$geometry <- st_sfc(p_a, p_b, p_c, crs = st_crs(original_point))
  
  # Assign new plot IDs with suffixes
  new_points$plot_id <- paste0(original_point$plot_id, c("a", "b", "c"))
  
  # Combine the original point with the new cluster points
  rbind(original_point, new_points)
})

# Combine all clusters into a single sf object
all_clusters <- do.call(rbind, all_clusters_list)

# ---- 9 Thin points to enforce minimum distance ----
# First, get the frequency of each stratum from the original sample points to inform thinning decisions
strata_counts <- as.data.frame(table(pts_quantiles$strata))
names(strata_counts) <- c("strata", "freq")

# Calculate distance matrix
dist_matrix <- st_distance(all_clusters)

# Set threshold in meters to be slightly smaller than 120 ft to account for the fact that clusters are designed to be 120 ft apart. 
threshold_m <- 119 * 0.3048

# Set diagonal to NA so points don't get compared to themselves
diag(dist_matrix) <- NA

# Find pairs of points that are too close
close_pairs <- which(units::drop_units(dist_matrix) < threshold_m, arr.ind = TRUE)
mapview(all_clusters, zcol = "strata", alpha.regions = 1) + mapview(access)

# Extract strata from the full population raster so cluster points use the same
# population stratification that was used to calculate the sampling weights.
strata_values <- terra::extract(sraster_population[[3]], all_clusters)
# Update the strata column in the all_clusters dataframe
# The extracted values are in the second column of the returned data frame
all_clusters$strata <- strata_values[, 2]
mapview(all_clusters, zcol = "strata", alpha.regions = 1) + mapview(access)

# Identify points to remove based on stratum abundance
points_to_remove <- c()
if (nrow(close_pairs) > 0) {
  for (i in 1:nrow(close_pairs)) {
    p1_index <- close_pairs[i, 1]
    p2_index <- close_pairs[i, 2]
    
    # Make sure we haven't already decided to remove one of these points
    if (p1_index %in% points_to_remove || p2_index %in% points_to_remove) {
      next
    }
    
    # Get strata for the pair
    stratum1 <- all_clusters$strata[p1_index]
    stratum2 <- all_clusters$strata[p2_index]
    
    # Get frequency of each stratum
    freq1 <- strata_counts$freq[strata_counts$strata == stratum1]
    freq2 <- strata_counts$freq[strata_counts$strata == stratum2]
    
    # Decide which point to remove
    if (freq1 < freq2) {
      points_to_remove <- c(points_to_remove, p1_index) # Remove point 1
    } else {
      points_to_remove <- c(points_to_remove, p2_index) # Remove point 2 (default if equal)
    }
  }
}

# Get unique indices of points to remove
points_to_remove <- unique(points_to_remove)

# Create the thinned dataset
thinned_clusters <- all_clusters
if (length(points_to_remove) > 0) {
  thinned_clusters <- all_clusters[-points_to_remove, ]
}


# Drop clusters without a valid strata number (NA or not finite)
thinned_clusters <- thinned_clusters[!is.na(thinned_clusters$strata) & is.finite(thinned_clusters$strata), ]

# --- Remove plots too close or too far from access layer ---
# Calculate distance from each cluster to the nearest access feature
dist_to_access <- st_distance(thinned_clusters, access)
min_dist_to_access <- apply(dist_to_access, 1, min)

# Keep only those at least 20 m and at most 242 m (0.15 miles) from access
thinned_clusters <- thinned_clusters[min_dist_to_access >= 20 & min_dist_to_access <= 242, ]

# ---- 10 Extract lidar metrics and review the sample ----
sample_metrics_clusters <- extract_metrics(mraster = mraster, 
                                           existing = thinned_clusters)



ggplot(sample_metrics_clusters, aes(zq90_plus2, rumple_index)) +
  geom_point(aes(color=as.factor(strata)), size=3)+
  geom_text(aes(label = strata), hjust = 0.5, vjust = -1.5, size = 3) +
  # scale_color_manual(values = rev(terrain.colors(11))[-1]) + 
  guides(color=guide_legend(title="Strata"))

mapview(sample_metrics_clusters, zcol = "strata", alpha.regions = 1) + mapview(access)


# ---- 11 Write sample points ----
st_write(
  sample_metrics_clusters, 
  out_gdb, 
  layer = out_gdb_layer, 
  append = FALSE
)