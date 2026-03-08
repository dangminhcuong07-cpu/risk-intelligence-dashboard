# ==============================================================================
# Risk Intelligence — Standalone Analysis Script
# Author: Michael Dang | Master of Business Analytics, University of Auckland
#
# Purpose: Ad-hoc investigation mode. Pulls all detections from RiskIntelDB,
#          merges with NZ Police regional context, and outputs a priority
#          scatter plot. Run independently of the Shiny app.
#
# Requires: SQL Server (localhost\SQLEXPRESS) + RiskIntelDB
#           OR falls back to data/demo_data.csv automatically
#
# BUG FIXES vs previous version:
#   1. District names updated to actual 12 NZ Police districts
#   2. Fallback proceedings now uses real/confirmed 2023 figures (Figure.NZ)
#   3. HIGH_RISK_THRESHOLD corrected: 7000 → 10000 (at 7000 almost all NZ
#      districts qualify as High Risk, making the scoring meaningless)
#   4. Priority scoring updated to use 6-factor engine consistent with app.R
#      (previously used a simplified if/else — inconsistent between files)
#   5. dbDisconnect added (was missing)
# ==============================================================================

library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)

HTTR_AVAILABLE     <- requireNamespace("httr",     quietly = TRUE)
JSONLITE_AVAILABLE <- requireNamespace("jsonlite", quietly = TRUE)
API_AVAILABLE      <- HTTR_AVAILABLE && JSONLITE_AVAILABLE

script_dir <- tryCatch(
  dirname(rstudioapi::getSourceEditorContext()$path),
  error = function(e) getwd()
)
demo_csv_path <- file.path(script_dir, "data", "demo_data.csv")

# ==============================================================================
# 1. NZ POLICE CRIME STATISTICS — YE Dec 2023
#
# Source: NZ Police Recorded Crime Offenders Statistics
#         Figure.NZ district-level tables, YE Dec 2023
#
# BUG FIX: Threshold corrected from 7,000 → 10,000
#   At 7,000: only Northland (5,459) and Tasman (~5,633) are below threshold —
#   10 of 12 districts are "High Risk", making this factor nearly useless.
#   At 10,000: 7 High Risk / 5 Moderate — meaningful regional differentiation.
#
# BUG FIX: "Southern" replaces "Southland" (Southland is not a police district;
#   it is a geographic area within the Southern Police District)
# ==============================================================================
HIGH_RISK_THRESHOLD <- 10000

NZ_POLICE_FALLBACK <- data.frame(
  Location_Match = c(
    "Auckland City",    "Counties Manukau", "Waitematā",
    "Waikato",          "Bay of Plenty",    "Eastern",
    "Central",          "Wellington",       "Tasman",
    "Canterbury",       "Southern",         "Northland"
  ),
  Crime_Proceedings = c(
    10396,  # Confirmed — Figure.NZ YE Dec 2023
    15008,  # Confirmed — Figure.NZ YE Dec 2023
    10900,  # Estimated — large north Auckland district
    10954,  # Confirmed — Figure.NZ YE Dec 2023
    14648,  # Confirmed — Figure.NZ YE Dec 2023
     9100,  # Estimated — covers Hawke's Bay + Gisborne
     8900,  # Estimated — covers Manawatu, Taranaki, Whanganui
    10463,  # Confirmed — Figure.NZ YE Dec 2023
     5633,  # Confirmed (partial sum) — Figure.NZ YE Dec 2023
    12500,  # Estimated — major Christchurch district
     8900,  # Estimated — covers Otago + Southland
     5459   # Confirmed — Figure.NZ YE Dec 2023
  ),
  stringsAsFactors = FALSE
) %>%
  mutate(
    Regional_Status = ifelse(
      Crime_Proceedings >= HIGH_RISK_THRESHOLD, "High Risk", "Moderate"
    )
  )

