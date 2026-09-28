# Risk Intelligence Dashboard

> Multi-source risk analytics: SQL Server, NZ Government open data and R Shiny.
> Runs in demo mode without a database: `git clone`, open `app.R`, run the app.

---

## Summary

This project integrates internal detection data with external regional crime context and classifies each detection by priority. It covers relational database design, integration with a public API, a documented scoring model, and a dashboard with a generated written summary.

Built as a capstone project during the Master of Business Analytics at the University of Auckland.

---

## The Problem

Organisations often hold related data in separate systems. This project combines three sources:

- Internal state: personnel, assigned assets and detection logs
- External context: regional crime statistics from NZ Government open data
- Decision point: which detections require immediate action?

A detection's priority depends on several factors at once, including who was involved and where it happened. Looking at one factor alone produces either false positives (operational noise) or missed cases.

The approach: a normalised relational database, combined with district-level crime context, passed through a scoring model and presented in a dashboard.

---

## What's Built Here

### 1. Database architecture

`schema.sql` defines five normalised tables with foreign key constraints:

| Table | Purpose |
|-------|---------|
| `Staff` | Personnel directory with risk classification |
| `CurrentAssignments` | Asset allocation ledger linking staff to assets |
| `Assets` | Inventory of monitored items |
| `Cameras` | Detection hardware registry, including location |
| `SurveillanceLog` | Time-stamped detection events |

Camera locations are held in `Cameras` rather than in each log row, so moving a camera does not require updating historical records.

### 2. Data pipeline

NZ Police district crime data (data.govt.nz CKAN API) → internal SQL Server database → scoring → R Shiny dashboard (KPI bar, tabbed panels and executive summary)

### 3. Risk scoring model

Each detection receives a composite threat score:

```
ThreatScore = PersonRisk × EquipmentRisk × RegionalRisk
              × CombinationBonus × PaymentBonus × NightBonus × VehicleBonus
```

| Factor | Weights |
|--------|---------|
| Person | Restricted 3.0, Moderate 1.5, Low 0.8, Unknown 1.0 |
| Equipment | High 3.0, Medium 1.5, Low 0.5 |
| Region | High Risk 2.0, Moderate 1.0 |
| Quantity | more than one item: ×1.5 |
| Payment | cash: ×1.3 |
| Time of day | 9pm to 6am: ×1.4 |
| Vehicle | high-risk plate ×2.0; medium-risk plate out of district ×1.5; other out-of-district plate ×1.3 |

Priority thresholds: CRITICAL ≥ 12.0, ELEVATED ≥ 5.5, ROUTINE ≥ 2.0, CLEAR below 2.0.

A district is classed as High Risk when it recorded at least 10,000 proceedings (NZ Police, year ended December 2023). Using the 2023 fallback figures, 7 of the 12 districts are High Risk and 5 are Moderate at this threshold. A lower threshold of 7,000 placed nearly every district in the High Risk group, which removed the factor's usefulness.

### 4. Executive summary

The Executive Summary panel generates a short written briefing from the current data: detection counts by priority, out-of-district and watch-list vehicles, the most frequent high-risk equipment, the location with the highest volume, High Risk districts, individuals flagged CRITICAL, and a note on methodology and data sources.

---

## Dashboard Panels

| Panel | What it shows |
|-------|---------------|
| KPI bar | Total detections, critical alerts, individuals tracked, out-of-district vehicles |
| Detection Map | Detections by location on a Leaflet map, sized by priority |
| Movement Timeline | Detection times for each individual |
| Detection Volume | Detection counts by hour of day, stacked by priority |
| Vehicle Activity | Vehicle detections by location and movement type |
| Detection Log | Filterable table of individual detections |
| Executive Summary | Generated written briefing (see above) |
| National Trends | NZ Police recorded crime proceedings 2023 to 2025, from `AEG_Full_Data_data.csv` |

---

## Technical Stack

| Component | Choice | Reason |
|-----------|--------|--------|
| Database | SQL Server (T-SQL) | Widely used relational database |
| Data API | CKAN (data.govt.nz), via `httr` and `jsonlite` | Public data source with a documented API |
| Analytics language | R (Shiny) | Reproducible analysis and interactive dashboards in one language |
| Mapping | Leaflet | Interactive maps within Shiny |
| Fallback strategy | CSV and synthetic data, hardcoded district figures | The dashboard still loads when the database or API is unavailable |

---

## Quick Start

The app runs in demo mode by default, so SQL Server is not required.

```bash
git clone https://github.com/dangminhcuong07-cpu/risk-intelligence-dashboard
cd risk-intelligence-dashboard
Rscript -e "install.packages(c('shiny','bslib','bsicons','leaflet','DT','DBI','odbc','dplyr','ggplot2','httr','jsonlite','scales','readr'))"
Rscript -e "shiny::runApp('app.R')"
```

Shiny prints the local URL in the console when the app starts. See `INSTALL.md` for connecting to SQL Server.

---

## Design Decisions

### Separating event logs from master data

An early version stored GPS coordinates directly in the detection log, so moving one camera meant updating every historical row for that camera. Location now lives in the `Cameras` table. Adding or moving a camera changes one row, and historical log records are not modified.

### Fallback chain

The dashboard is designed to load even when a data source is unavailable.

Detection data:
1. SQL Server (`RiskIntelDB`), reading `PurchaseLog` first and then `SurveillanceLog`
2. `data/demo_data.csv`
3. A synthetic 80-row in-memory dataset

District crime context:
1. Live NZ Police data from the data.govt.nz CKAN API
2. Hardcoded 2023 district totals if the API is unavailable or `httr`/`jsonlite` are not installed. Seven districts are confirmed figures from Figure.NZ tables; five are estimates derived from the national total.

### Executive summary panel

The other panels show the data; the Executive Summary panel states the main results in plain language so a reader does not need to interpret the charts to find them.

---

## About the Author

Built by Michael Dang as a capstone project during the Master of Business Analytics at the University of Auckland. Background: audit at EY Vietnam. [LinkedIn](https://linkedin.com/in/michael-dang-964622193)
