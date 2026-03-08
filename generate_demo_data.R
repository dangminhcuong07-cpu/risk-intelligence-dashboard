# ==============================================================================
# generate_demo_data.R
# Author: Michael Dang | Master of Business Analytics, University of Auckland
#
# PURPOSE: Regenerates data/demo_data.csv with the full current schema.
#
# Run this ONCE from RStudio whenever you need to reset the demo dataset:
#   source("generate_demo_data.R")
#
# The output file replaces any old demo_data.csv that is missing:
#   - Vehicle licence plate columns (LicencePlate, PlateRegisteredDistrict, VehicleRisk)
#   - Expanded district coverage (7 NZ Police districts)
#   - Equipment barcode columns (ProductName, Barcode, EquipmentRisk)
#   - Payment and quantity columns
# ==============================================================================

library(dplyr)

set.seed(42)
n <- 80

DISTRICT_COORDS <- data.frame(
  District = c(
    "Auckland City",    "Counties Manukau", "Waitematā",
    "Waikato",          "Bay of Plenty",    "Eastern",
    "Central",          "Wellington",       "Tasman",
    "Canterbury",       "Southern",         "Northland"
  ),
  Lat = c(-36.8509,-37.0082,-36.7850,-37.7870,-37.6878,-39.4928,
          -40.3523,-41.2865,-41.2706,-43.5321,-45.8788,-35.7275),
  Lng = c(174.7645,174.8996,174.7300,175.2793,176.1651,176.9120,
          175.6082,174.7762,173.2840,172.6362,170.5028,174.3228),
  stringsAsFactors = FALSE
)

EQUIPMENT_RISK <- data.frame(
  Barcode = c(
    "9300601123456","9300601234567","9300601345678","9300601456789",
    "9300601567890","9300601678901","9300602123456","9300602234567",
    "9300602345678","9300602456789","9300602567890",
    "9300603123456","9300603234567"
  ),
  ProductName = c(
    "Stanley FatMax Knife","Gerber Folding Knife","Knipex Bolt Cutters 200mm",
    "Irwin Wire Cutters Heavy Duty","Master Lock Bypass Tool Set",
    "Milwaukee Angle Grinder 115mm","Stanley Zip Ties 300mm x100",
    "3M Duct Tape 50m","Maglite XL200 Torch","Disposable Nitrile Gloves x100",
    "Balaclava Thermal","Bunnings Padlock 40mm","Ryobi Drill Driver 18V"
  ),
  EquipmentRisk = c(
    "High","High","High","High","High","High",
    "Medium","Medium","Medium","Medium","Medium",
    "Low","Low"
  ),
  stringsAsFactors = FALSE
)

VEHICLE_PLATES <- data.frame(
  Plate = c(
    "FKZ819","HTR442","BJM291","WLG003","CNT557",
    "AKL991","NTH228","WKT661","BOP972","EAS663",
    "CTL401","TSM119","SRN445","WTM228","CMK883"
  ),
  RegisteredDistrict = c(
    "Counties Manukau","Wellington","Auckland City",
    "Wellington","Canterbury",
    "Auckland City","Northland","Waikato",
    "Bay of Plenty","Eastern",
    "Central","Tasman","Southern",
    "Waitematā","Counties Manukau"
  ),
  VehicleRisk = c(
    "High","High","High",
    "Medium","Medium",
    "Low","Low","Low",
    "Medium","Medium",
    "Low","Low","Medium",
    "Low","High"
  ),
  stringsAsFactors = FALSE
)

