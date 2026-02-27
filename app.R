# ==============================================================================
# Risk Intelligence Dashboard
# Author: Michael Dang
# Description: Multi-source analytics dashboard fusing a normalised SQL
#              database with the NZ Government open data API to deliver
#              automated risk prioritisation for operational decision-making.
#
# Run modes:
#   LIVE  — requires SQL Server (localhost\SQLEXPRESS) with ForensicDB loaded
#   DEMO  — falls back to data/demo_data.csv automatically (no setup needed)
# ==============================================================================

#install.packages(c("shiny","bslib","leaflet","DT","DBI","odbc","dplyr","ggplot2","ckanr"))
#install.packages('bsicons')
library(shiny)
library(bslib)
library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)
library(leaflet)
library(DT)
library(ckanr)

# ==============================================================================
# DATA LAYER
# ==============================================================================

# --- External API: NZ Government crime statistics (data.govt.nz) --------------
get_nz_police_context <- function() {
  tryCatch({
    message("[API] Connecting to data.govt.nz...")
    ckanr_setup(url = "https://catalogue.data.govt.nz")
    res <- ds_search(
      resource_id = "76839352-71c1-4857-8461-9f3d6da55319",
      limit = 100,
      as = "table"
    )
    res$records %>%
      mutate(
        Location_Match    = District,
        Crime_Proceedings = as.numeric(Value),
        Regional_Status   = ifelse(Crime_Proceedings > 100, "High Risk", "Moderate")
      ) %>%
      select(Location_Match, Crime_Proceedings, Regional_Status)

  }, error = function(e) {
    message("[API] Unavailable — using cached regional context.")
    data.frame(
      Location_Match    = c("Auckland City", "Wellington", "Canterbury"),
      Crime_Proceedings = c(450, 85, 120),
      Regional_Status   = c("High Risk", "Moderate", "High Risk"),
      stringsAsFactors  = FALSE
    )
  })
}

# --- Primary data engine: SQL (live) → CSV (demo) fallback -------------------
get_app_data <- function() {
  con <- tryCatch({
    dbConnect(
      odbc::odbc(),
      Driver             = "ODBC Driver 17 for SQL Server",
      Server             = "localhost\\SQLEXPRESS",
      Database           = "ForensicDB",
      Trusted_Connection = "yes",
      timeout            = 2
    )
  }, error = function(e) NULL)

  if (!is.null(con)) {
    message("[SQL] Live connection established.")
    data <- dbGetQuery(con,
      "SELECT L.ScanTime,
              C.CameraLocation, C.CameraLat, C.CameraLng,
              S.FullName, S.RiskLevel
       FROM   SurveillanceLog  L
       JOIN   Cameras          C  ON L.CameraID      = C.CameraID
       JOIN   Assets           A  ON L.BarcodeScanned = A.BarcodeString
       JOIN   CurrentAssignments CA ON A.AssetID      = CA.AssetID
       JOIN   Staff            S  ON CA.StaffID       = S.StaffID"
    )
    dbDisconnect(con)

    nz_context <- get_nz_police_context()
    data <- data %>%
      left_join(nz_context, by = c("CameraLocation" = "Location_Match"))

  } else {
    message("[DEMO] SQL not found — loading data/demo_data.csv")
    data <- read.csv("data/demo_data.csv", stringsAsFactors = FALSE)
    data$ScanTime <- as.POSIXct(data$ScanTime)
  }

  # Risk prioritisation engine: cross-references individual risk level
  # against regional crime context to generate a binary CRITICAL / ROUTINE flag
  data %>%
    mutate(
      Regional_Status = ifelse(is.na(Regional_Status), "Moderate", Regional_Status),
      Priority        = ifelse(
        RiskLevel == "Restricted" & Regional_Status == "High Risk",
        "CRITICAL", "ROUTINE"
      )
    )
}

# ==============================================================================
# UI
# ==============================================================================
ui <- page_sidebar(
  title = "Risk Intelligence Dashboard",
  theme = bs_theme(bootswatch = "darkly", primary = "#e74c3c"),

  sidebar = sidebar(
    width = 240,
    h4("Controls"),
    actionButton("refresh", "⟳  Refresh Data", class = "btn-primary w-100"),
    hr(),
    selectInput("risk_filter", "Filter by Priority:",
                choices = c("All", "CRITICAL", "ROUTINE")),
    hr(),
    helpText("Data sources:"),
    helpText("• ForensicDB (SQL Server)"),
    helpText("• data.govt.nz Police API"),
    hr(),
    uiOutput("last_refreshed")
  ),

  # KPI summary bar
  layout_columns(
    fill = FALSE,
    value_box(
      title    = "Total Detections",
      value    = uiOutput("kpi_total"),
      showcase  = bsicons::bs_icon("camera"),
      theme    = "secondary"
    ),
    value_box(
      title    = "Critical Alerts",
      value    = uiOutput("kpi_critical"),
      showcase  = bsicons::bs_icon("exclamation-triangle-fill"),
      theme    = "danger"
    ),
    value_box(
      title    = "Individuals Tracked",
      value    = uiOutput("kpi_individuals"),
      showcase  = bsicons::bs_icon("person-fill"),
      theme    = "secondary"
    ),
    value_box(
      title    = "High-Risk Regions",
      value    = uiOutput("kpi_regions"),
      showcase  = bsicons::bs_icon("geo-alt-fill"),
      theme    = "warning"
    )
  ),

  navset_card_underline(
    nav_panel("Tactical Map",
      leafletOutput("suspect_map", height = "480px")),
    nav_panel("Movement Timeline",
      plotOutput("timeline_plot", height = "420px")),
    nav_panel("Detection Volume",
      plotOutput("volume_plot",   height = "420px")),
    nav_panel("Evidence Log",
      DTOutput("evidence_table")),
    nav_panel("Executive Summary",
      uiOutput("exec_summary"))
  )
)

