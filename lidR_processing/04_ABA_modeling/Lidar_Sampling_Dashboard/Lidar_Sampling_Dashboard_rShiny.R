
# --- AUTOLOAD PACKAGES ---
list_of_packages <- c(
  "shiny", "shinydashboard", "ggplot2", "plotly", "dplyr", "sf", 
  "terra", "DT", "shinyFiles", "leaflet", "mapview", "sgsR", "rlang"
)

new_packages <- list_of_packages[!(list_of_packages %in% installed.packages()[,"Package"])]
if (length(new_packages)) install.packages(new_packages, dependencies = TRUE)

# Load all required libraries
invisible(lapply(list_of_packages, library, character.only = TRUE))

# Set mapview basemaps to Esri World Imagery, Esri World Topo Map, USGS USTopo, and OpenStreetMap
mapviewOptions(basemaps = c("Esri.WorldImagery", "Esri.WorldTopoMap", "USGS.USTopo", "OpenStreetMap"))

# --- CONFIGURATION ---
# Use relative paths so the app works on ANY computer it is copied to
ROOT_DIR <- "example_data"
POTENTIAL_GDB <- file.path(ROOT_DIR, "Seward_SamplingPts.gdb")
POTENTIAL_LAYER <- "Seward_SamplingPts"

ACCESS_GDB <- file.path(ROOT_DIR, "KenaiVegMap_Roads_Trails_Dataset.gdb")
ACCESS_LAYER <- "Roads_Trails"

SRASTER_PATH <- file.path(ROOT_DIR, "Seward_sraster_16_strata_zq90plus2_rumple.tif")
MRASTER_PATH <- file.path(ROOT_DIR, "Seward_mraster_zq90plus2_rumple.tif")

DEFAULT_FINAL_PLOT_TOTAL <- 120L
MIN_PER_STRATUM <- 2L
FREQ_THRESHOLD <- 0.01
STRATA_PROPORTIONS <- c(0.205873480945912, 0.0401706064056906, 0.00373669183516466,
0.000296971128326603, 0.0367612843182876, 0.128118489141847,
0.0707562942679896, 0.0142943662004766, 0.00618494987735326,
0.0642603431302628, 0.110657989809447, 0.0690773551330407, 0.00118086944728295,
0.0174511459110349, 0.0648472703208925, 0.166331892126991)


apportion_integer <- function(weights, n) {
  if (n <= 0L) return(rep.int(0L, length(weights)))
  w <- ifelse(is.na(weights) | weights < 0, 0, weights)
  if (sum(w) == 0) return(rep.int(0L, length(weights)))
  w <- w / sum(w)
  
  raw <- w * n
  out <- floor(raw)
  rem <- as.integer(n - sum(out))
  
  if (rem > 0L) {
    idx <- order(raw - out, decreasing = TRUE)[seq_len(rem)]
    out[idx] <- out[idx] + 1L
  }
  
  as.integer(out)
}

apportion_constrained <- function(weights, n, min_vals) {
  if (sum(min_vals) > n) stop("Minimum requirement exceeds total goal.")
  
  alloc <- rep(NA_integer_, length(weights))
  locked <- rep(FALSE, length(weights))
  
  for (i in seq_along(weights)) {
    unlocked_idx <- which(!locked)
    if (length(unlocked_idx) == 0) break
    
    remaining_n <- n - sum(alloc[locked], na.rm = TRUE)
    w_unlocked <- weights[unlocked_idx]
    temp_alloc <- apportion_integer(w_unlocked, remaining_n)
    violations <- temp_alloc < min_vals[unlocked_idx]
    
    if (any(violations)) {
      violator_idx <- unlocked_idx[violations]
      alloc[violator_idx] <- min_vals[violator_idx]
      locked[violator_idx] <- TRUE
    } else {
      alloc[unlocked_idx] <- temp_alloc
      break
    }
  }
  
  alloc
}

