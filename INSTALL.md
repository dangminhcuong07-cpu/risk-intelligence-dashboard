# Installation Guide

This guide is written for non-technical reviewers and hiring managers. You do not need to be an R developer to get the dashboard running.

---

## What You Need

| Requirement | Download |
|---|---|
| R (version 4.0 or later) | https://cran.r-project.org |
| RStudio (recommended) | https://posit.co/download/rstudio-desktop |
| SQL Server or SQL Server Express | https://www.microsoft.com/en-us/sql-server/sql-server-downloads |

**Time to install:** approximately 15–20 minutes if starting from scratch.

---

## Step 1 — Clone the Repository

Open a terminal (or Git Bash on Windows) and run:

```bash
git clone https://github.com/dangminhcuong07-cpu/risk-intelligence-dashboard.git
cd risk-intelligence-dashboard
```

Or download as a ZIP: click the green **Code** button on this page → **Download ZIP** → extract to a folder.

---

## Step 2 — Set Up the Database

1. Open **SQL Server Management Studio** (SSMS) or any SQL Server client.
2. Connect to your local SQL Server instance.
3. Open the file `schema.sql` from this repository.
4. Run the full script — this creates the **RiskIntelDB** database and all five tables (Staff, Assets, CurrentAssignments, Cameras, SurveillanceLog).
5. Open `data/demo_data.csv` — this file contains sample records. Import it using SSMS's import wizard or run the provided insert statements at the bottom of `schema.sql`.

---

## Step 3 — Install R Packages

Open RStudio, then run this in the console:

```r
install.packages(c(
  "shiny",
  "shinydashboard",
  "DBI",
  "odbc",
  "dplyr",
  "ggplot2",
  "leaflet",
  "httr",
  "jsonlite",
  "lubridate"
))
```

This will take 2–5 minutes. You only need to do this once.

---

## Step 4 — Configure the Database Connection

Open `app.R` in RStudio. Near the top of the file, find the connection block:

```r
con <- dbConnect(
  odbc::odbc(),
  Driver = "ODBC Driver 17 for SQL Server",
  Server = "YOUR_SERVER_NAME",
  Database = "RiskIntelDB",
  Trusted_Connection = "Yes"
)
```

Replace `YOUR_SERVER_NAME` with your local SQL Server instance name. If you installed SQL Server Express, this is typically `localhost\SQLEXPRESS`.

---

## Step 5 — Run the Dashboard

In RStudio, open `app.R` and click **Run App** (top right of the editor), or run:

```r
shiny::runApp()
```

The dashboard will open in your browser. It connects to your local SQL Server database and calls the NZ Government CKAN API live on load.

---

## What Each Panel Does

| Panel | Description |
|---|---|
| **Detection Map** | Geographic view of camera locations and detection events |
| **Movement Timeline** | Time-series of detections by asset zone |
| **Detection Volume** | Aggregated counts by date and classification |
| **Detection Log** | Full filterable table of all detection records |
| **Executive Summary** | CRITICAL events only, with priority scores and recommended actions |

---

## Troubleshooting

**"Could not connect to SQL Server"** — Check that SQL Server is running. In Windows, open Services and confirm SQL Server (MSSQLSERVER or SQLEXPRESS) is started.

**"Package not found"** — Re-run the `install.packages()` command in Step 3.

**"API call failed"** — Check your internet connection. The CKAN API call requires outbound internet access. The dashboard will load with internal data only if the API is unreachable.

---

## Questions

Contact: dangminhcuong07@gmail.com  
LinkedIn: linkedin.com/in/cuong-dang
