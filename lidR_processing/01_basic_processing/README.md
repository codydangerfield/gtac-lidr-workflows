# Basic Lidar Processing

This folder contains a general-purpose R workflow for completing the basic processing steps commonly needed for a airborne lidar acquisition. The script will process and normalize LAS/LAZ point clouds to generate LAX files, DEMs, and CHMs as well as prepare the point cloud for later analysis such as area-based modeling, forest-metric generation, individual-tree detection, and etc.

## Script

- [lidR LAX, DEM, normalization, and CHM workflow](lidR_LAX_DEM_Normalize_CHM.R)

## Processing workflow

The script is organized into four processing chunks:

1. **Create LAX indexes** — creates a `.lax` spatial index beside each LAS/LAZ file to improve catalog queries and processing performance.
2. **Create Digital Elevation Models (DEMs)** — interpolates ground-classified points with a TIN to generate DEM rasters.
3. **Normalize point-cloud heights** — normalizes the Z value of each point so its value represents height above ground rather than elevation.
4. **Create Canopy Height Models (CHMs)** — rasterizes the normalized point cloud into a canopy height model (CHM).

The full workflow does not have to be run in this exact order. LAX indexing and DEM creation are independent steps and may be skipped when those products already exist or are not needed. However, point-cloud normalization must be completed before creating a CHM with this script and it is highly recommended to have LAX files generated if they have not been already. 

## Input requirements

- An acquisition folder containing LAS or LAZ files.
- Ground-classified points, normally ASPRS class 2, for DEM creation and height normalization.
- Sufficient disk space for indexes, DEMs, normalized point clouds, and CHMs.

Before processing, review the vendor's report, point cloud classifications, CRS, and expected vegetation height range. The script removes noise classes 7 and 18, withheld points, and points below zero during the relevant processing stages. You may also want to remove additional classes based on the vendor's report.

## R packages

The workflow uses the following packages:

- `lidR`
- `future`
- `sf`
- `raster`
- `terra`
- `mapview`

Missing packages are installed automatically from CRAN or the R-lidar R-universe repository.

## User configuration

Edit the **USER CONFIGURATION** section before running a new acquisition:

| Parameter | Purpose |
| --- | --- |
| `n_workers` | Number of parallel R workers. Choose a value appropriate for available CPU cores and memory. |
| `buffer_size` | Catalog chunk buffer in the CRS units. Buffers reduce edge effects between tiles. |
| `dem_resolution` | DEM cell size in the CRS units. |
| `chm_resolution` | CHM cell size in the CRS units. |
| `max_height` | Maximum accepted normalized canopy height, in the CRS units. |
| `folder` | Folder containing the acquisition's source LAS/LAZ files. |

The script detects whether the CRS uses meters or feet and adds the detected unit and raster resolution to DEM and CHM filenames.

## Outputs

Outputs are written beneath the configured acquisition folder:

```text
Acquisition folder/
├── source_file.las or source_file.laz
├── source_file.lax
├── DEM/
│   └── source_file_DEM_<resolution>.tif
└── Normalized/
    ├── source_file_Normalized.las
    ├── source_file_Normalized.lax
    └── CHM/
        └── source_file_CHM_<resolution>.tif
```

### Optional LAZ compression for normalized files

Normalized point clouds are written as LAS files by default. To write compressed LAZ files instead, add the following catalog option in the **Normalize Point Cloud** section before calling `normalize_height()`:

```r
opt_laz_compression(ctg) <- TRUE
```

LAZ compression can make catalog processing substantially slower. Use LAZ output primarily when storage space is constrained; otherwise, LAS is preferable for processing speed. See the [`lidR` guidance on LAScatalog computation speed](https://cran.r-project.org/web/packages/lidR/vignettes/lidR-computation-speed-LAScatalog.html) for additional details.


## Recommended use

1. Copy or adapt the script for the specified lidar acquisition.
2. Set `folder` and review all user-configuration values.
3. View the catalog summary and plots to verify tile coverage, chunk layout, file count, and CRS.
4. Run one processing section at a time. LAX indexing and DEM creation may be run independently or skipped when they are not needed. Always run normalization before CHM generation.
5. Inspect each output before continuing to the next section. You may see noise that needs to be classified and removed prior to ABA modeling or lidar metric generation.
6. Reset parallel processing with the final cleanup section when processing is complete.

Do **not** run the entire script at once with **Ctrl+A** followed by **Ctrl+Enter**. Processing one section at a time makes it easier to inspect results, manage memory, and restart failed catalog chunks.

## Restarting interrupted processing

The script includes commented examples for restarting at a failed chunk with `opt_restart()` or marking selected catalog entries as already processed. Place and adjust these options immediately before the catalog operation being resumed. Verify the catalog order and output files before skipping any chunks.

## Quality-control checks

For each acquisition, review:

- catalog CRS and units;
- tile alignment, gaps, and overlaps;
- ground-classification coverage and quality;
- DEM artifacts and interpolation across data gaps;
- normalized ground elevations, which should generally be near zero;
- CHM seams, missing cells, and unrealistic canopy heights; and
- output completeness for every source tile.

Parameter values are acquisition-specific. Point density, terrain complexity, vegetation structure, coordinate units, computer resources, and downstream analysis requirements should guide the selected buffer size, raster resolutions, interpolation settings, and height thresholds.