ui <- dashboardPage(
  skin = "green",
  dashboardHeader(title = "Seward Lidar Sampling Dashboard"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Trip Dashboard", tabName = "dash", icon = icon("dashboard")),
      menuItem("Map View", tabName = "map_tab", icon = icon("map")),
      menuItem("Feature Space", tabName = "feature_space", icon = icon("chart-area")),
      menuItem("Sync Field Data", tabName = "connect", icon = icon("sync"))
    ),
    hr()
  ),
  dashboardBody(
    tabItems(
      tabItem(tabName = "dash",
              fluidRow(
                valueBoxOutput("total_collected_box", width = 6),
                valueBoxOutput("progress_box", width = 6)
              ),
              fluidRow(
                box(title = "Current Trip Collection vs. Per-Trip Target", width = 12, status = "success",
                    plotlyOutput("progressChart", height = "350px"))
              ),
              fluidRow(
                box(
                  title = "Allocation Goal",
                  width = 12,
                  status = "info",
                  numericInput("final_plot_total", "Final Plot Total", value = DEFAULT_FINAL_PLOT_TOTAL, min = 1, step = 1)
                )
              )
      ),
      tabItem(tabName = "feature_space",
              fluidRow(
                box(width = 12, title = "Filter & Highlight", status = "warning", collapsible = TRUE,
                    helpText("Novelty priorities are calculated after field data is uploaded; they are unavailable before the first upload."),
                    selectizeInput("filter_cluster", "Highlight Cluster ID(s):", choices = NULL, multiple = TRUE, options = list(placeholder = 'Select a Cluster ID'))
                )
              ),
              fluidRow(
                tabBox(width = 12,
                       tabPanel("Scatter Plot", plotlyOutput("scatterPlot", height = "700px")),
                       tabPanel("Priority Table", DTOutput("priorityTable"))
                )
              )
      ),
      tabItem(tabName = "map_tab",
              fluidRow(
                box(width = 12, title = "Map Controls", status = "info", collapsible = TRUE,
                    selectizeInput("zoom_plot", "Search and Zoom to Plot:", choices = NULL, multiple = FALSE, options = list(placeholder = 'Select a point...'))
                )
              ),
              fluidRow(
                box(title = "Spatial Distribution", width = 12, leafletOutput("map", height = "700px"))
              )
      ),
      tabItem(tabName = "connect",
              box(title = "Upload GeoPackage", width = 12, status = "primary",
                  p("Upload your latest field GeoPackage data (.gpkg). The app will extract metrics from the master rasters automatically."),
                  fileInput("gpkg_upload", "Choose .gpkg File", accept = c(".gpkg")),
                  actionButton("btn_load", "Process & Extract Metrics", icon = icon("database"), class = "btn-success")
              )
      )
    )
  )
)

