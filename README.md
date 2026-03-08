# Risk Intelligence Dashboard

[![Live Demo](https://img.shields.io/badge/Live%20Demo-Shinyapps.io-brightgreen)](https://YOUR_ACCOUNT.shinyapps.io/risk-intelligence-dashboard/)
[![R Shiny](https://img.shields.io/badge/Built%20with-R%20Shiny-blue)](https://shiny.rstudio.com/)
[![Data](https://img.shields.io/badge/Data-NZ%20Police%202023-lightgrey)](https://catalogue.data.govt.nz)

> 🟢 **Runs in demo mode — no SQL Server required.**  
> Clone the repo, run `generate_demo_data.R` once, open `app.R`, click Run App.

An end-to-end forensic analytics solution that fuses a **normalised SQL database**, a **live NZ Government open data API**, and a **6-factor composite threat scoring engine** to deliver automated risk prioritisation through an interactive R Shiny dashboard.

Built to replicate the multi-source data integration problems common in operational consulting — where decisions must be made by combining internal records with external public context in real time.

---

## What It Does

The dashboard ingests three concurrent data streams:

1. **Internal risk database** — a normalised SQL Server database (`RiskIntelDB`) tracking individuals, assigned assets, camera locations, EAN-13 equipment barcodes, and scan events across five related tables
2. **NZ Police regional crime statistics** — pulled live from [data.govt.nz](https://catalogue.data.govt.nz) via the CKAN API (Year Ended December 2023)
3. **Vehicle licence plate registry** — ANPR-style plate detections cross-referenced against a registered-district lookup to flag cross-district movement as a forensic escalation signal

These streams are merged and passed through a **6-factor composite threat scoring engine** that classifies each detection as `CRITICAL`, `ELEVATED`, `ROUTINE`, or `CLEAR`:

| Factor | Signal | Weight |
|---|---|---|
| Individual risk profile | Restricted / Moderate / Low | ×3.0 / ×1.5 / ×0.8 |
| Equipment risk category | High / Medium / Low (EAN-13 barcode) | ×3.0 / ×1.5 / ×0.5 |
| Regional crime index | NZ Police proceedings ≥ 10,000 | ×2.0 / ×1.0 |
| Purchase quantity | Multiple items in single transaction | ×1.5 |
| Payment method | Cash — no identity trail | ×1.3 |
| Time of day | 9pm–5am NZST | ×1.4 |
| Vehicle movement | Out-of-district / watch-list plate | ×1.5 / ×2.0 |

> **Priority thresholds:** CRITICAL ≥ 9.0 · ELEVATED ≥ 4.5 · ROUTINE ≥ 2.0 · CLEAR < 2.0

---

## Dashboard Panels

| Panel | Description |
|---|---|
| **KPI Bar** | Total detections, critical alerts, individuals tracked, out-of-district vehicles |
| **Detection Map** | Leaflet interactive map — colour-coded priority markers, full detection detail on click |
| **Movement Timeline** | Individual movement history plotted by time, location, and priority classification |
| **Detection Volume** | Hourly detection count stacked by priority — identifies peak activity windows |
| **Vehicle Activity** | Cross-district plate movement by location — watch list vs out-of-district vs local |
| **Detection Log** | Filterable data table with conditional formatting, barcode, plate, and threat score columns |
| **Executive Summary** | Auto-generated written briefing synthesising all findings into a decision-ready report |

---

## Architecture

```
data.govt.nz CKAN API (httr + jsonlite)
      │
      ▼
get_nz_police_context()       ← Real 2023 proceedings, graceful fallback
      │
      ▼
get_app_data()  ─── SQL Server (live) ─── PurchaseLog → SurveillanceLog
      │
      ├── data/demo_data.csv  (CSV fallback — stale-schema detection + auto-skip)
      └── Synthetic 80-row   (in-memory fallback — never blank screen)
                    │
                    ▼
        6-Factor Threat Scoring Engine
  person × equipment × region × qty × payment × night × vehicle
                    │
                    ▼
          Shiny Dashboard (7 panels)
```

### Database Schema — 5 Normalised Tables

```
Staff ──────────── CurrentAssignments ──── Assets (EAN-13 barcodes)
                                              │
                                         BarcodeScanned
                                              │
SurveillanceLog ── CameraID ──────────── Cameras (GPS per NZ Police district)
```

---

## Quick Start

```r
# 1. Install dependencies
install.packages(c(
  "shiny", "bslib", "bsicons", "leaflet", "DT",
  "DBI", "odbc", "dplyr", "ggplot2",
  "httr", "jsonlite", "scales"
))

# 2. Clone the repo
# git clone https://github.com/dangminhcuong07-cpu/risk-intelligence-dashboard

# 3. Generate demo data (run once)
source("generate_demo_data.R")

# 4. Launch
shiny::runApp("app.R")
```

---

## Run With Live SQL (Optional)

```
Server:   localhost\SQLEXPRESS
Database: RiskIntelDB  (create in SSMS first)
Auth:     Windows Authentication
```

Run `schema.sql` Sections 1–4 in SSMS to build and seed the database. The app auto-detects the connection and switches from demo to live mode. Run **Section 5 only** to refresh stale timestamps.

---

## File Structure

```
risk-intelligence-dashboard/
├── app.R                     # Shiny dashboard — UI + server + scoring engine
├── analysis.R                # Standalone investigation script
├── schema.sql                # SQL Server schema + seed data (7 cameras, 12 districts)
├── generate_demo_data.R      # Regenerates demo_data.csv with full current schema
├── DEPLOY.md                 # Step-by-step Shinyapps.io deployment guide
├── data/
│   └── demo_data.csv         # 80-row demo — vehicles, barcodes, 7 districts
├── map.png
├── summary.png
└── README.md
```

---

## NZ Police Data Source

| District | Proceedings (YE Dec 2023) | Source |
|---|---|---|
| Counties Manukau | 15,008 | ✅ Confirmed — Figure.NZ |
| Bay of Plenty | 14,648 | ✅ Confirmed — Figure.NZ |
| Waikato | 10,954 | ✅ Confirmed — Figure.NZ |
| Wellington | 10,463 | ✅ Confirmed — Figure.NZ |
| Auckland City | 10,396 | ✅ Confirmed — Figure.NZ |
| Canterbury | ~12,500 | Estimated |
| Waitematā | ~10,900 | Estimated |
| Eastern | ~9,100 | Estimated |
| Central / Southern | ~8,900 each | Estimated |
| Tasman | 5,633 | ✅ Confirmed — Figure.NZ |
| Northland | 5,459 | ✅ Confirmed — Figure.NZ |

High Risk threshold set at **≥ 10,000 proceedings** — at 7,000 (previous), 10 of 12 districts qualified, making the regional factor near-meaningless in scoring.

---

## Skills Demonstrated

| Skill | Evidence |
|---|---|
| Relational database design | 5 normalised tables, FK constraints, safe migration pattern |
| Multi-table SQL JOINs | 5-way JOIN across full schema |
| External API integration | `httr` + `jsonlite` CKAN call with column-defensive aggregation |
| Three-source data pipeline | SQL → CSV → synthetic — never a blank screen |
| Composite risk scoring | 6-factor multiplicative engine, 4 priority levels |
| Geospatial visualisation | Leaflet map with real GPS per NZ Police district |
| Forensic data modelling | EAN-13 barcode + ANPR plate cross-district movement |
| Data storytelling | Executive Summary — raw scores → decision-ready briefing |

---

## Roadmap

- Anomaly detection — continuous `P(high_risk)` score from historical scan pattern modelling
- Automated PDF export — rmarkdown briefing for non-technical stakeholders
- Shinyapps.io deployment — public live demo URL

---

## Author

**Michael Dang** · Master of Business Analytics, University of Auckland  
[linkedin.com/in/michael-dang-964622193](https://linkedin.com/in/michael-dang-964622193)