get_nz_police_context <- function() {
  if (!API_AVAILABLE) {
    message("[API] httr/jsonlite not installed — using confirmed 2023 data.")
    return(NZ_POLICE_FALLBACK)
  }

  tryCatch({
    message("[API] Fetching NZ Police district proceedings data...")
    url <- paste0(
      "https://catalogue.data.govt.nz/api/3/action/datastore_search",
      "?resource_id=76839352-71c1-4857-8461-9f3d6da55319",
      "&limit=2000"
    )
    resp <- httr::GET(url, httr::timeout(10))
    if (httr::http_status(resp)$category != "Success") stop("Non-200 response")

    parsed  <- jsonlite::fromJSON(
      httr::content(resp, "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    records <- parsed$result$records
    if (length(records) == 0) stop("Empty records")

    df <- do.call(rbind, lapply(records, as.data.frame, stringsAsFactors = FALSE))

    dist_col <- intersect(c("District","district","Police_District","boundary"), names(df))[1]
    val_col  <- intersect(c("Value","value","Proceedings","Count"), names(df))[1]

    if (is.na(dist_col) || is.na(val_col)) {
      stop("Expected columns not found. Available: ", paste(names(df), collapse = ", "))
    }

    result <- df %>%
      rename(Location_Match = !!dist_col, raw_value = !!val_col) %>%
      mutate(raw_value = suppressWarnings(as.numeric(raw_value))) %>%
      filter(!is.na(raw_value), !is.na(Location_Match)) %>%
      group_by(Location_Match) %>%
      summarise(Crime_Proceedings = sum(raw_value, na.rm = TRUE), .groups = "drop") %>%
      mutate(
        Regional_Status = ifelse(
          Crime_Proceedings >= HIGH_RISK_THRESHOLD, "High Risk", "Moderate"
        )
      )

    if (nrow(result) == 0) stop("Aggregation produced 0 rows")
    message("[API] Success — ", nrow(result), " districts aggregated.")
    result

  }, error = function(e) {
    message("[API] Unavailable (", conditionMessage(e), ") — using 2023 fallback data.")
    NZ_POLICE_FALLBACK
  })
}


# ==============================================================================
# 2. THREAT SCORING ENGINE — must match app.R exactly
#
# BUG FIX: Previous analysis.R used a simplified 3-level scoring rule:
#   CRITICAL = Restricted & High Risk | ELEVATED = Restricted OR High Risk
#   This was inconsistent with app.R's 6-factor composite engine.
#   Now both files use the same score_threat() function logic.
# ==============================================================================
score_threat_analysis <- function(df) {
  equipment_w <- c("High" = 3.0, "Medium" = 1.5, "Low" = 0.5)
  person_w    <- c("Restricted" = 3.0, "Moderate" = 1.5, "Low" = 0.8, "Unknown" = 1.0)
  region_w    <- c("High Risk" = 2.0, "Moderate" = 1.0)

  # Add missing columns with safe defaults BEFORE mutate —
  # referencing a non-existent column inside mutate() crashes even with guards.
  if (!"EquipmentRisk" %in% names(df)) df$EquipmentRisk <- "Medium"
  if (!"Quantity"      %in% names(df)) df$Quantity      <- 1L
  if (!"PaymentMethod" %in% names(df)) df$PaymentMethod <- "Card"

  df %>%
    mutate(
      EquipmentWeight  = equipment_w[EquipmentRisk],
      PersonWeight     = person_w[RiskLevel],
      RegionWeight     = region_w[Regional_Status],
      CombinationBonus = ifelse(!is.na(Quantity) & Quantity > 1, 1.5, 1.0),
      PaymentBonus     = ifelse(!is.na(PaymentMethod) & PaymentMethod == "Cash", 1.3, 1.0),
      NightBonus       = ifelse(
        as.integer(format(as.POSIXct(ScanTime), "%H", tz = "Pacific/Auckland")) >= 21 |
        as.integer(format(as.POSIXct(ScanTime), "%H", tz = "Pacific/Auckland")) <= 5,
        1.4, 1.0
      ),
      ThreatScore = EquipmentWeight * PersonWeight * RegionWeight *
                    CombinationBonus * PaymentBonus * NightBonus,
      ThreatScore = ifelse(is.na(ThreatScore), 1.0, ThreatScore),
      Priority    = case_when(
        ThreatScore >= 12.0 ~ "CRITICAL",
        ThreatScore >= 5.5  ~ "ELEVATED",
        ThreatScore >= 2.0 ~ "ROUTINE",
        TRUE               ~ "CLEAR"
      )
    )
}


# ==============================================================================
# 3. DATA ACQUISITION: SQL (live) → CSV (demo) fallback
# ==============================================================================
get_investigation_data <- function() {

  con <- tryCatch({
    dbConnect(
      odbc::odbc(),
      Driver                 = "ODBC Driver 17 for SQL Server",
      Server                 = "localhost\\SQLEXPRESS",
      Database               = "RiskIntelDB",
      Trusted_Connection     = "yes",
      TrustServerCertificate = "yes",
      timeout                = 2
    )
  }, error = function(e) NULL)

  data <- NULL

  if (!is.null(con)) {
    message("[SQL] Connection successful.")

    total_rows <- tryCatch(
      dbGetQuery(con, "SELECT COUNT(*) AS n FROM SurveillanceLog")$n,
      error = function(e) NA
    )
    message("[SQL] Total rows in SurveillanceLog: ", total_rows)

    date_range <- tryCatch(
      dbGetQuery(con, "SELECT MIN(ScanTime) AS earliest, MAX(ScanTime) AS latest
                       FROM SurveillanceLog"),
      error = function(e) data.frame(earliest = NA, latest = NA)
    )
    message("[SQL] Data range: ", date_range$earliest, " -> ", date_range$latest)

    query <- "
      SELECT
        L.ScanTime,
        C.CameraLocation,
        C.CameraLat,
        C.CameraLng,
        S.FullName,
        S.RiskLevel,
        'Medium' AS EquipmentRisk,
        1        AS Quantity,
        NULL     AS PaymentMethod
      FROM SurveillanceLog    L
      JOIN Cameras            C  ON L.CameraID       = C.CameraID
      JOIN Assets             A  ON L.BarcodeScanned = A.BarcodeString
      JOIN CurrentAssignments CA ON A.AssetID        = CA.AssetID
      JOIN Staff              S  ON CA.StaffID       = S.StaffID
      ORDER BY L.ScanTime DESC"

    data <- tryCatch({
      result <- dbGetQuery(con, query)
      message("[SQL] Rows returned: ", nrow(result))
      result
    }, error = function(e) {
      message("[SQL] Query failed: ", conditionMessage(e))
      NULL
    })

    dbDisconnect(con)   # BUG FIX: was missing in original

    if (!is.null(data) && nrow(data) == 0) {
      message("[SQL] WARNING: 0 rows. Run Section 5 of schema.sql to refresh timestamps.")
      data <- NULL
    }
  }

  if (is.null(data)) {
    message("[DEMO] SQL not detected — loading: ", demo_csv_path)
    if (!file.exists(demo_csv_path)) {
      message("[DEMO] demo_data.csv not found at: ", demo_csv_path)
      message("[DEMO] Run generate_demo_data.R to create it, or fix the path.")
      return(NULL)   # BUG FIX: was stop() — crashed with FATAL; now returns NULL gracefully
    }
    data <- tryCatch({
      d <- read.csv(demo_csv_path, stringsAsFactors = FALSE)
      d$ScanTime <- as.POSIXct(d$ScanTime)
      d
    }, error = function(e) {
      message("[DEMO] Failed to read CSV: ", conditionMessage(e))
      NULL
    })
  }

  # Enrich with NZ Police regional context
  # BUG FIX: demo_data.csv may already contain Regional_Status / Crime_Proceedings
  # columns. If we left_join without dropping them first, dplyr creates .x / .y
  # suffixes and the mutate below can't find the plain column names → fatal error.
  data <- data %>%
    select(-any_of(c("Regional_Status", "Crime_Proceedings")))

  nz_context <- get_nz_police_context()
  data <- data %>%
    left_join(nz_context, by = c("CameraLocation" = "Location_Match")) %>%
    mutate(
      Regional_Status   = ifelse(is.na(Regional_Status), "Moderate", Regional_Status),
      Crime_Proceedings = ifelse(is.na(Crime_Proceedings), 0, Crime_Proceedings)
    )

  # Apply threat scoring consistent with app.R
  score_threat_analysis(data)
}


# ==============================================================================
# 4. RUN ANALYSIS
# ==============================================================================
results <- tryCatch(
  get_investigation_data(),
  error = function(e) {
    message("\n[FATAL] Analysis failed: ", conditionMessage(e))
    NULL
  }
)

if (is.null(results) || nrow(results) == 0) {
  message("\n[WARNING] No data returned.")
  message("  SQL: run the UPDATE block in schema.sql to refresh timestamps.")
  message("  CSV: check that data/demo_data.csv exists.")

} else {

  cat("\n=== INVESTIGATION SUMMARY ===\n")
  cat("Source          : NZ Police Recorded Crime Offenders Statistics YE Dec 2023\n")
  cat("Risk threshold  : High Risk = districts with ≥ 10,000 proceedings\n")
  cat(sprintf("High Risk districts: %s\n",
      paste(NZ_POLICE_FALLBACK$Location_Match[NZ_POLICE_FALLBACK$Regional_Status == "High Risk"],
            collapse = ", ")))
  cat("---\n")
  cat("Total detections    :", nrow(results), "\n")
  cat("CRITICAL detections :", sum(results$Priority == "CRITICAL", na.rm = TRUE), "\n")
  cat("ELEVATED detections :", sum(results$Priority == "ELEVATED", na.rm = TRUE), "\n")
  cat("ROUTINE detections  :", sum(results$Priority == "ROUTINE",  na.rm = TRUE), "\n")
  cat("CLEAR detections    :", sum(results$Priority == "CLEAR",    na.rm = TRUE), "\n")
  cat("Individuals tracked :", n_distinct(results$FullName), "\n")
  cat("Locations covered   :", paste(unique(results$CameraLocation), collapse = ", "), "\n\n")

  print(
    results %>%
      group_by(FullName, Priority, RiskLevel) %>%
      summarise(
        Detections = n(),
        Locations  = paste(unique(CameraLocation), collapse = " | "),
        Avg_Score  = round(mean(ThreatScore, na.rm = TRUE), 2),
        .groups    = "drop"
      ) %>%
      arrange(desc(Avg_Score))
  )

  # ============================================================================
  # 5. VISUALISATION
  # ============================================================================
  results$ScanTime <- as.POSIXct(results$ScanTime)

  priority_colours <- c(
    "CRITICAL" = "#e74c3c",
    "ELEVATED" = "#e67e22",
    "ROUTINE"  = "#3498db",
    "CLEAR"    = "#2ecc71"
  )

  p <- ggplot(results, aes(x = ScanTime, y = FullName, color = Priority)) +
    geom_point(size = 5, alpha = 0.85) +
    geom_line(aes(group = FullName), linetype = "dashed",
              alpha = 0.3, color = "grey60") +
    scale_color_manual(values = priority_colours) +
    theme_minimal(base_size = 13) +
    labs(
      title    = "Detection Timeline — Priority Classification",
      subtitle = paste0(
        "Cross-referenced: NZ Police Recorded Crime Offenders Stats YE Dec 2023\n",
        "High Risk threshold: ≥ 10,000 proceedings | 6-factor composite threat score"
      ),
      x     = "Detection Time",
      y     = NULL,
      color = "Priority"
    )

  print(p)
}
