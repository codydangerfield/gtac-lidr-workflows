# Lidar Individual Tree Detection and Segmentation

This folder contains an R-based workflow for detecting individual treetops and delineating tree crowns using marker-controlled watershed segmentation. It processes height-normalized LAS or LAZ files with the `lidR` catalog engine and uses `ForestTools` to delineate individual tree crowns. The workflow produces treetop points, crown polygons, canopy height models (CHMs), and, optionally, LAS files in which points are assigned a tree ID.

## Script

- [Marker-controlled watershed tree detection and segmentation](ITD_ITS_MarkerControlledWatershed.R)

## Processing workflow

For each LAScatalog chunk, the script:

1. reads the height-normalized point cloud;
2. creates a 0.5 m canopy height model (CHM);
3. fills local CHM gaps with a 3 × 3 median focal filter;
4. detects treetops with a variable-window local maximum filter;
5. delineates crown polygons with `ForestTools::mcws()`;
6. assigns each tree to the unbuffered chunk containing its treetop;
7. optionally assigns crown `treeID` values to lidar points;
8. writes chunk-level crowns, treetops, CHMs, and optional segmented LAS files; and
9. reads and combines the chunk-level crown and treetop GeoPackages into acquisition-wide outputs.

The workflow uses a custom `LAScatalog` output driver because one catalog operation returns several object types: crown polygons, treetop points, a CHM raster, and optionally a segmented point cloud.

## Input requirements

- Height-normalized LAS or LAZ files.
- Enough memory and storage for simultaneous chunk processing and output products.

## R packages

The script directly uses:

- `lidR`
- `ForestTools`
- `terra`
- `sf`
- `dplyr`
- `future`
- `future.apply`
- `progressr`

Missing packages are installed automatically from CRAN with their dependencies.

## User configuration

Review the **User inputs** section near the beginning of the script before processing a new acquisition:

The current buffer, CHM, and height-filter defaults are in meters. If the catalog uses feet, convert all distance and height parameters to feet before running the workflow. The variable-window local maximum filter should also be tuned to the forest type and point-cloud characteristics. Test it on a small subset before processing the full acquisition. The current function uses a 1% height coefficient and a minimum window size of 3 m: `0.01 × height + 3`. Coefficients from 1% to 7% may be useful starting points for testing, but they should be visually inspected against the CHM.

| Parameter | Purpose |
| --- | --- |
| `folder` | Directory containing the normalized LAS or LAZ files. |
| `output_folder` | Parent directory for all workflow outputs. By default, an `ITD_ITS` folder is created beneath `folder`. |
| `cores` | Number of parallel multisession workers. Reduce this when available memory is limited. |
| `export_las` | Set to `TRUE` to produce segmented LAS files or `FALSE` to skip point-to-crown assignment and LAS export. |

Also review these processing settings:

| Setting | Current value | Purpose |
| --- | --- | --- |
| CHM resolution | `0.5` | Cell size used by `rasterize_canopy()`. |
| Point-to-raster subcircle | `0.25` | Radius used by `p2r()` to reduce empty cells. |
| Empty-cell interpolation | `knnidw(k = 10, p = 2, rmax = 1.5)` | Fills CHM cells lacking returns. |
| Focal window | `3 × 3` | Median filter used to smooth the CHM and fill small holes. |
| Tree-detection window | `0.01 × height + 3` | Variable local-maximum window supplied to `lmf()`. |
| Minimum crown height | `2` | Minimum CHM height used by `ForestTools::mcws()`. |
| Catalog buffer | `30` | Spatial context loaded around each catalog chunk. |
| Maximum retained height | `115` | Points above this normalized height are dropped. |

The catalog filter also removes classifications 7 and 18, points below zero, and withheld points.

## Tree ownership and buffered points

Buffers are required to reduce edge effects in CHM creation, treetop detection, and crown segmentation. The output is intentionally organized by **treetop ownership**, not strictly clipped to source-tile boundaries:

