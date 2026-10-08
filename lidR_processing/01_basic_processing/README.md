# Basic LiDAR Acquisition Processing

This folder contains a general-purpose R workflow for completing the basic processing steps commonly needed for a new airborne LiDAR acquisition. The workflow prepares raw LAS/LAZ point clouds for later analysis such as area-based modeling, forest-metric generation, individual-tree detection, and canopy segmentation.

## Script

- [LiDAR LAX, DEM, normalization, and CHM workflow](%E2%81%AFlidR_LAX_DEM_Normalize_CHM.R)

## Processing workflow

The script is organized into sections that should be run in sequence:

1. **Create LAX indexes** — creates a `.lax` spatial index beside each LAS/LAZ file to improve catalog queries and processing performance.
2. **Create Digital Elevation Models (DEMs)** — interpolates ground-classified points with a TIN to generate acquisition-wide terrain rasters.
3. **Normalize point-cloud heights** — subtracts the modeled ground elevation from each point so its Z value represents height above ground.
4. **Create Canopy Height Models (CHMs)** — rasterizes the normalized point cloud into canopy-height surfaces for vegetation analysis.

## Input requirements

- An acquisition folder containing LAS or LAZ files.
- A valid, consistent projected coordinate reference system (CRS) for all files.
- Ground-classified points, normally ASPRS class 2, for DEM creation and height normalization.
- Sufficient disk space for indexes, DEMs, normalized point clouds, and CHMs.

Before processing, review the point-cloud classifications, CRS, horizontal units, vertical units, and expected vegetation-height range. The script removes noise classes 7 and 18, withheld points, and points below zero during the relevant processing stages.

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
| `buffer_size` | Catalog chunk buffer in the CRS horizontal units. Buffers reduce edge effects between tiles. |
| `dem_resolution` | DEM cell size in the CRS horizontal units. |
| `chm_resolution` | CHM cell size in the CRS horizontal units. |
| `max_height` | Maximum accepted normalized canopy height, in the point cloud's vertical units. |
| `folder` | Folder containing the acquisition's source LAS/LAZ files. |

The script detects whether the CRS uses meters or feet and adds the detected unit and raster resolution to DEM and CHM filenames. Confirm that horizontal and vertical units are appropriate before processing; CRS unit detection does not validate the point cloud's vertical units.

## Outputs

Outputs are written beneath the configured acquisition folder:

```text
Acquisition folder/
├── source_file.las or source_file.laz
├── source_file.lax
├── DEM/
│   └── source_file_DEM_<resolution>.<raster extension>
└── Normalized/
    ├── source_file_Normalized.las or .laz
    ├── source_file_Normalized.lax
    └── CHM/
        └── source_file_CHM_<resolution>.<raster extension>
```

Exact raster and point-cloud formats are determined by the `lidR` catalog output drivers and source data.

## Recommended use

1. Copy or adapt the script for the new LiDAR acquisition.
2. Set `folder` and review all user-configuration values.
3. Open the catalog plots and summary to verify tile coverage, chunk layout, file count, and CRS.
4. Run one processing section at a time in the order shown above.
5. Inspect each output before continuing to the next section.
6. Reset parallel processing with the final cleanup section when processing is complete.

Do **not** run the entire script at once with **Ctrl+A** followed by **Ctrl+Enter**. Processing one section at a time makes it easier to inspect results, manage memory, and restart failed catalog chunks.

## Restarting interrupted processing

The script includes commented examples for restarting at a failed chunk with `opt_restart()` or marking selected catalog entries as already processed. Place and adjust these options immediately before the catalog operation being resumed. Verify the catalog order and output files before skipping any chunks.

## Quality-control checks

For each acquisition, review at minimum:

- catalog CRS and units;
- tile alignment, gaps, and overlaps;
- ground-classification coverage and quality;
- DEM artifacts and interpolation across data gaps;
- normalized ground elevations, which should generally be near zero;
- CHM seams, missing cells, and unrealistic canopy heights; and
- output completeness for every source tile.

Parameter values are acquisition-specific. Point density, terrain complexity, vegetation structure, coordinate units, computer resources, and downstream analysis requirements should guide the selected buffer size, raster resolutions, interpolation settings, and height thresholds.
