# ---- LASindex/LAStools Indexing Pipeline ----
# Description:
# This script creates spatial index (.lax) files for LiDAR point clouds. 
# LAStools is required to be installed on your machine. 
#
# Performance Note:
# - You can generate .lax files directly in R using lidR functions.
# - However, doing this using lasindex via system() (as shown below) is 
#   significantly faster for large batch processing.

# Author: Cody Dangerfield
# Last Updated: November 3, 2026

# Load required packages
library(parallel)

# Determine available cores for parallel processing (using 25% of capacity)
cores <- detectCores() / 4)

# Directory containing the point cloud files
folder <- "D:/LAS"

# Run LAStools lasindex to create .lax files across all LAZ files in the folder
system(paste0('C:/LASTools/LASTools_2021.01.28/bin/lasindex -i ', folder, '/*.laz -cores ', cores))