- Tree tops are exported based on the original LAS extent. This ensures that no duplicate trees are exported based on the loaded buffer.
- Crown polygons are then filtered according to those tree tops in the original LAS extent. However, a retained crown may extend beyond the original LAS tile or chunk boundary to ensure the full crown is captured.
- The script retains all points assigned to the exported tree crowns which would include crown points located within the processing buffer. Consequently, neighboring LAS files will technically can have overlapping spatial extents.However, because we are filtering based on the unique trees within each LAS file, there won't be any true overlap or `duplicated points`.
- Segmented LAS files can be used for visualization or to calculate [tree-level lidar metrics](https://r-lidar.github.io/lidRbook/tree_metrics.html). A future iteration of this workflow might have an option to calculate these metrics during processing with `crown_metrics()`.
- CHMs are cropped to the unbuffered las extent. These tiles can be assembled into a virtual raster (VRT) for wall-to-wall viewing.

Consequently, a segmented LAS output may extend outside the nominal boundary represented by its filename. This is expected and prevents trees crossing tile boundaries from being spatially truncated.

## Optional segmented LAS export

Set:

```r
export_las <- TRUE
```

to export the LAS files containing only points assigned to detected crowns. The script registers `treeID` as a LAS Extra Bytes attribute so it is preserved by `writeLAS()`.

Set:

```r
export_las <- FALSE
```

to skip `merge_spatial()`, Extra Bytes registration, point filtering, and LAS writing. Crown, treetop, and CHM products are still generated.

## Output organization

Outputs follow this general structure:

```text
<folder>/
└── ITD_ITS/
    └── mcws_crowns/
        ├── <source>_mcws_crowns.gpkg
        ├── <source>_mcws_treetops.gpkg
        ├── <source>_mcws_chm.tif
        ├── <source>_mcws_points.las        # only when export_las is TRUE
        ├── mcwatershed_crown_delineation.gdb/
        └── mcwatershed_treetops.gdb/
```

Chunk-level products use the original catalog filename through the `{*}` output template.

## Spatial-output merging

After catalog processing, the script performs two separate parallel merges:

1. files ending in `_crowns.gpkg` are combined into `mcws_crowns` and written to `mcwatershed_crown_delineation.gdb`; and
2. files ending in `_treetops.gpkg` are combined into `mcws_treetops` and written to `mcwatershed_treetops.gdb`.


## Recommended use

1. Confirm that all input files are height normalized and use the same projected CRS.
2. Set `folder`, `output_folder`, `cores`, and `export_las`.
3. Review the CHM resolution, buffer, point filters, tree-detection window, and minimum crown height.
4. Inspect the LAScatalog maps and chunk pattern.
5. Test the workflow on one or a small number of chunks.
6. Examine treetop locations, crown geometry, CHM seams, and tree assignments.
7. Run the complete catalog only after validating the selected parameters.
8. Merge crown and treetop outputs after all required chunks finish successfully.

## Quality-control considerations

Review the following before using the products for inventory or modeling:

- height normalization and ground values near zero;
- CRS and horizontal/vertical measurement units;
- whether the variable-window function is appropriate for the forest type: `f <- function(x) {x * 0.01 + 3}`;
- output completeness following interrupted or restarted processing; and
- available memory when increasing the number of workers.

A processing buffer must be wider than the expected crown radius. Trees extending beyond the buffer cannot be exported completely because those points were never loaded into the chunk.

## Tree ID considerations

`locate_trees()` currently uses its default tree-ID behavior. Because LAScatalog chunks are processed independently, locally assigned IDs may repeat among chunks. Native `lidR` workflows can generate globally unique IDs by setting the `uniqueness` argument in `locate_trees()` to `"bitmerge"`. However, `ForestTools::mcws()` converts its `IDfield` to a standard integer before segmentation, so it doesn't preserve the global IDs.

If `crown_metrics()` is added in a future iteration, the metrics can be calculated within each chunk and joined to its crown polygons before export. Repeated `treeID` values would not affect those crown attributes because the metrics would already be attached to the correct spatial features. The IDs should not, however, be treated as globally unique keys for joins across merged crown, treetop, or LAS outputs.

## Limitations

- Marker-controlled watershed results depend strongly on CHM quality and treetop detection.
- A single treetop is assumed to identify the chunk that owns the complete tree.
- Points outside the catalog buffer are unavailable even when their crown belongs to the chunk.
- Trees without a detected treetop or accepted crown are omitted from segmented LAS outputs.
- The workflow does not calculate tree-level or crown-geometry metrics by default.
- Acquisition-wide LAS files are not merged; segmented LAS outputs remain partitioned by treetop-owning chunk.