# ==============================================================================
# SERVER
# ==============================================================================
server <- function(input, output, session) {

  # Reactive dataset — refreshes on button click
  threat_data <- reactive({
    input$refresh
    df <- get_app_data()
    if (!is.null(df) && nrow(df) > 0) {
      df <- df %>% rename(Lat = CameraLat, Lng = CameraLng)
    }
    df
  })

  # Filtered view
  filtered_data <- reactive({
    df <- threat_data()
    if (input$risk_filter != "All") {
      df <- df %>% filter(Priority == input$risk_filter)
    }
    df
  })

  # --- KPI boxes ---------------------------------------------------------------
  output$kpi_total       <- renderUI({ nrow(threat_data()) })
  output$kpi_critical    <- renderUI({ sum(threat_data()$Priority == "CRITICAL") })
  output$kpi_individuals <- renderUI({ n_distinct(threat_data()$FullName) })
  output$kpi_regions     <- renderUI({
    threat_data() %>%
      filter(Regional_Status == "High Risk") %>%
      pull(CameraLocation) %>%
      n_distinct()
  })

  output$last_refreshed <- renderUI({
    input$refresh
    helpText(paste("Last refresh:", format(Sys.time(), "%H:%M:%S")))
  })

  # --- Tactical Map ------------------------------------------------------------
  output$suspect_map <- renderLeaflet({
    df <- filtered_data()
    req(nrow(df) > 0)

    leaflet(df) %>%
      addProviderTiles(providers$CartoDB.DarkMatter) %>%
      addCircleMarkers(
        lng         = ~Lng,
        lat         = ~Lat,
        color       = ~ifelse(Priority == "CRITICAL", "#e74c3c", "#3498db"),
        radius      = ~ifelse(Priority == "CRITICAL", 14, 9),
        fillOpacity = 0.8,
        stroke      = TRUE,
        weight      = 2,
        popup       = ~paste0(
          "<strong>", FullName, "</strong><br>",
          "<span style='color:", ifelse(Priority == "CRITICAL", "#e74c3c", "#3498db"), "'>",
          "⬤ ", Priority, "</span><br>",
          "📍 ", CameraLocation, "<br>",
          "⚠️ Risk Level: ", RiskLevel, "<br>",
          "🗺️ Region: ", Regional_Status, "<br>",
          "📊 Crime Index: ", Crime_Proceedings
        )
      ) %>%
      addLegend(
        position = "bottomright",
        colors   = c("#e74c3c", "#3498db"),
        labels   = c("CRITICAL", "ROUTINE"),
        title    = "Priority",
        opacity  = 0.8
      )
  })

  # --- Movement Timeline -------------------------------------------------------
  output$timeline_plot <- renderPlot({
    df <- filtered_data()
    req(nrow(df) > 0)
    df$ScanTime <- as.POSIXct(df$ScanTime)

    ggplot(df, aes(x = ScanTime, y = FullName, color = Priority, shape = CameraLocation)) +
      geom_point(size = 5, alpha = 0.85) +
      geom_line(aes(group = FullName), linetype = "dashed", alpha = 0.3, color = "grey60") +
      scale_color_manual(values = c("CRITICAL" = "#e74c3c", "ROUTINE" = "#3498db")) +
      theme_minimal(base_size = 13) +
      theme(
        plot.background  = element_rect(fill = "#2c2c2c", color = NA),
        panel.background = element_rect(fill = "#2c2c2c", color = NA),
        text             = element_text(color = "white"),
        axis.text        = element_text(color = "grey80"),
        panel.grid.major = element_line(color = "grey30"),
        panel.grid.minor = element_blank(),
        legend.background = element_rect(fill = "#2c2c2c")
      ) +
      labs(
        title    = "Individual Movement Timeline",
        subtitle = "Cross-referenced against NZ Police regional crime data",
        x = "Detection Time", y = NULL,
        color = "Priority", shape = "Location"
      )
  })

  # --- Detection Volume (trend analysis) ---------------------------------------
  output$volume_plot <- renderPlot({
    df <- threat_data()
    req(nrow(df) > 0)
    df$ScanTime <- as.POSIXct(df$ScanTime)
    df$Hour     <- format(df$ScanTime, "%H:00")

    hourly <- df %>%
      group_by(Hour, Priority) %>%
      summarise(Count = n(), .groups = "drop")

    ggplot(hourly, aes(x = Hour, y = Count, fill = Priority)) +
      geom_col(position = "stack", width = 0.7) +
      scale_fill_manual(values = c("CRITICAL" = "#e74c3c", "ROUTINE" = "#3498db")) +
      theme_minimal(base_size = 13) +
      theme(
        plot.background  = element_rect(fill = "#2c2c2c", color = NA),
        panel.background = element_rect(fill = "#2c2c2c", color = NA),
        text             = element_text(color = "white"),
        axis.text        = element_text(color = "grey80"),
        axis.text.x      = element_text(angle = 45, hjust = 1),
        panel.grid.major = element_line(color = "grey30"),
        panel.grid.minor = element_blank(),
        legend.background = element_rect(fill = "#2c2c2c")
      ) +
      labs(
        title    = "Detection Volume by Hour",
        subtitle = "Identifies peak activity windows for resource allocation",
        x = "Hour of Day", y = "Detection Count", fill = "Priority"
      )
  })

  # --- Evidence Log ------------------------------------------------------------
  output$evidence_table <- renderDT({
    datatable(
      filtered_data() %>%
        select(ScanTime, FullName, RiskLevel, CameraLocation,
               Regional_Status, Crime_Proceedings, Priority),
      options  = list(pageLength = 10, order = list(list(0, "desc"))),
      rownames = FALSE
    ) %>%
      formatStyle(
        "Priority",
        backgroundColor = styleEqual(
          c("CRITICAL", "ROUTINE"), c("#5c1e1e", "#1e2d5c")
        ),
        color = styleEqual(
          c("CRITICAL", "ROUTINE"), c("#e74c3c", "#3498db")
        ),
        fontWeight = "bold"
      )
  })

  # --- Executive Summary -------------------------------------------------------
  output$exec_summary <- renderUI({
    df <- threat_data()
    req(nrow(df) > 0)

    total      <- nrow(df)
    n_critical <- sum(df$Priority == "CRITICAL")
    n_routine  <- sum(df$Priority == "ROUTINE")
    n_people   <- n_distinct(df$FullName)
    high_risk_regions <- df %>%
      filter(Regional_Status == "High Risk") %>%
      pull(CameraLocation) %>%
      unique() %>%
      paste(collapse = ", ")

    critical_names <- df %>%
      filter(Priority == "CRITICAL") %>%
      pull(FullName) %>%
      unique() %>%
      paste(collapse = ", ")

    peak_location <- df %>%
      count(CameraLocation, sort = TRUE) %>%
      slice(1) %>%
      pull(CameraLocation)

    tagList(
      h3("Executive Briefing", style = "color: #e74c3c; margin-bottom: 20px;"),
      div(style = "background:#1e1e1e; padding:24px; border-radius:8px; line-height:1.9;",
        p(strong("Summary:"), sprintf(
          "This cycle recorded %d total detections across %d tracked individuals. 
          %d detections (%d%%) were escalated to CRITICAL priority; %d were classified ROUTINE.",
          total, n_people, n_critical,
          round(n_critical / total * 100), n_routine
        )),
        hr(style = "border-color: #444;"),
        p(strong("Risk Concentration:"), sprintf(
          "The highest detection volume was recorded at %s. 
          High-risk regional designations (based on NZ Police crime index) 
          apply to: %s.",
          peak_location, high_risk_regions
        )),
        hr(style = "border-color: #444;"),
        if (n_critical > 0) {
          p(strong("Critical Individuals:"), sprintf(
            "%s — flagged CRITICAL due to Restricted access profile 
            in a High Risk region. Recommend immediate escalation to senior review.",
            critical_names
          ))
        } else {
          p(strong("Critical Individuals:"), "None identified in this cycle. Monitoring continues.")
        },
        hr(style = "border-color: #444;"),
        p(strong("Data Sources:"),
          "Internal surveillance database (ForensicDB) cross-referenced with 
          live NZ Police regional crime statistics via the NZ Government Open Data API (data.govt.nz). 
          Priority scoring is derived by intersecting individual risk classification 
          with regional crime index thresholds."),
        hr(style = "border-color: #444;"),
        p(em(sprintf("Report generated: %s", format(Sys.time(), "%d %B %Y, %H:%M"))),
          style = "color: grey; font-size: 0.9em;")
      )
    )
  })
}

# ==============================================================================
shinyApp(ui = ui, server = server)
