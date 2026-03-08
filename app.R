# ==============================================================================
# Forensic Asset Intelligence Dashboard — app.R
# Author: Michael Dang | Master of Business Analytics, University of Auckland
#
# What it does:
#   Tracks retail purchase of high-risk equipment (knives, cutters, tools)
#   via EAN barcode scans at POS, cross-references purchaser identity and
#   risk profile against NZ Police district crime statistics (YE Dec 2023),
#   and auto-classifies each detection as CRITICAL / ELEVATED / ROUTINE / CLEAR
#   using a 6-factor composite threat scoring engine.
#
# Data fallback chain (never shows blank screen):
#   1. SQL Server live  — RiskIntelDB, PurchaseLog first, SurveillanceLog second
#   2. data/demo_data.csv
#   3. Synthetic 80-row in-memory dataset
#
# NZ Police District Data — Source & Notes:
#   Source: NZ Police Recorded Crime Offenders Statistics (Proceedings)
#           Year Ended December 2023, via Figure.NZ / data.govt.nz
#   NZ has exactly 12 police districts. Sub-area names (Hawke's Bay, Manawatu,
#   Otago, Southland) are NOT police districts — they belong to Eastern,
#   Central, and Southern districts respectively.
#   Confirmed totals (summed from Figure.NZ offence breakdown tables):
#     Counties Manukau 15,008 | Bay of Plenty 14,648 | Waikato 10,954
#     Wellington 10,463       | Auckland City 10,396  | Tasman 5,633
#     Northland 5,459
#   Estimated (derived from NZ total ~123,411 minus confirmed districts):
#     Canterbury ~12,500 | Waitematā ~10,900 | Central ~8,900
#     Eastern ~9,100     | Southern ~8,900
#
# HIGH_RISK_THRESHOLD: 10,000 proceedings
#   At 7,000, nearly all NZ districts qualify as High Risk — not useful.
#   At 10,000, the 7 highest-volume districts are High Risk, 5 are Moderate.
#   This gives meaningful differentiation across the country.
#
# Install once:
# install.packages(c("shiny","bslib","bsicons","leaflet","DT","DBI","odbc",
#                    "dplyr","ggplot2","httr","jsonlite","scales"))
# ==============================================================================

library(shiny)
library(bslib)
library(bsicons)
library(DBI)
library(odbc)
library(dplyr)
library(ggplot2)
library(leaflet)
library(DT)
library(scales)
library(readr)

# Optional: httr + jsonlite for NZ Police API (replaces ckanr)
HTTR_AVAILABLE     <- requireNamespace("httr",     quietly = TRUE)
JSONLITE_AVAILABLE <- requireNamespace("jsonlite", quietly = TRUE)
API_AVAILABLE      <- HTTR_AVAILABLE && JSONLITE_AVAILABLE


# ==============================================================================
# 1. NZ POLICE DISTRICT COORDINATES — 12 official districts only
#    (source: NZ Police website district pages)
# ==============================================================================
DISTRICT_COORDS <- data.frame(
  District = c(
    "Auckland City",    "Counties Manukau", "Waitematā",
    "Waikato",          "Bay of Plenty",    "Eastern",
    "Central",          "Wellington",       "Tasman",
    "Canterbury",       "Southern",         "Northland"
  ),
  Lat = c(
    -36.8509, -37.0082, -36.7850,
    -37.7870, -37.6878, -39.4928,
    -40.3523, -41.2865, -41.2706,
    -43.5321, -45.8788, -35.7275
  ),
  Lng = c(
    174.7645, 174.8996, 174.7300,
    175.2793, 176.1651, 176.9120,
    175.6082, 174.7762, 173.2840,
    172.6362, 170.5028, 174.3228
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# 2. NZ POLICE REGIONAL CRIME CONTEXT
#    Source: NZ Police Recorded Crime Offenders Statistics, YE Dec 2023
#    API resource: catalogue.data.govt.nz
#    resource_id: 76839352-71c1-4857-8461-9f3d6da55319
#
#    NOTE ON API DATA STRUCTURE:
#    The CKAN datastore returns one row per district × offence-type combination.
#    Total proceedings per district = sum of Value across all offence rows.
#    The API call below filters for Year==2023 and aggregates correctly.
#    If the API is unavailable or columns differ, confirmed 2023 fallback is used.
# ==============================================================================
NZ_POLICE_RESOURCE_ID <- "76839352-71c1-4857-8461-9f3d6da55319"
HIGH_RISK_THRESHOLD   <- 10000   # BUG FIX: was 7000 — at 7000 almost all NZ
                                  # districts qualify as High Risk, making the
                                  # scoring factor meaningless. 10000 gives
                                  # 7 High Risk / 5 Moderate split.

# Hardcoded fallback: confirmed + estimated 2023 totals
# "Confirmed" = summed from Figure.NZ offence-type breakdown tables
# "Estimated" = derived from national total ~123,411 minus confirmed districts
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
     5633,  # Confirmed (partial) — Figure.NZ YE Dec 2023
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
      "?resource_id=", NZ_POLICE_RESOURCE_ID,
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

    # Convert list of records to data frame
    df <- do.call(rbind, lapply(records, as.data.frame, stringsAsFactors = FALSE))

    # Identify district and value columns defensively
    # Expected: a district/boundary column and a numeric value column
    dist_col <- intersect(c("District","district","Police_District","boundary"),
                          names(df))[1]
    val_col  <- intersect(c("Value","value","Proceedings","Count"),
                          names(df))[1]

    if (is.na(dist_col) || is.na(val_col)) {
      stop("Expected columns not found. Available: ",
           paste(names(df), collapse = ", "))
    }

    # Aggregate: sum all offence types per district
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
    message("[API] Unavailable (", conditionMessage(e),
            ") — using confirmed 2023 NZ Police data.")
    NZ_POLICE_FALLBACK
  })
}