STAFF_PROFILES <- data.frame(
  FullName = c(
    "Alex Turner","Sarah Kim","James Patel","Michael Chen",
    "Emma Wilson","David Nguyen","Lisa Thompson","Robert Scott",
    "Anna Lee","Chris Morgan","Nina Sharma","Tom Bradley",
    "Jess Huang","Mark Evans","Priya Desai"
  ),
  RiskLevel = c(
    "Restricted","Restricted","Restricted","Moderate",
    "Restricted","Moderate","Moderate","Restricted",
    "Moderate","Moderate","Low","Low",
    "Moderate","Restricted","Low"
  ),
  HomeDistrict = c(
    "Auckland City","Counties Manukau","Wellington","Canterbury",
    "Auckland City","Waikato","Bay of Plenty","Wellington",
    "Northland","Canterbury","Southern","Tasman",
    "Waitematā","Auckland City","Central"
  ),
  stringsAsFactors = FALSE
)

# 7 most-populous NZ Police districts — matches synthetic fallback in app.R
locations   <- c("Auckland City","Counties Manukau","Waikato",
                 "Bay of Plenty","Wellington","Canterbury","Northland")

staff_weights <- ifelse(STAFF_PROFILES$RiskLevel == "Restricted", 1,
                  ifelse(STAFF_PROFILES$RiskLevel == "Moderate",   5, 4))
staff_idx   <- sample(nrow(STAFF_PROFILES), n, replace = TRUE, prob = staff_weights)
equip_weights <- ifelse(EQUIPMENT_RISK$EquipmentRisk == "High",   1,
                   ifelse(EQUIPMENT_RISK$EquipmentRisk == "Medium", 3, 5))
equip_idx   <- sample(nrow(EQUIPMENT_RISK), n, replace = TRUE, prob = equip_weights)
detect_loc  <- sample(locations, n, replace = TRUE)
has_plate   <- sample(c(TRUE,FALSE), n, replace = TRUE, prob = c(0.7,0.3))
plate_idx   <- ifelse(has_plate, sample(nrow(VEHICLE_PLATES), n, replace = TRUE), NA)

demo <- data.frame(
  ScanTime                = format(Sys.time() - sample(1:(30*24*3600), n), "%Y-%m-%d %H:%M:%S"),
  CameraLocation          = detect_loc,
  FullName                = STAFF_PROFILES$FullName[staff_idx],
  RiskLevel               = STAFF_PROFILES$RiskLevel[staff_idx],
  HomeDistrict            = STAFF_PROFILES$HomeDistrict[staff_idx],
  PaymentMethod           = sample(c("Card","Cash","Loyalty"), n,
                                   replace = TRUE, prob = c(0.70,0.15,0.15)),
  Quantity                = sample(1:4, n, replace = TRUE, prob = c(0.6,0.2,0.1,0.1)),
  ProductName             = EQUIPMENT_RISK$ProductName[equip_idx],
  Barcode                 = EQUIPMENT_RISK$Barcode[equip_idx],
  EquipmentRisk           = EQUIPMENT_RISK$EquipmentRisk[equip_idx],
  LicencePlate            = ifelse(has_plate,
                                   VEHICLE_PLATES$Plate[ifelse(is.na(plate_idx),1,plate_idx)],
                                   NA_character_),
  PlateRegisteredDistrict = ifelse(has_plate,
                                   VEHICLE_PLATES$RegisteredDistrict[ifelse(is.na(plate_idx),1,plate_idx)],
                                   NA_character_),
  VehicleRisk             = ifelse(has_plate,
                                   VEHICLE_PLATES$VehicleRisk[ifelse(is.na(plate_idx),1,plate_idx)],
                                   NA_character_),
  stringsAsFactors = FALSE
)

# Write to data/ folder (create if needed)
dir.create("data", showWarnings = FALSE)
write.csv(demo, "data/demo_data.csv", row.names = FALSE)

cat("✅ data/demo_data.csv regenerated:\n")
cat("   Rows      :", nrow(demo), "\n")
cat("   Districts :", paste(sort(unique(demo$CameraLocation)), collapse = ", "), "\n")
cat("   With plates:", sum(!is.na(demo$LicencePlate)), "rows\n")
cat("   Walk-ins   :", sum(is.na(demo$LicencePlate)), "rows\n")
