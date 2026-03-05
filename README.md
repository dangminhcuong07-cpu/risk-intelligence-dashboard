# Risk Intelligence Dashboard

> 🟢 **Runs in demo mode — no SQL Server required.**  
> Clone the repo, open `app.R`, click Run App.

An end-to-end analytics solution that fuses a **normalised SQL database** with a **live NZ Government open data API** to deliver automated risk prioritisation through an interactive R Shiny dashboard.

Built to replicate the kind of multi-source data integration problem common in operational consulting — where decisions must be made by combining internal records with external public data in real time.

---

## What It Does

The dashboard ingests two data streams:

1. **Internal risk database** — a normalised SQL Server database (`RiskIntelDB`) tracking individuals, assigned assets, camera locations, and scan events across five related tables
2. **NZ Police regional crime statistics** — pulled live from [data.govt.nz](https://catalogue.data.govt.nz) via the CKAN API

These are merged and passed through a **priority scoring engine** that classifies each detection as `CRITICAL` or `ROUTINE` based on two intersecting factors:
- Individual risk classification (Restricted / Moderate)
- Regional crime index threshold (High Risk / Moderate)

The result is surfaced across five dashboard panels, from a live detection map through to an auto-generated executive briefing.

---

## Dashboard Panels

| Panel | Description |
|---|---|
| **KPI Bar** | Summary tiles — total detections, critical alerts, individuals tracked, high-risk regions |
| **Detection Map** | Leaflet interactive map with colour-coded markers and popup detail |
| **Movement Timeline** | Individual detection history plotted by time and location |
| **Detection Volume** | Hourly detection volume stacked by priority — identifies peak activity windows |
| **Detection Log** | Filterable data table with conditional formatting by priority |
| **Executive Summary** | Auto-generated written briefing synthesising all findings into a decision-ready report |

![Tactical Map](data/map.png)
![Evidence Log](data/summary.png)

---

![Tactical Map](data/screenshots/map.png)
![Executive Summary](data/screenshots/summary.png)


## Architecture

```
data.govt.nz API
      │
      ▼
get_nz_police_context()          ← External API with graceful fallback
      │
      ▼
get_app_data()  ──── SQL (live) ─────────────────────────────────────┐
      │                                                               │
      └──── CSV fallback (data/demo_data.csv)                        │
                                                                      │
                              Priority Scoring Engine                 │
              (RiskLevel == "Restricted" & Regional_Status == "High Risk")
                                      │
                                      ▼
                            Shiny Dashboard (app.R)
                    ┌──────────┬──────────┬──────────┐
                    │   Map    │ Timeline │  Report  │
                    └──────────┴──────────┴──────────┘
```

### Database Schema (5 normalised tables)

```
Staff ──────────── CurrentAssignments ──── Assets
                                              │
                                         BarcodeString
                                              │
SurveillanceLog ── CameraID ──────────── Cameras
```

---

## Run It (No SQL Needed)

The app runs in **demo mode** automatically if SQL Server is not available. All five panels are fully functional using `data/demo_data.csv`.

```r
# 1. Install dependencies
install.packages(c("shiny", "bslib", "leaflet", "DT", "DBI",
                   "odbc", "dplyr", "ggplot2", "ckanr"))

# 2. Clone the repo
# git clone https://github.com/dangminhcuong07-cpu/risk-intelligence-dashboard

# 3. Open app.R in RStudio and click Run App
#    — or from the console:
shiny::runApp("app.R")
```

---

## Run With Live SQL (Optional)

If you have SQL Server Express installed locally:

```
Server:   localhost\SQLEXPRESS
Database: RiskIntelDB (create this first)
Auth:     Windows Authentication
```

Then run `schema.sql` in SSMS or Azure Data Studio to build and seed the database. The app will automatically detect the connection and switch from demo to live mode.

---

## File Structure

```
risk-intelligence-dashboard/
│
├── app.R                   # Shiny dashboard (UI + server)
├── analysis.R              # Standalone investigation script
├── schema.sql              # SQL Server schema + seed data
│
├── data/
│   └── demo_data.csv       # Portfolio fallback — no SQL needed
│
├── .gitignore
└── README.md
```

---

## Skills Demonstrated

| Skill | Where |
|---|---|
| Relational database design | `schema.sql` — 5 normalised tables, FK constraints, safe migration pattern |
| Multi-table SQL JOINs | `analysis.R`, `app.R` — 5-way JOIN across the full schema |
| External API integration | `get_nz_police_context()` — live CKAN API with structured fallback |
| Data pipeline design | Two-source ingestion → merge → transformation → output |
| Risk scoring / business logic | Priority engine cross-referencing two independent risk dimensions |
| R Shiny dashboard development | Reactive UI, filter controls, KPI boxes, multi-panel layout |
| Geospatial visualisation | Leaflet map with GPS coordinates from the database |
| Data storytelling | Executive Summary panel translating data into a decision-ready briefing |
| Graceful error handling | API and SQL fallbacks ensure the app never breaks |
| Version control & documentation | Commented code, structured repo, recruiter-readable README |

---

## Why This Project

Every consulting engagement eventually becomes a data integration problem. This project demonstrates the ability to:

- Identify what data matters (internal records + external context)
- Build infrastructure to combine them reliably
- Apply a scoring model to prioritise management attention
- Communicate findings at two levels — raw data and executive summary

Those four steps map directly to how Big 4 advisory teams structure analytical deliverables for clients.

---
## Roadmap

- **Anomaly detection layer** — replace binary CRITICAL/ROUTINE 
  with a continuous risk probability score using historical 
  scan pattern modelling
- **Automated PDF briefing** — rmarkdown export of the 
  Executive Summary panel for distribution to non-technical 
  stakeholders
- **Shinyapps.io deployment** — public URL for live demo 
  without local setup
  
## Author

**Michael Dang**  
Master of Business Analytics — University of Auckland  
[linkedin.com/in/michael-dang-964622193](https://linkedin.com/in/michael-dang-964622193)