# ==============================================================================
# load_nz_police_csv — Parses the NZ Police AEG proceedings CSV
#
# Handles:
#   - UTF-8 BOM header (﻿Table 1 → Table 1)
#   - Vietnamese date format: "thg MYYYY" → parsed to year + month
#   - Aggregates to year × offence_type totals ready for trend charts
#   - Future-proof: auto-detects all years present in the file
#
# Returns a list with two data frames:
#   $by_year_offence  — year × ANZSOC Division × Proceedings (for trend chart)
#   $annual_totals    — year × total Proceedings (for KPI + summary)
# ==============================================================================
load_nz_police_csv <- function(path = "AEG_Full_Data_data.csv") {
  if (!file.exists(path)) {
    message("[CSV] AEG file not found at: ", path)
    return(NULL)
  }
  tryCatch({
    # read_csv handles UTF-8-BOM automatically
    raw <- readr::read_csv(path, show_col_types = FALSE)

    # Normalise column names (BOM-safe)
    names(raw) <- trimws(gsub("\\uFEFF|\xEF\xBB\xBF", "", names(raw)))

    # Expect: "Table 1", "ANZSOC Division", "Year Month", "Proceedings"
    required <- c("ANZSOC Division", "Year Month", "Proceedings")
    missing  <- setdiff(required, names(raw))
    if (length(missing) > 0) stop("Missing columns: ", paste(missing, collapse=", "))

    # Parse "thg MYYYY" Vietnamese date format → year integer
    # "thg 22023" → year=2023, "thg 122024" → year=2024
    raw$year <- as.integer(
      sub(".*?(\\d{4})$", "\\1", raw[["Year Month"]])
    )
    raw$month <- as.integer(
      sub("^thg\\s+(\\d+)\\d{4}$", "\\1", raw[["Year Month"]])
    )
    raw <- raw[!is.na(raw$year) & raw$year >= 2020, ]

    # Aggregate: year × offence type
    by_year_offence <- raw %>%
      group_by(year, offence = `ANZSOC Division`) %>%
      summarise(Proceedings = sum(as.numeric(Proceedings), na.rm = TRUE),
                .groups = "drop")

    # Annual totals
    annual_totals <- by_year_offence %>%
      group_by(year) %>%
      summarise(Total = sum(Proceedings), .groups = "drop") %>%
      arrange(year)

    message("[CSV] Loaded AEG data: ",
            min(annual_totals$year), "–", max(annual_totals$year),
            " | Latest year total: ",
            format(annual_totals$Total[nrow(annual_totals)], big.mark=","))

    list(by_year_offence = by_year_offence, annual_totals = annual_totals)

  }, error = function(e) {
    message("[CSV] Failed to parse AEG file: ", conditionMessage(e))
    NULL
  })
}



