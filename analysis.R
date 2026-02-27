# ==============================================================================
# Risk Intelligence — Standalone Analysis Script
# Author: Michael Dang
#
# Purpose: Ad-hoc investigation mode. Pulls all detections from ForensicDB,
#          merges with NZ Police regional context, and outputs a priority
#          scatter plot. Run this independently of the Shiny app.
#
# Requires: SQL Server (localhost\SQLEXPRESS) + ForensicDB
#           OR falls back to data/demo_data.csv automatically
# ==============================================================================

# BUG FIX 1: All libraries at top level — never inside function bodies
library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)
library(ckanr)

# BUG FIX 3: Resolve paths relative to THIS script's location, not the
# working directory — prevents "file not found" when run from any location
script_dir <- tryCatch(
  dirname(rstudioapi::getSourceEditorContext()$path),
  error = function(e) getwd()  # fallback if not in RStudio
)
demo_csv_path <- file.path(script_dir, "data", "demo_data.csv")

# ==============================================================================
# 1. EXTERNAL CONTEXT: NZ Government crime statistics
# ==============================================================================
get_nz_police_context <- function() {
  tryCatch({
    message("[API] Fetching NZ Police regional crime data...")
    ckanr_setup(url = "https://catalogue.data.govt.nz")
    res <- ds_search(
      resource_id = "76839352-71c1-4857-8461-9f3d6da55319",
      limit       = 100,
      as          = "table"
    )
    res$records %>%
      mutate(
        Location_Match    = District,
        Crime_Proceedings = as.numeric(Value),
        Regional_Status   = ifelse(Crime_Proceedings > 100, "High Risk", "Moderate")
      ) %>%
      select(Location_Match, Crime_Proceedings, Regional_Status)

  }, error = function(e) {
    message("[API] Unavailable — using cached fallback data.")
    data.frame(
      Location_Match    = c("Auckland City", "Wellington", "Canterbury"),
      Crime_Proceedings = c(450, 85, 120),
      Regional_Status   = c("High Risk", "Moderate", "High Risk"),
      stringsAsFactors  = FALSE
    )
  })
}

# ==============================================================================
# 2. DATA ACQUISITION: SQL (live) → CSV (demo) fallback
# ==============================================================================
get_investigation_data <- function() {

  con <- tryCatch({
    dbConnect(
      odbc::odbc(),
      Driver                 = "ODBC Driver 17 for SQL Server",
      Server                 = "localhost\\SQLEXPRESS",
      Database               = "ForensicDB",
      Trusted_Connection     = "yes",
      TrustServerCertificate = "yes",
      timeout                = 2
    )
  }, error = function(e) NULL)

  if (!is.null(con)) {
    message("[SQL] Connection successful.")

    # Diagnostic: check row count and date range BEFORE any filtering
    total_rows <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM SurveillanceLog")$n
    message("[SQL] Total rows in SurveillanceLog (no filter): ", total_rows)

    date_range <- dbGetQuery(con,
      "SELECT MIN(ScanTime) AS earliest, MAX(ScanTime) AS latest FROM SurveillanceLog")
    message("[SQL] Data range: ", date_range$earliest, " -> ", date_range$latest)

    # Pull all records — no time filter, seed timestamps may be older than
    # any fixed window since GETDATE() was called at schema setup, not now
    query <- "SELECT L.ScanTime,
                     C.CameraLocation, C.CameraLat, C.CameraLng,
                     S.FullName, S.RiskLevel
              FROM   SurveillanceLog    L
              JOIN   Cameras            C  ON L.CameraID       = C.CameraID
              JOIN   Assets             A  ON L.BarcodeScanned  = A.BarcodeString
              JOIN   CurrentAssignments CA ON A.AssetID         = CA.AssetID
              JOIN   Staff              S  ON CA.StaffID        = S.StaffID
              ORDER  BY L.ScanTime DESC"

    data <- dbGetQuery(con, query)
    message("[SQL] Rows returned after JOIN: ", nrow(data))
    dbDisconnect(con)

    if (nrow(data) == 0) {
      message("[SQL] WARNING: JOIN returned 0 rows. Check that BarcodeScanned values in")
      message("              SurveillanceLog match BarcodeString values in Assets exactly.")
      message("              Run the VERIFY query at the bottom of schema.sql in SSMS.")
    }

    # Merge with regional crime context
    nz_context <- get_nz_police_context()
    data <- data %>%
      left_join(nz_context, by = c("CameraLocation" = "Location_Match"))

  } else {
    message("[DEMO] SQL not detected — loading: ", demo_csv_path)

    # BUG FIX 3: Use resolved path instead of bare relative path
    if (!file.exists(demo_csv_path)) {
      stop("demo_data.csv not found at: ", demo_csv_path,
           "\nMake sure you are running this script from the repo root folder.")
    }
    data <- read.csv(demo_csv_path, stringsAsFactors = FALSE)
    data$ScanTime <- as.POSIXct(data$ScanTime)
  }

  # Priority scoring engine
  data %>%
    mutate(
      Regional_Status = ifelse(is.na(Regional_Status), "Moderate", Regional_Status),
      Priority = ifelse(
        RiskLevel == "Restricted" & Regional_Status == "High Risk",
        "CRITICAL", "ROUTINE"
      )
    )
}

# ==============================================================================
# 3. RUN ANALYSIS
# ==============================================================================
results <- get_investigation_data()

# BUG FIX 4: Guard all summary calculations against 0-row results
if (nrow(results) == 0) {
  message("\n[WARNING] No data returned. Nothing to summarise or plot.")
  message("  If using SQL: run the UPDATE block in schema.sql to refresh timestamps,")
  message("                then check the VERIFY query returns rows in SSMS.")
  message("  If using CSV: check that data/demo_data.csv exists in the repo folder.")

} else {

  cat("\n=== INVESTIGATION SUMMARY ===\n")
  cat("Total detections    :", nrow(results), "\n")
  cat("Critical detections :", sum(results$Priority == "CRITICAL", na.rm = TRUE), "\n")
  cat("Routine detections  :", sum(results$Priority == "ROUTINE",  na.rm = TRUE), "\n")
  cat("Individuals tracked :", n_distinct(results$FullName), "\n")
  cat("Locations covered   :", paste(unique(results$CameraLocation), collapse = ", "), "\n\n")

  print(
    results %>%
      group_by(FullName, Priority, RiskLevel) %>%
      summarise(
        Detections = n(),
        Locations  = paste(unique(CameraLocation), collapse = " | "),
        .groups    = "drop"
      ) %>%
      arrange(desc(Priority))
  )

  # ============================================================================
  # 4. VISUALISATION: Priority scatter plot
  # ============================================================================
  results$ScanTime <- as.POSIXct(results$ScanTime)

  p <- ggplot(results, aes(x = ScanTime, y = FullName, color = Priority)) +
    geom_point(size = 5, alpha = 0.85) +
    geom_line(aes(group = FullName), linetype = "dashed", alpha = 0.3) +
    scale_color_manual(values = c("CRITICAL" = "#e74c3c", "ROUTINE" = "#3498db")) +
    theme_minimal(base_size = 13) +
    labs(
      # BUG FIX 2: Subtitle no longer claims "24 hours" — time filter was removed
      title    = "Detection Timeline — Priority Classification",
      subtitle = "All records | Cross-referenced: NZ Police Regional Crime Index",
      x        = "Detection Time",
      y        = NULL,
      color    = "Priority"
    )

  print(p)
}