server <- function(input, output, session) {
  
  # --- INITIAL LOAD ---
  base_layers <- reactive({
    potential <- st_read(POTENTIAL_GDB, layer = POTENTIAL_LAYER, quiet = TRUE) %>%
            mutate(base_plot_id = gsub("[a-zA-Z]", "", plot_id))
    
    access <- tryCatch(
      st_read(ACCESS_GDB, layer = ACCESS_LAYER, quiet = TRUE) %>% 
        st_zm(), 
      error = function(e) NULL
    )
    
    list(pot = potential, access = access,
         sraster = rast(SRASTER_PATH), mraster = rast(MRASTER_PATH), 
         crs = st_crs(potential))
  })
  
  # Populate filter choices dynamically
  observe({
    req(base_layers()$pot)
    clusters <- unique(base_layers()$pot$base_plot_id)
    updateSelectizeInput(session, "filter_cluster", choices = sort(na.omit(clusters)), server = TRUE)
    
    plots <- unique(base_layers()$pot$plot_id)
    updateSelectizeInput(session, "zoom_plot", choices = c("", sort(na.omit(plots))), server = TRUE)
  })
  
  # Reactive storage for new field data
  trip_data_store <- reactiveVal(NULL)
  scatter_view_state <- reactiveValues(ranges = NULL)
  
  sampled_data <- reactive({
    new_data <- trip_data_store()
    if (is.null(new_data)) {
      return(base_layers()$pot[0, ])
    }
    new_data
  })

  allocation_targets <- reactive({
    static <- base_layers()
    samples <- sampled_data()
    strata_layer <- static$sraster[[3]]
    final_plot_total <- as.integer(input$final_plot_total %||% DEFAULT_FINAL_PLOT_TOTAL)
    
    if (nrow(samples) > 0 && (!"strata" %in% names(samples) || all(is.na(samples$strata)))) {
      extracted_strata <- terra::extract(strata_layer, terra::vect(samples))
      samples$strata <- extracted_strata[[2]]
    }
    
    sampled_counts <- samples %>%
      st_drop_geometry() %>%
      filter(!is.na(strata)) %>%
      count(strata, name = "sampled_so_far")
    
    alloc_table <- data.frame(
      strata = seq_along(STRATA_PROPORTIONS),
      strata_proportion = STRATA_PROPORTIONS
    )
    
    min_vals <- ifelse(alloc_table$strata_proportion > FREQ_THRESHOLD, MIN_PER_STRATUM, 0L)
    
    alloc_table$target_total_samples <- apportion_constrained(
      weights = alloc_table$strata_proportion,
      n = final_plot_total,
      min_vals = min_vals
    )
    
    alloc_table %>%
      left_join(sampled_counts, by = "strata") %>%
      mutate(
        sampled_so_far = ifelse(is.na(sampled_so_far), 0L, sampled_so_far),
        remaining_target = pmax(target_total_samples - sampled_so_far, 0L)
      )
  })
  
  # Persist scatter zoom/pan between reactive redraws.
  observeEvent(event_data("plotly_relayout", source = "scatter_plot"), {
    rel <- event_data("plotly_relayout", source = "scatter_plot")
    if (is.null(rel)) return()
    
    if (!is.null(rel[["xaxis.autorange"]]) || !is.null(rel[["yaxis.autorange"]])) {
      scatter_view_state$ranges <- NULL
      return()
    }
    
    current_ranges <- if (is.null(scatter_view_state$ranges)) {
      list(x = NULL, y = NULL)
    } else {
      scatter_view_state$ranges
    }
    
    if (!is.null(rel[["xaxis.range[0]"]]) && !is.null(rel[["xaxis.range[1]"]])) {
      current_ranges$x <- c(as.numeric(rel[["xaxis.range[0]"]]), as.numeric(rel[["xaxis.range[1]"]]))
    }
    
    if (!is.null(rel[["yaxis.range[0]"]]) && !is.null(rel[["yaxis.range[1]"]])) {
      current_ranges$y <- c(as.numeric(rel[["yaxis.range[0]"]]), as.numeric(rel[["yaxis.range[1]"]]))
    }
    
    scatter_view_state$ranges <- current_ranges
  }, ignoreInit = TRUE)
  
  # --- MAP ZOOM OBSERVER ---
  observeEvent(input$zoom_plot, {
    req(base_layers()$pot, input$zoom_plot)
    if (input$zoom_plot != "") {
      # Safely filter base_layers()$pot
      target <- base_layers()$pot %>% filter(plot_id == input$zoom_plot)
      
      if (nrow(target) > 0) {
        # Transform the first targeted point into WGS84 for leaflet
        target_wgs <- sf::st_transform(target[1, ], 4326)
        coords <- sf::st_coordinates(sf::st_geometry(target_wgs))
        
        # Use setView for a more reliable immediate jump, ensuring numerics
        leafletProxy("map", session) %>%
          setView(lng = as.numeric(coords[1, "X"]), lat = as.numeric(coords[1, "Y"]), zoom = 17)
      }
    }
  })
  
  # --- SYNC & RASTER EXTRACTION ---
  observeEvent(input$btn_load, {
    req(input$gpkg_upload)
    
    withProgress(message = 'Processing Uploaded Data', value = 0, {
      
      incProgress(0.1, detail = "Loading base layers...")
      static <- base_layers()
      
      # 1. Read the uploaded GeoPackage directly
      incProgress(0.2, detail = "Reading GeoPackage...")
      gpkg_file <- input$gpkg_upload$datapath
      
      # Assuming the first layer in the GeoPackage is the one of interest
      layer_name <- st_layers(gpkg_file)$name[1]
      raw_field <- st_read(gpkg_file, layer = layer_name, quiet = TRUE) %>%
        st_transform(static$crs)
      
      # 2. Extract LiDAR Metrics (mraster)
      incProgress(0.3, detail = "Extracting LiDAR metrics (this may take a bit)...")
      field_with_metrics <- extract_metrics(mraster = static$mraster, existing = raw_field)
      
      if("rumple" %in% names(field_with_metrics)) {
        field_with_metrics <- field_with_metrics %>% rename(rumple_index = rumple)
      }
      
      # 3. Extract Strata (sraster layer 3)
      incProgress(0.3, detail = "Extracting strata values...")
      extracted_strata <- terra::extract(static$sraster[[3]], vect(field_with_metrics))
      field_with_metrics$strata <- extracted_strata[, 2]
      
      incProgress(0.1, detail = "Updating dashboard...")
      trip_data_store(field_with_metrics)
      updateTabItems(session, "tabs", "dash")
      
    })
  })
  
  # --- ANALYTICS ---
  analytics <- reactive({
    static <- base_layers()
    current_samples <- sampled_data()
    
    # NOVELTY RANKING
    sampled_pts <- current_samples %>% st_drop_geometry() %>% select(zq90_plus2, rumple_index) %>% na.omit()
    pot_df <- static$pot %>% st_drop_geometry() %>% select(zq90_plus2, rumple_index, strata, plot_id, base_plot_id) %>% na.omit()

    if (nrow(sampled_pts) == 0) {
      pot_df$novelty_score <- NA_real_
    } else {
      feat_matrix <- rbind(sampled_pts, pot_df %>% select(zq90_plus2, rumple_index))
      scaled <- scale(feat_matrix)
      
      n_samp <- nrow(sampled_pts)
      pot_scaled <- scaled[(n_samp + 1):nrow(scaled), , drop = FALSE]
      samp_scaled <- scaled[seq_len(n_samp), , drop = FALSE]
      
      pot_df$novelty_score <- apply(pot_scaled, 1, function(p) {
        dists <- sqrt((samp_scaled[, 1] - p[1])^2 + (samp_scaled[, 2] - p[2])^2)
        mean(sort(dists)[seq_len(min(5, length(dists)))], na.rm = TRUE)
      })
    }
    
    rank_df <- pot_df %>%
      group_by(base_plot_id) %>%
      mutate(cluster_novelty_score = if (all(is.na(novelty_score))) NA_real_ else mean(novelty_score, na.rm = TRUE)) %>%
      ungroup() %>%
      mutate(novelty_rank = ifelse(is.na(cluster_novelty_score), NA_integer_, dense_rank(desc(cluster_novelty_score)))) %>%
      arrange(is.na(novelty_rank), novelty_rank)
    
    list(ranks = rank_df)
  })
  
  # --- OUTPUTS ---
  output$progressChart <- renderPlotly({
    # Calculate current trip progress per strata
    current_trip <- sampled_data() %>%
      st_drop_geometry() %>%
      filter(!is.na(strata)) %>%
      group_by(strata) %>%
      summarize(collected = n(), .groups = "drop")
    
    # Merge with target_per_trip
    plot_data <- allocation_targets() %>% 
      left_join(current_trip, by = "strata") %>% 
      mutate(collected = ifelse(is.na(collected), 0, collected))
    
    p <- ggplot(plot_data) +
      geom_bar(aes(x = as.factor(strata), y = target_total_samples, fill = "Trip Target",
                   text = paste("Strata: ", strata,
                                "<br>Final Target: ", target_total_samples,
                                "<br>Sampled: ", sampled_so_far,
                                "<br>Remaining Target: ", remaining_target)), stat = "identity", alpha = 0.5) +
      geom_bar(aes(x = as.factor(strata), y = collected, fill = "Current Progress",
                   text = paste("Strata: ", strata, "<br>Current Progress: ", collected)), stat = "identity", width = 0.6) +
      scale_fill_manual(values = c("Trip Target" = "grey70", "Current Progress" = "#2D8E4D")) +
      labs(x = "Strata", y = "Count", fill = "") + theme_minimal()
    
    ggplotly(p, tooltip = "text")
  })
  
  output$scatterPlot <- renderPlotly({
    potential_df <- analytics()$ranks
    current_samples <- sampled_data()
    pal <- rev(terrain.colors(18))[3:18]
    
    # Split data for highlighting
    if (is.null(input$filter_cluster) || length(input$filter_cluster) == 0) {
      bg_df <- data.frame() # empty
      hl_df <- potential_df
      hl_alpha <- 1
      hl_size <- 2
    } else {
      bg_df <- potential_df %>% filter(!(base_plot_id %in% input$filter_cluster))
      hl_df <- potential_df %>% filter(base_plot_id %in% input$filter_cluster)
      hl_alpha <- 1
      hl_size <- 3
    }
    
    p <- ggplot()
    
    # Background points (if any are filtered out)
    if (nrow(bg_df) > 0) {
      p <- p + geom_point(data = bg_df, aes(x = zq90_plus2, y = rumple_index, color = as.factor(strata),
                                            text = paste("Cluster ID:", base_plot_id, 
                                                         "<br>Point ID:", plot_id,
                                                         "<br>Cluster Rank:", novelty_rank, 
                                                         "<br>Strata:", strata)), 
                          alpha = 0.1, size = 1.5) +
        geom_text(data = bg_df, aes(x = zq90_plus2, y = rumple_index, label = plot_id), 
                  alpha = 0.1, vjust = -1, size = 3, check_overlap = TRUE)
    }
    
    # Highlighted / Default points
    if (nrow(hl_df) > 0) {
      p <- p + geom_point(data = hl_df, aes(x = zq90_plus2, y = rumple_index, color = as.factor(strata),
                                            text = paste("Cluster ID:", base_plot_id, 
                                                         "<br>Point ID:", plot_id,
                                                         "<br>Cluster Rank:", novelty_rank, 
                                                         "<br>Cluster Score:", round(cluster_novelty_score, 3),
                                                         "<br>Point Score:", round(novelty_score, 3),
                                                         "<br>Strata:", strata)), 
                          alpha = hl_alpha, size = hl_size) +
        geom_text(data = hl_df, aes(x = zq90_plus2, y = rumple_index, label = plot_id), 
                  vjust = -1, size = 3, check_overlap = TRUE)
    }
    
    p <- p + scale_color_manual(values = pal)

    if (nrow(current_samples) > 0) {
      p <- p + geom_point(data = current_samples, aes(x = zq90_plus2, y = rumple_index, text = "Uploaded Field Data"), color = "purple", alpha = 1, size = 2)
    }
    
    p <- p + labs(title = "Feature Space Gaps (Purple = Uploaded Field Data)",
                  x = "zq90_plus2",
                  y = "rumple_index",
                  color = "Strata") +
      theme_minimal()
    
    scatter_plot <- ggplotly(p, tooltip = "text", source = "scatter_plot")
    
    if (!is.null(scatter_view_state$ranges)) {
      if (!is.null(scatter_view_state$ranges$x)) {
        scatter_plot <- scatter_plot %>% layout(xaxis = list(range = scatter_view_state$ranges$x, autorange = FALSE))
      }
      if (!is.null(scatter_view_state$ranges$y)) {
        scatter_plot <- scatter_plot %>% layout(yaxis = list(range = scatter_view_state$ranges$y, autorange = FALSE))
      }
    }
    
    scatter_plot <- scatter_plot %>% plotly::event_register("plotly_relayout")
    
    scatter_plot %>%
      layout(uirevision = "scatter-view-lock") %>%
      config(modeBarButtonsToRemove = c("select2d", "lasso2d"), displaylogo = FALSE)
  })
  
  output$map <- renderLeaflet({
    current_samples <- sampled_data()
    
    # Set mapview options to use ESRI World Imagery as the default basemap
    mapviewOptions(basemaps = c("Esri.WorldImagery", "OpenStreetMap", "CartoDB.Positron", "OpenTopoMap"))
    
    m <- mapview(base_layers()$pot, zcol = "strata", layer.name = "Potential Sites", alpha.regions = 1, alpha = 1)
    
    if (nrow(current_samples) > 0) {
      m <- m + mapview(current_samples, color = "purple", col.regions = "purple", layer.name = "Uploaded Field Data", alpha.regions = 1, alpha = 1)
    }
    
    if (!is.null(base_layers()$access)) {
      m <- m + mapview(base_layers()$access, color = "white", lwd = 2, layer.name = "Access Layer")
    }
    
    # Convert mapview object to leaflet and add static text labels
    pot_wgs84 <- sf::st_transform(base_layers()$pot, 4326)
    
    # Calculate a unique angle for each label in a circular pattern around the cluster, pushing it outwards
    pot_wgs84 <- pot_wgs84 %>%
      dplyr::mutate(
        angle = (as.numeric(factor(plot_id)) * 137.5) %% 360,
        x_offset = cos(angle * pi / 180) * 15,
        y_offset = sin(angle * pi / 180) * 15
      )
    
    # Build dynamic overlay groups so we only list what we actually generated on the map
    overlay_groups <- c("Potential Sites", "Plot Labels")
    if (nrow(current_samples) > 0) overlay_groups <- c(overlay_groups, "Uploaded Field Data")
    if (!is.null(base_layers()$access)) overlay_groups <- c(overlay_groups, "Access Layer")
    
    m_leaf <- m@map %>%
      leaflet::addLabelOnlyMarkers(
        data = pot_wgs84,
        label = ~as.character(plot_id),
        group = "Plot Labels",
        labelOptions = ~leaflet::labelOptions(
          noHide = TRUE, 
          direction = "center", 
          textOnly = TRUE, 
          offset = c(x_offset, y_offset),
          style = list(
            "color" = "white",
            "font-weight" = "bold",
            "text-shadow" = "1px 1px 2px black, -1px -1px 2px black, 1px -1px 2px black, -1px 1px 2px black"
          )
        )
      ) %>%
      leaflet::addLayersControl(
        position = "topleft",
        baseGroups = c("Esri.WorldImagery", "OpenStreetMap", "CartoDB.Positron", "OpenTopoMap"),
        overlayGroups = overlay_groups,
        options = leaflet::layersControlOptions(collapsed = TRUE)
      ) 
    
    m_leaf
  })
  
  output$priorityTable <- renderDT({
    analytics()$ranks %>%
      transmute(
        novelty_rank,
        plot_id,
        strata = as.factor(strata),
        cluster_novelty_score
      ) %>%
      datatable(filter = "top", options = list(pageLength = 10, dom = 'ltipr'), rownames = FALSE)
  })
  
  output$total_collected_box <- renderValueBox({
    count <- nrow(sampled_data())
    valueBox(count, "Plots Uploaded", icon = icon("location-dot"), color = "blue")
  })
  
  output$progress_box <- renderValueBox({
    total_target <- sum(allocation_targets()$target_total_samples)
    current_total <- nrow(sampled_data())
    perc <- round((current_total / total_target) * 100)
    valueBox(paste0(perc, "%"), "Trip Goal Progress", icon = icon("gauge-high"), color = "green")
  })
}

shinyApp(ui, server)