# ==============================================================================
# 3. EQUIPMENT RISK CLASSIFICATION — EAN-13 barcodes
# ==============================================================================
EQUIPMENT_RISK <- data.frame(
  Barcode = c(
    "9300601123456", "9300601234567", "9300601345678",
    "9300601456789", "9300601567890", "9300601678901",
    "9300602123456", "9300602234567", "9300602345678",
    "9300602456789", "9300602567890",
    "9300603123456", "9300603234567"
  ),
  ProductName = c(
    "Stanley FatMax Knife",         "Gerber Folding Knife",
    "Knipex Bolt Cutters 200mm",    "Irwin Wire Cutters Heavy Duty",
    "Master Lock Bypass Tool Set",  "Milwaukee Angle Grinder 115mm",
    "Stanley Zip Ties 300mm x100",  "3M Duct Tape 50m",
    "Maglite XL200 Torch",          "Disposable Nitrile Gloves x100",
    "Balaclava Thermal",
    "Bunnings Padlock 40mm",        "Ryobi Drill Driver 18V"
  ),
  EquipmentRisk = c(
    "High", "High", "High", "High", "High", "High",
    "Medium", "Medium", "Medium", "Medium", "Medium",
    "Low", "Low"
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# 4. VEHICLE LICENCE PLATE REGISTRY
#    BUG FIX: RegisteredDistrict now uses actual NZ Police district names
#    (previously used sub-area names that don't exist as police districts)
# ==============================================================================
VEHICLE_PLATES <- data.frame(
  Plate = c(
    "FKZ819", "HTR442", "BJM291", "WLG003", "CNT557",
    "AKL991", "NTH228", "WKT661", "BOP972", "EAS663",
    "CTL401", "TSM119", "SRN445", "WTM228", "CMK883"
  ),
  RegisteredDistrict = c(
    "Counties Manukau", "Wellington",    "Auckland City",
    "Wellington",       "Canterbury",
    "Auckland City",    "Northland",     "Waikato",
    "Bay of Plenty",    "Eastern",
    "Central",          "Tasman",        "Southern",
    "Waitematā",        "Counties Manukau"
  ),
  VehicleRisk = c(
    "High",   "High",   "High",
    "Medium", "Medium",
    "Low",    "Low",    "Low",
    "Medium", "Medium",
    "Low",    "Low",    "Medium",
    "Low",    "High"
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# 5. STAFF PROFILES — 15 individuals, 4 risk levels
#    BUG FIX: HomeDistrict now uses actual NZ Police district names
# ==============================================================================
STAFF_PROFILES <- data.frame(
  FullName = c(
    "Alex Turner",   "Sarah Kim",     "James Patel",   "Michael Chen",
    "Emma Wilson",   "David Nguyen",  "Lisa Thompson", "Robert Scott",
    "Anna Lee",      "Chris Morgan",  "Nina Sharma",   "Tom Bradley",
    "Jess Huang",    "Mark Evans",    "Priya Desai"
  ),
  RiskLevel = c(
    "Restricted", "Restricted", "Restricted", "Moderate",
    "Restricted", "Moderate",   "Moderate",   "Restricted",
    "Moderate",   "Moderate",   "Low",        "Low",
    "Moderate",   "Restricted", "Low"
  ),
  HomeDistrict = c(
    "Auckland City",    "Counties Manukau", "Wellington",   "Canterbury",
    "Auckland City",    "Waikato",          "Bay of Plenty","Wellington",
    "Northland",        "Canterbury",       "Southern",     "Tasman",
    "Waitematā",        "Auckland City",    "Central"
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# 6. THREAT SCORING ENGINE — 6 factors
#
# ThreatScore = PersonRisk × EquipmentRisk × RegionalRisk
#               × CombinationBonus × PaymentBonus × NightBonus × VehicleBonus
#
# Weights:
#   Person:      Restricted=3.0  Moderate=1.5  Low=0.8   Unknown=1.0
#   Equipment:   High=3.0        Medium=1.5    Low=0.5
#   Region:      High Risk=2.0   Moderate=1.0
#   Combination: Qty > 1 → ×1.5
#   Cash:        no identity trail → ×1.3
#   Night:       9pm–5am → ×1.4
#   Vehicle:     out-of-district plate → ×1.5; High risk plate → ×2.0
#
# Priority thresholds:
#   CRITICAL  >= 12.0 | ELEVATED >= 5.5 | ROUTINE >= 2.0 | CLEAR < 2.0
# ==============================================================================
score_threat <- function(df) {
  equipment_w <- c("High" = 3.0, "Medium" = 1.5, "Low" = 0.5)
  person_w    <- c("Restricted" = 3.0, "Moderate" = 1.5, "Low" = 0.8, "Unknown" = 1.0)
  region_w    <- c("High Risk" = 2.0, "Moderate" = 1.0)
  vehicle_w   <- c("High" = 2.0, "Medium" = 1.5, "Low" = 1.0, "None" = 1.0)

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
      VehicleRiskLevel = ifelse(is.na(VehicleRisk) | VehicleRisk == "", "None", VehicleRisk),
      OutOfDistrict    = !is.na(PlateRegisteredDistrict) &
                         !is.na(CameraLocation) &
                         PlateRegisteredDistrict != CameraLocation,
      VehicleBonus     = case_when(
        VehicleRiskLevel == "High"                     ~ 2.0,
        VehicleRiskLevel == "Medium" & OutOfDistrict   ~ 1.5,
        OutOfDistrict                                  ~ 1.3,
        TRUE                                           ~ 1.0
      ),
      ThreatScore = EquipmentWeight * PersonWeight * RegionWeight *
                    CombinationBonus * PaymentBonus * NightBonus * VehicleBonus,
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
# 7. DATA ACQUISITION ENGINE
#
# Fallback chain:
#   A. SQL Server — PurchaseLog first, then SurveillanceLog
#   B. data/demo_data.csv
#   C. Synthetic 80-row in-memory dataset (never blank screen)
# ==============================================================================

# Separate function for synthetic data so it can be called as emergency fallback
generate_synthetic_data <- function() {
  set.seed(42)
  n <- 80
  locations   <- DISTRICT_COORDS$District[1:7]  # 7 most-populous districts
  # Realistic risk distribution: most people are Low/Moderate risk
  # Uniform sampling gives ~33% Restricted → ~60% CRITICAL — looks fake
  # Weighted: 10% Restricted, 50% Moderate, 40% Low → realistic ~8% CRITICAL
  staff_weights <- ifelse(STAFF_PROFILES$RiskLevel == "Restricted", 1,
                   ifelse(STAFF_PROFILES$RiskLevel == "Moderate",   5, 4))
  staff_idx   <- sample(nrow(STAFF_PROFILES), n, replace = TRUE, prob = staff_weights)
  # Most retail purchases are mundane — high-risk equipment should be rare
  equip_weights <- ifelse(EQUIPMENT_RISK$EquipmentRisk == "High",   1,
                   ifelse(EQUIPMENT_RISK$EquipmentRisk == "Medium", 3, 5))
  equip_idx   <- sample(nrow(EQUIPMENT_RISK), n, replace = TRUE, prob = equip_weights)
  has_plate   <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.7, 0.3))
  plate_idx   <- ifelse(has_plate, sample(nrow(VEHICLE_PLATES), n, replace = TRUE), NA)

  # Realistic retail hours: mostly 8am-9pm, rare night detections
  scan_hours   <- sample(c(8:21, 22, 23, 0, 1), n, replace = TRUE,
                          prob = c(rep(6, 14), 2, 1, 0.5, 0.5))
  scan_offsets <- sample(1:(30*86400), n) %% (30*86400)
  scan_times   <- Sys.time() - scan_offsets +
                  (scan_hours - as.integer(format(Sys.time(), "%H"))) * 3600

  data.frame(
    ScanTime               = scan_times,
    CameraLocation         = sample(locations, n, replace = TRUE),
    FullName               = STAFF_PROFILES$FullName[staff_idx],
    RiskLevel              = STAFF_PROFILES$RiskLevel[staff_idx],
    HomeDistrict           = STAFF_PROFILES$HomeDistrict[staff_idx],
    PaymentMethod          = sample(c("Card","Cash","Loyalty"), n,
                                    replace = TRUE, prob = c(0.70,0.15,0.15)),
    Quantity               = sample(1:4, n, replace = TRUE,
                                    prob = c(0.6,0.2,0.1,0.1)),
    ProductName            = EQUIPMENT_RISK$ProductName[equip_idx],
    Barcode                = EQUIPMENT_RISK$Barcode[equip_idx],
    EquipmentRisk          = EQUIPMENT_RISK$EquipmentRisk[equip_idx],
    LicencePlate           = ifelse(has_plate,
                                    VEHICLE_PLATES$Plate[ifelse(is.na(plate_idx), 1, plate_idx)],
                                    NA_character_),
    PlateRegisteredDistrict = ifelse(has_plate,
                                     VEHICLE_PLATES$RegisteredDistrict[ifelse(is.na(plate_idx), 1, plate_idx)],
                                     NA_character_),
    VehicleRisk            = ifelse(has_plate,
                                    VEHICLE_PLATES$VehicleRisk[ifelse(is.na(plate_idx), 1, plate_idx)],
                                    NA_character_),
    CameraLat              = NA_real_,
    CameraLng              = NA_real_,
    stringsAsFactors = FALSE
  )
}

get_app_data <- function() {

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
  }, error = function(e) { message("[SQL] Not reachable — falling back."); NULL })

  data <- NULL

  if (!is.null(con)) {
    message("[SQL] Connected to RiskIntelDB.")

    # Try PurchaseLog (new equipment schema) first
    data <- tryCatch({
      result <- dbGetQuery(con, "
        SELECT
          P.PurchaseTime                        AS ScanTime,
          P.PaymentMethod,
          P.Quantity,
          P.StoreLocation                       AS CameraLocation,
          C.CameraLat,
          C.CameraLng,
          E.ProductName,
          E.Barcode,
          E.RiskCategory                        AS EquipmentRisk,
          COALESCE(S.FullName,  'Unknown')      AS FullName,
          COALESCE(S.RiskLevel, 'Unknown')      AS RiskLevel,
          NULL AS LicencePlate,
          NULL AS PlateRegisteredDistrict,
          NULL AS VehicleRisk
        FROM PurchaseLog      P
        JOIN EquipmentRegistry E ON P.Barcode         = E.Barcode
        LEFT JOIN Staff        S ON P.ResolvedStaffID = S.StaffID
        LEFT JOIN Cameras      C ON P.StoreLocation   = C.CameraLocation
        ORDER BY P.PurchaseTime DESC
      ")
      message("[SQL] PurchaseLog: ", nrow(result), " rows")
      result
    }, error = function(e) {
      message("[SQL] PurchaseLog not found — trying SurveillanceLog...")
      NULL
    })

    # Fall back to SurveillanceLog schema
    if (is.null(data) || nrow(data) == 0) {
      data <- tryCatch({
        result <- dbGetQuery(con, "
          SELECT
            L.ScanTime,
            C.CameraLocation,
            C.CameraLat,
            C.CameraLng,
            S.FullName,
            S.RiskLevel,
            NULL    AS PaymentMethod,
            1       AS Quantity,
            'Unknown Equipment' AS ProductName,
            NULL    AS Barcode,
            'Medium'AS EquipmentRisk,
            NULL    AS LicencePlate,
            NULL    AS PlateRegisteredDistrict,
            NULL    AS VehicleRisk
          FROM SurveillanceLog    L
          JOIN Cameras            C  ON L.CameraID       = C.CameraID
          JOIN Assets             A  ON L.BarcodeScanned = A.BarcodeString
          JOIN CurrentAssignments CA ON A.AssetID        = CA.AssetID
          JOIN Staff              S  ON CA.StaffID       = S.StaffID
          ORDER BY L.ScanTime DESC
        ")
        message("[SQL] SurveillanceLog: ", nrow(result), " rows")
        result
      }, error = function(e) {
        message("[SQL] SurveillanceLog failed: ", conditionMessage(e))
        NULL
      })
    }

    dbDisconnect(con)

    if (!is.null(data) && nrow(data) == 0) {
      message("[SQL] 0 rows — run Section 5 of schema.sql to refresh timestamps.")
      data <- NULL
    }
  }

  # ---- CSV fallback ----------------------------------------------------------
  # Validates that the CSV has all current required columns before accepting it.
  # A stale CSV (saved before vehicles/expanded districts were added) will be
  # missing LicencePlate, PlateRegisteredDistrict, VehicleRisk etc. — in that
  # case we skip it and fall through to the richer synthetic dataset.
  REQUIRED_CSV_COLS <- c("ScanTime", "CameraLocation", "FullName", "RiskLevel",
                          "LicencePlate", "PlateRegisteredDistrict", "VehicleRisk",
                          "EquipmentRisk", "ProductName")
  if (is.null(data)) {
    csv_paths <- c("data/demo_data.csv", "demo_data.csv")
    csv_found <- csv_paths[file.exists(csv_paths)]
    if (length(csv_found) > 0) {
      message("[DEMO] Loading: ", csv_found[1])
      candidate <- tryCatch(
        read.csv(csv_found[1], stringsAsFactors = FALSE) %>%
          mutate(ScanTime = as.POSIXct(ScanTime)),
        error = function(e) { message("[DEMO] CSV failed: ", conditionMessage(e)); NULL }
      )
      missing_cols <- setdiff(REQUIRED_CSV_COLS, names(candidate))
      stale_vehicles <- "LicencePlate" %in% names(candidate) &&
                        all(is.na(candidate$LicencePlate))
      stale_locations <- length(unique(candidate$CameraLocation)) < 5

      if (length(missing_cols) > 0) {
        message("[DEMO] CSV missing columns: ", paste(missing_cols, collapse = ", "),
                " — regenerating.")
        candidate <- NULL
      } else if (stale_vehicles) {
        message("[DEMO] CSV has no vehicle plate data (saved from old schema) — regenerating.")
        candidate <- NULL
      } else if (stale_locations) {
        message("[DEMO] CSV has fewer than 5 districts (saved from old schema) — regenerating.")
        candidate <- NULL
      }
      data <- candidate
    }
  }

  # ---- Synthetic fallback ----------------------------------------------------
  if (is.null(data)) {
    message("[DEMO] Generating synthetic 80-row dataset.")
    data <- generate_synthetic_data()
  }

  # ---- Ensure all required columns exist ------------------------------------
  defaults <- list(
    PaymentMethod           = "Card",
    Quantity                = 1L,
    ProductName             = "Unknown Equipment",
    Barcode                 = NA_character_,
    EquipmentRisk           = "Medium",
    LicencePlate            = NA_character_,
    PlateRegisteredDistrict = NA_character_,
    VehicleRisk             = NA_character_,
    HomeDistrict            = NA_character_
  )
  for (col in names(defaults)) {
    if (!col %in% names(data)) data[[col]] <- defaults[[col]]
  }

  # ---- Enrich with NZ Police regional context --------------------------------
  # BUG FIX: drop pre-existing columns before joining to prevent .x/.y collision
  # (demo_data.csv and SQL results may already carry these columns)
  data <- data %>%
    select(-any_of(c("Regional_Status", "Crime_Proceedings")))

  nz_ctx <- nz_police_ctx()
  data <- data %>%
    left_join(nz_ctx, by = c("CameraLocation" = "Location_Match")) %>%
    mutate(
      Regional_Status   = ifelse(is.na(Regional_Status), "Moderate", Regional_Status),
      Crime_Proceedings = ifelse(is.na(Crime_Proceedings), 0, Crime_Proceedings)
    )

  # ---- Resolve GPS coordinates -----------------------------------------------
  # BUG FIX: safe conditional check — only use DB coords if they exist AND are not all NA
  has_db_coords <- all(c("CameraLat","CameraLng") %in% names(data)) &&
                   !all(is.na(data$CameraLat))

  if (!has_db_coords) {
    coords <- data %>%
      left_join(DISTRICT_COORDS, by = c("CameraLocation" = "District")) %>%
      mutate(
        Lat = ifelse(is.na(Lat), -40.9006, Lat),
        Lng = ifelse(is.na(Lng), 174.8860, Lng)
      ) %>%
      select(Lat, Lng)
    data$CameraLat <- coords$Lat
    data$CameraLng <- coords$Lng
  }

  # BUG FIX: safe rename — only rename if CameraLat exists and Lat doesn't yet
  if ("CameraLat" %in% names(data) && !"Lat" %in% names(data)) {
    data <- data %>% rename(Lat = CameraLat, Lng = CameraLng)
  }

  # ---- Apply threat scoring --------------------------------------------------
  data <- score_threat(data)

  message("[DATA] Ready — ", nrow(data), " rows | ",
          sum(data$Priority == "CRITICAL"), " CRITICAL | ",
          sum(data$Priority == "ELEVATED"), " ELEVATED | ",
          sum(data$Priority == "ROUTINE"),  " ROUTINE | ",
          sum(data$Priority == "CLEAR"),    " CLEAR")
  data
}


# ==============================================================================
# 8. PRIORITY COLOURS
# ==============================================================================
PRIORITY_COLOURS <- c(
  "CRITICAL" = "#e74c3c",
  "ELEVATED" = "#e67e22",
  "ROUTINE"  = "#3498db",
  "CLEAR"    = "#2ecc71"
)


# ==============================================================================
# 9. UI
# ==============================================================================
ui <- page_sidebar(
  title = "Forensic Asset Intelligence Dashboard",
  theme = bs_theme(bootswatch = "darkly", primary = "#e74c3c"),

  sidebar = sidebar(
    width = 250,
    h4("Controls"),
    actionButton("refresh", "⟳  Refresh Data", class = "btn-primary w-100"),
    br(), br(),
    selectInput("risk_filter",   "Filter by Priority:",
                choices = c("All", "CRITICAL", "ELEVATED", "ROUTINE", "CLEAR")),
    selectInput("region_filter", "Filter by Region:",
                choices = c("All Regions")),
    hr(),
    div(
      style = "display:flex; align-items:center; gap:8px;",
      div(style = "width:10px; height:10px; border-radius:50%;
                   background:#00ff88; flex-shrink:0;"),
      uiOutput("last_refreshed", inline = TRUE)
    ),
    hr(),
    tags$small(class = "text-muted",
      "Sources: RiskIntelDB (SQL) + NZ Police API", tags$br(),
      "Crime data: NZ Police YE Dec 2023",          tags$br(),
      "Fallback: data/demo_data.csv"
    )
  ),

  layout_columns(
    fill = FALSE,
    value_box(title = "Total Detections",
              value    = uiOutput("kpi_total"),
              showcase = bs_icon("activity"),
              theme    = "secondary"),
    value_box(title = "Critical Alerts",
              value    = uiOutput("kpi_critical"),
              showcase = bs_icon("exclamation-triangle-fill"),
              theme    = "danger"),
    value_box(title = "Individuals Tracked",
              value    = uiOutput("kpi_individuals"),
              showcase = bs_icon("person-fill"),
              theme    = "secondary"),
    value_box(title = "Out-of-District Vehicles",
              value    = uiOutput("kpi_vehicles"),
              showcase = bs_icon("car-front-fill"),
              theme    = "warning")
  ),

  navset_card_underline(
    nav_panel("🗺️ Detection Map",     leafletOutput("detection_map",  height = "480px")),
    nav_panel("📈 Movement Timeline", plotOutput("timeline_plot",     height = "420px")),
    nav_panel("📊 Detection Volume",  plotOutput("volume_plot",       height = "420px")),
    nav_panel("🚗 Vehicle Activity",  plotOutput("vehicle_plot",      height = "420px")),
    nav_panel("📋 Detection Log",     DTOutput("evidence_table")),
    nav_panel("📄 Executive Summary",   uiOutput("exec_summary")),
    nav_panel("🇳🇿 National Trends",
      fluidRow(
        column(12,
          p("NZ Police recorded crime proceedings 2023–2025 (national, all districts).",
            style="color:grey; font-size:0.88em; margin-bottom:12px;"),
          uiOutput("nz_csv_kpis")
        )
      ),
      plotOutput("trends_by_offence", height = "500px"),
      br(),
      plotOutput("trends_annual",     height = "300px")
    )
  )
)


# ==============================================================================
# 10. SERVER
# ==============================================================================
server <- function(input, output, session) {

  # Load NZ Police AEG CSV once at session start
  # Looks for file in working dir and one level up (covers local + deployed paths)
  aeg_data <- local({
    # sys.frame(0)$ofile gives the path of the currently-sourced file (app.R)
    # This is more reliable than getwd() when RStudio sets a different working dir
    app_dir <- tryCatch(
      dirname(normalizePath(sys.frame(0)$ofile, mustWork = FALSE)),
      error = function(e) getwd()
    )
    if (is.null(app_dir) || length(app_dir) == 0) app_dir <- getwd()

    paths <- unique(c(
      file.path(app_dir,        "AEG_Full_Data_data.csv"),         # app.R folder
      file.path(app_dir, "data","AEG_Full_Data_data.csv"),         # data/ sub
      file.path(getwd(),        "AEG_Full_Data_data.csv"),         # RStudio cwd
      file.path(getwd(), "data","AEG_Full_Data_data.csv")
    ))

    message("[CSV] Searching for AEG file...")
    found <- Filter(file.exists, paths)[1]

    if (is.na(found)) {
      message("[CSV] Not found. Searched:\n", paste(" -", paths, collapse="\n"))
      NULL
    } else {
      message("[CSV] Found: ", found)
      load_nz_police_csv(found)
    }
  })


  # Cache the NZ Police API call as its own reactive — called once per session,
  # not once per output render. Eliminates repeated API calls in the log.
  nz_police_ctx <- reactive({
    get_nz_police_context()
  }) |> bindCache(Sys.Date())   # re-fetch at most once per calendar day

  # BUG FIX: outer tryCatch — if get_app_data() throws any uncaught error,
  # generate synthetic data rather than crashing the reactive and blanking the UI
  dashboard_data <- reactive({
    input$refresh
    invalidateLater(30000, session)
    isolate({
      withProgress(message = "Loading intelligence data...", value = 0.5, {
        tryCatch(
          get_app_data(),
          error = function(e) {
            message("[FATAL] get_app_data() crashed: ", conditionMessage(e))
            message("[FATAL] Falling back to synthetic data.")
            tryCatch(
              {
                synth <- generate_synthetic_data()
                nz_ctx <- NZ_POLICE_FALLBACK
                synth <- synth %>%
                  left_join(nz_ctx, by = c("CameraLocation" = "Location_Match")) %>%
                  mutate(
                    Regional_Status   = ifelse(is.na(Regional_Status), "Moderate", Regional_Status),
                    Crime_Proceedings = ifelse(is.na(Crime_Proceedings), 0, Crime_Proceedings),
                    CameraLat         = NA_real_, CameraLng = NA_real_
                  )
                coords <- synth %>%
                  left_join(DISTRICT_COORDS, by = c("CameraLocation" = "District")) %>%
                  mutate(Lat = ifelse(is.na(Lat), -40.9, Lat),
                         Lng = ifelse(is.na(Lng), 174.9, Lng)) %>%
                  select(Lat, Lng)
                synth$CameraLat <- coords$Lat
                synth$CameraLng <- coords$Lng
                synth <- synth %>% rename(Lat = CameraLat, Lng = CameraLng)
                score_threat(synth)
              },
              error = function(e2) {
                message("[FATAL] Emergency fallback also failed: ", conditionMessage(e2))
                data.frame()  # Return empty frame as last resort
              }
            )
          }
        )
      })
    })
  })

  observe({
    df      <- dashboard_data()
    validate(need(nrow(df) > 0, "No data available"))
    regions <- c("All Regions", sort(unique(df$CameraLocation)))
    updateSelectInput(session, "region_filter", choices = regions)
  })

  filtered_data <- reactive({
    df <- dashboard_data()
    if (nrow(df) == 0) return(df)
    if (input$risk_filter != "All")
      df <- df %>% filter(Priority == input$risk_filter)
    if (!is.null(input$region_filter) && input$region_filter != "All Regions")
      df <- df %>% filter(CameraLocation == input$region_filter)
    df
  })

  output$last_refreshed <- renderUI({
    input$refresh
    invalidateLater(30000, session)
    tags$small(style = "color:grey;", paste("Updated", format(Sys.time(), "%H:%M:%S")))
  })

  # KPI boxes
  output$kpi_total       <- renderUI({ nrow(dashboard_data()) })
  output$kpi_critical    <- renderUI({ sum(dashboard_data()$Priority == "CRITICAL") })
  output$kpi_individuals <- renderUI({ n_distinct(dashboard_data()$FullName) })
  output$kpi_vehicles    <- renderUI({
    df <- dashboard_data()
    sum(!is.na(df$LicencePlate) & df$OutOfDistrict == TRUE, na.rm = TRUE)
  })

  # Detection Map
  output$detection_map <- renderLeaflet({
    df <- filtered_data()
    validate(need(nrow(df) > 0, "No data to display. Adjust filters or refresh."))

    pal <- colorFactor(palette = unname(PRIORITY_COLOURS),
                       levels  = names(PRIORITY_COLOURS))

    leaflet(df) %>%
      addProviderTiles(providers$CartoDB.DarkMatter) %>%
      addCircleMarkers(
        lng         = ~Lng, lat = ~Lat,
        color       = ~pal(Priority),
        radius      = ~case_when(
          Priority == "CRITICAL" ~ 16,
          Priority == "ELEVATED" ~ 12,
          TRUE                   ~ 8
        ),
        fillOpacity = 0.85, stroke = TRUE, weight = 2,
        popup = ~paste0(
          "<strong>", FullName, "</strong><br>",
          "Priority: <b style='color:", PRIORITY_COLOURS[Priority], "'>",
          Priority, "</b><br>",
          "Equipment: ", ProductName, " (", EquipmentRisk, " risk)<br>",
          "Barcode: ", ifelse(is.na(Barcode), "N/A", Barcode), "<br>",
          "Payment: ", ifelse(is.na(PaymentMethod), "N/A", PaymentMethod),
          " | Qty: ", Quantity, "<br>",
          ifelse(!is.na(LicencePlate),
                 paste0("Plate: <b>", LicencePlate, "</b> (reg. ",
                        PlateRegisteredDistrict, ")<br>",
                        ifelse(OutOfDistrict,
                               "<span style='color:#e67e22'>⚠ Out-of-district vehicle</span><br>",
                               "")),
                 "Vehicle: Walk-in (no plate)<br>"),
          "Location: ", CameraLocation, "<br>",
          "District proceedings: ", comma(as.numeric(Crime_Proceedings)), "<br>",
          "Threat score: ", round(ThreatScore, 2), "<br>",
          "Time: ", format(as.POSIXct(ScanTime), "%Y-%m-%d %H:%M")
        )
      ) %>%
      addLegend(position = "bottomright",
                colors   = unname(PRIORITY_COLOURS),
                labels   = names(PRIORITY_COLOURS),
                title    = "Priority", opacity = 0.85)
  })

  # Movement Timeline
  output$timeline_plot <- renderPlot({
    df <- filtered_data()
    validate(need(nrow(df) > 0, "No data to display."))
    df$ScanTime <- as.POSIXct(df$ScanTime)

    ggplot(df, aes(x = ScanTime, y = FullName,
                   colour = Priority, shape = CameraLocation)) +
      geom_point(size = 5, alpha = 0.85) +
      geom_line(aes(group = FullName), linetype = "dashed",
                alpha = 0.3, colour = "grey60") +
      scale_colour_manual(values = PRIORITY_COLOURS) +
      theme_minimal(base_size = 13) +
      theme(
        plot.background   = element_rect(fill = "#2c2c2c", colour = NA),
        panel.background  = element_rect(fill = "#2c2c2c", colour = NA),
        text              = element_text(colour = "white"),
        axis.text         = element_text(colour = "grey80"),
        panel.grid.major  = element_line(colour = "grey30"),
        panel.grid.minor  = element_blank(),
        legend.background = element_rect(fill = "#2c2c2c")
      ) +
      labs(title    = "Individual Movement Timeline",
           subtitle = "Cross-referenced against NZ Police regional crime data (YE Dec 2023)",
           x = "Detection Time", y = NULL,
           colour = "Priority", shape = "Location")
  })

  # Detection Volume by Hour
  output$volume_plot <- renderPlot({
    df <- dashboard_data()
    validate(need(nrow(df) > 0, "No data to display."))
    df$ScanTime <- as.POSIXct(df$ScanTime)
    df$Hour     <- format(df$ScanTime, "%H:00")
    hourly <- df %>% group_by(Hour, Priority) %>%
      summarise(Count = n(), .groups = "drop")

    ggplot(hourly, aes(x = Hour, y = Count, fill = Priority)) +
      geom_col(position = "stack", width = 0.7) +
      scale_fill_manual(values = PRIORITY_COLOURS) +
      theme_minimal(base_size = 13) +
      theme(
        plot.background   = element_rect(fill = "#2c2c2c", colour = NA),
        panel.background  = element_rect(fill = "#2c2c2c", colour = NA),
        text              = element_text(colour = "white"),
        axis.text         = element_text(colour = "grey80"),
        axis.text.x       = element_text(angle = 45, hjust = 1),
        panel.grid.major  = element_line(colour = "grey30"),
        panel.grid.minor  = element_blank(),
        legend.background = element_rect(fill = "#2c2c2c")
      ) +
      labs(title    = "Detection Volume by Hour of Day",
           subtitle = "Identifies peak activity windows for resource allocation",
           x = "Hour", y = "Detection Count", fill = "Priority")
  })

  # Vehicle Activity
  output$vehicle_plot <- renderPlot({
    df <- dashboard_data() %>% filter(!is.na(LicencePlate))
    validate(need(nrow(df) > 0, "No vehicle detections in current data."))

    vehicle_summary <- df %>%
      mutate(
        MovementType = case_when(
          VehicleRisk == "High" ~ "Watch List",
          OutOfDistrict == TRUE ~ "Out-of-District",
          TRUE                  ~ "Local"
        )
      ) %>%
      count(CameraLocation, MovementType) %>%
      arrange(desc(n))

    ggplot(vehicle_summary,
           aes(x = reorder(CameraLocation, n), y = n, fill = MovementType)) +
      geom_col(position = "stack", width = 0.65) +
      coord_flip() +
      scale_fill_manual(values = c(
        "Watch List"      = "#e74c3c",
        "Out-of-District" = "#e67e22",
        "Local"           = "#3498db"
      )) +
      theme_minimal(base_size = 13) +
      theme(
        plot.background   = element_rect(fill = "#2c2c2c", colour = NA),
        panel.background  = element_rect(fill = "#2c2c2c", colour = NA),
        text              = element_text(colour = "white"),
        axis.text         = element_text(colour = "grey80"),
        panel.grid.major  = element_line(colour = "grey30"),
        panel.grid.minor  = element_blank(),
        legend.background = element_rect(fill = "#2c2c2c")
      ) +
      labs(
        title    = "Vehicle Activity by Detection District",
        subtitle = "Out-of-district and watch-list plates flagged as escalation signals",
        x = NULL, y = "Vehicle Detections", fill = "Movement Type"
      )
  })

  # Detection Log
  output$evidence_table <- renderDT({
    df <- filtered_data()
    validate(need(nrow(df) > 0, "No data to display."))

    df <- df %>%
      mutate(
        ScanTime          = format(as.POSIXct(ScanTime), "%Y-%m-%d %H:%M"),
        ThreatScore       = round(ThreatScore, 2),
        Crime_Proceedings = comma(as.numeric(Crime_Proceedings)),
        LicencePlate      = ifelse(is.na(LicencePlate), "—", LicencePlate),
        OutOfDistrict     = ifelse(OutOfDistrict == TRUE, "Yes", "No")
      ) %>%
      select(ScanTime, FullName, RiskLevel, CameraLocation,
             ProductName, EquipmentRisk, Barcode,
             LicencePlate, PlateRegisteredDistrict, OutOfDistrict,
             PaymentMethod, Quantity,
             Crime_Proceedings, ThreatScore, Priority) %>%
      arrange(desc(ThreatScore))

    datatable(
      df,
      colnames = c("Time","Individual","Risk Level","Location",
                   "Equipment","Equip. Risk","Barcode",
                   "Plate","Plate District","Out of District",
                   "Payment","Qty",
                   "District Proceedings","Threat Score","Priority"),
      options  = list(pageLength = 10, scrollX = TRUE,
                      order = list(list(13, "desc"))),
      rownames = FALSE
    ) %>%
      formatStyle(
        "Priority",
        backgroundColor = styleEqual(names(PRIORITY_COLOURS),
                                     c("#5a1010","#5a3010","#1a2a4a","#0d3320")),
        color      = styleEqual(names(PRIORITY_COLOURS), unname(PRIORITY_COLOURS)),
        fontWeight = "bold"
      ) %>%
      formatStyle(
        "OutOfDistrict",
        color = styleEqual(c("Yes","No"), c("#e67e22","grey"))
      )
  })

  # Executive Summary
  output$exec_summary <- renderUI({
    df <- dashboard_data()
    validate(need(nrow(df) > 0, "No data available."))

    n_total        <- nrow(df)
    n_critical     <- sum(df$Priority == "CRITICAL")
    n_elevated     <- sum(df$Priority == "ELEVATED")
    n_routine      <- sum(df$Priority == "ROUTINE")
    n_people       <- n_distinct(df$FullName)
    pct_crit       <- round(100 * n_critical / n_total, 1)
    n_ood_plates   <- sum(!is.na(df$LicencePlate) & df$OutOfDistrict == TRUE, na.rm = TRUE)
    n_watch_plates <- sum(!is.na(df$VehicleRisk) & df$VehicleRisk == "High", na.rm = TRUE)

    peak_loc <- df %>% count(CameraLocation, sort = TRUE) %>%
      slice(1) %>% pull(CameraLocation)

    hr_regions <- df %>% filter(Regional_Status == "High Risk") %>%
      pull(CameraLocation) %>% unique() %>% paste(collapse = ", ")

    crit_names <- df %>% filter(Priority == "CRITICAL") %>%
      pull(FullName) %>% unique() %>% paste(collapse = ", ")

    top_equip <- df %>% filter(EquipmentRisk == "High") %>%
      count(ProductName, sort = TRUE) %>% slice(1) %>% pull(ProductName)

    tagList(
      h3("Executive Briefing", style = "color: #e74c3c; margin-bottom: 20px;"),
      div(style = "background:#1e1e1e; padding:24px; border-radius:8px; line-height:1.9;",

        p(strong("Operational Summary:"), sprintf(
          "This cycle recorded %d total detections across %d tracked individuals.
          %d detections (%s%%) escalated to CRITICAL; %d ELEVATED; %d ROUTINE.",
          n_total, n_people, n_critical, pct_crit, n_elevated, n_routine
        )),

        hr(style = "border-color:#444;"),

        p(strong("Vehicle Intelligence:"), sprintf(
          "%d out-of-district vehicle plates detected across monitored locations.
          %d plates are on the active watch list.
          Cross-district vehicle movement is an escalation factor in threat scoring.",
          n_ood_plates, n_watch_plates
        )),

        hr(style = "border-color:#444;"),

        p(strong("Equipment Intelligence:"), sprintf(
          "Most frequently detected high-risk equipment: %s.
          All detections cross-referenced via EAN-13 barcode against the forensic risk registry.",
          ifelse(length(top_equip) > 0 && !is.na(top_equip), top_equip, "N/A")
        )),

        hr(style = "border-color:#444;"),

        p(strong("Risk Concentration:"), sprintf(
          "Highest detection volume at %s.
          High-risk districts (NZ Police YE Dec 2023, proceedings ≥ 10,000): %s.",
          peak_loc,
          ifelse(nchar(hr_regions) > 0, hr_regions, "None in current view")
        )),

        hr(style = "border-color:#444;"),

        if (n_critical > 0) {
          p(strong("Critical Individuals:"), sprintf(
            "%s — flagged CRITICAL based on Restricted profile,
            high-risk equipment acquisition, and elevated regional crime index.
            Recommend immediate escalation to senior review.", crit_names
          ))
        } else {
          p(strong("Critical Individuals:"),
            "None identified this cycle. Monitoring continues.")
        },

        hr(style = "border-color:#444;"),

        p(strong("Threat Scoring Methodology:"),
          "6-factor composite: individual risk × equipment risk × regional crime index
          × purchase quantity × payment method × time of day × vehicle movement.
          Thresholds: CRITICAL ≥ 12.0 | ELEVATED ≥ 5.5 | ROUTINE ≥ 2.0.
          High Risk district threshold: ≥ 10,000 proceedings (NZ Police YE Dec 2023)."
        ),

        hr(style = "border-color:#444;"),

        p(strong("Data Sources:"),
          "Internal: RiskIntelDB (SQL Server).", br(),
          "District context: NZ Police Recorded Crime Offenders Statistics YE Dec 2023.",
          "Live feed: catalogue.data.govt.nz CKAN API.", br(),
          "National trends: AEG_Full_Data_data.csv — NZ Police proceedings 2023–2025.",
          "See National Trends tab for year-on-year offence breakdown."
        ),

        hr(style = "border-color:#444;"),
        p(em(paste("Report generated:", format(Sys.time(), "%d %B %Y, %H:%M"))),
          style = "color:grey; font-size:0.9em;")
      )
    )
  })

  # ── National Trends: KPI strip ─────────────────────────────────────────────
  output$nz_csv_kpis <- renderUI({
    if (is.null(aeg_data)) {
      return(p("AEG_Full_Data_data.csv not found. Place the file in the app folder.",
               style="color:#e74c3c;"))
    }
    tots <- aeg_data$annual_totals
    cards <- lapply(seq_len(nrow(tots)), function(i) {
      yr  <- tots$year[i]
      tot <- format(tots$Total[i], big.mark = ",")
      div(style = paste0(
        "display:inline-block; background:#1e1e1e; border:1px solid #333;",
        "border-radius:8px; padding:12px 28px; margin:6px; text-align:center;"),
        div(as.character(yr), style="color:grey; font-size:0.85em;"),
        div(tot, style="color:#3498db; font-size:1.6em; font-weight:bold;"),
        div("proceedings", style="color:grey; font-size:0.8em;")
      )
    })
    do.call(tagList, cards)
  })

  # ── National Trends: offence type line chart ────────────────────────────────
  output$trends_by_offence <- renderPlot({
    if (is.null(aeg_data)) return(NULL)
    df <- aeg_data$by_year_offence %>%
      filter(year %in% c(2023, 2024, 2025))

    # Highlight top 6 offences, lump rest into "Other"
    top6 <- df %>%
      group_by(offence) %>%
      summarise(total = sum(Proceedings)) %>%
      arrange(desc(total)) %>%
      slice(1:6) %>%
      pull(offence)

    df <- df %>%
      mutate(offence_grp = ifelse(offence %in% top6, offence, "Other")) %>%
      group_by(year, offence_grp) %>%
      summarise(Proceedings = sum(Proceedings), .groups = "drop")

    ggplot(df, aes(x = factor(year), y = Proceedings,
                   colour = offence_grp, group = offence_grp)) +
      geom_line(linewidth = 1.1) +
      geom_point(size = 3) +
      scale_y_continuous(labels = scales::comma) +
      scale_colour_brewer(palette = "Set2") +
      labs(
        title    = "NZ Police Proceedings by Offence Category (National, 2023–2025)",
        subtitle = "Source: NZ Police Recorded Crime Offenders Statistics — AEG_Full_Data",
        x = "Year", y = "Proceedings", colour = NULL
      ) +
      theme_minimal(base_size = 11) +
      theme(
        plot.background   = element_rect(fill = "#121212", colour = NA),
        panel.background  = element_rect(fill = "#121212", colour = NA),
        text              = element_text(colour = "white"),
        axis.text         = element_text(colour = "#aaaaaa"),
        panel.grid.major  = element_line(colour = "#2a2a2a"),
        panel.grid.minor  = element_blank(),
        legend.background = element_rect(fill = "#121212", colour = NA),
        legend.text       = element_text(colour = "white", size = 9),
        legend.position   = "bottom",
        legend.direction  = "horizontal",
        legend.key.size   = unit(0.8, "lines"),
        plot.title        = element_text(colour = "#e0e0e0", size = 12, face = "bold"),
        plot.subtitle     = element_text(colour = "grey", size = 9),
        plot.margin       = margin(8, 8, 4, 8)
      )
  })

  # ── National Trends: annual total bar chart ─────────────────────────────────
  output$trends_annual <- renderPlot({
    if (is.null(aeg_data)) return(NULL)
    df <- aeg_data$annual_totals %>%
      filter(year %in% c(2023, 2024, 2025))

    ggplot(df, aes(x = factor(year), y = Total, fill = factor(year))) +
      geom_col(width = 0.5) +
      geom_text(aes(label = scales::comma(Total)), vjust = -0.5,
                colour = "white", size = 4.5) +
      scale_y_continuous(labels = scales::comma,
                         expand = expansion(mult = c(0, 0.12))) +
      scale_fill_manual(values = c("2023"="#3498db","2024"="#e74c3c","2025"="#2ecc71")) +
      labs(title   = "Total NZ Proceedings per Year",
           x = NULL, y = "Total Proceedings") +
      theme_minimal(base_size = 11) +
      theme(
        plot.background  = element_rect(fill = "#121212", colour = NA),
        panel.background = element_rect(fill = "#121212", colour = NA),
        text             = element_text(colour = "white"),
        axis.text        = element_text(colour = "#aaaaaa"),
        panel.grid.major = element_line(colour = "#2a2a2a"),
        panel.grid.minor = element_blank(),
        legend.position  = "none",
        plot.title       = element_text(colour = "#e0e0e0", size = 12, face = "bold"),
        plot.margin      = margin(8, 8, 4, 8)
      )
  })

} # end server

# ==============================================================================
shinyApp(ui = ui, server = server)
