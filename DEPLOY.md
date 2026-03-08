# Deployment Guide — Shinyapps.io

## Prerequisites
- RStudio installed
- R packages installed (see below)
- Free Shinyapps.io account at https://www.shinyapps.io

---

## Step 1 — Create a Shinyapps.io Account

1. Go to https://www.shinyapps.io and sign up (free tier = 5 apps, 25 active hours/month)
2. After login, click your username (top right) → **Tokens**
3. Click **Show** → copy the three-line `rsconnect::setAccountInfo(...)` command — you'll need it in Step 3

---

## Step 2 — Install Required Packages

Run this in RStudio console:

```r
install.packages(c(
  "shiny", "bslib", "bsicons", "leaflet", "DT",
  "DBI", "odbc", "dplyr", "ggplot2",
  "httr", "jsonlite", "scales",
  "rsconnect"
))
```

---

## Step 3 — Connect RStudio to Shinyapps.io

In RStudio console, paste the token command you copied in Step 1:

```r
rsconnect::setAccountInfo(
  name   = "YOUR_ACCOUNT_NAME",
  token  = "YOUR_TOKEN",
  secret = "YOUR_SECRET"
)
```

---

## Step 4 — Prepare Your Project Folder

Make sure your project folder contains exactly these files:

```
risk-intelligence-dashboard/
├── app.R
├── analysis.R
├── generate_demo_data.R
├── data/
│   └── demo_data.csv        ← must exist before deploying
└── schema.sql               ← optional, not used at runtime
```

**Important:** Generate `demo_data.csv` first if it doesn't exist:

```r
setwd("C:/Users/Admin/Desktop/Personal/Personal project/Risk_intelligence_dashboard")
source("generate_demo_data.R")
```

---

## Step 5 — Remove the SQL/ODBC Dependency for Cloud

Shinyapps.io does not have access to your local SQL Server. The app handles this automatically via its fallback chain — but `library(odbc)` will fail on deployment if the ODBC driver isn't available on the server.

Open `app.R` and change the top library block from:

```r
library(DBI)
library(odbc)
```

To a soft-load so missing packages don't crash startup:

```r
DBI_AVAILABLE  <- requireNamespace("DBI",  quietly = TRUE)
ODBC_AVAILABLE <- requireNamespace("odbc", quietly = TRUE)
SQL_AVAILABLE  <- DBI_AVAILABLE && ODBC_AVAILABLE
```

Then wrap the `dbConnect` call (already in a `tryCatch`) to also check `SQL_AVAILABLE`:

```r
con <- if (!SQL_AVAILABLE) NULL else tryCatch({
  DBI::dbConnect(
    odbc::odbc(),
    Driver = "ODBC Driver 17 for SQL Server",
    ...
  )
}, error = function(e) { message("[SQL] Not reachable."); NULL })
```

This means the cloud deployment runs entirely on `demo_data.csv` — all panels work, no SQL errors.

---

## Step 6 — Deploy

In RStudio, set your working directory to the project folder, then run:

```r
setwd("C:/Users/Admin/Desktop/Personal/Personal project/Risk_intelligence_dashboard")

rsconnect::deployApp(
  appDir  = ".",
  appName = "risk-intelligence-dashboard",
  appFiles = c("app.R", "data/demo_data.csv")
)
```

RStudio will open a browser showing deployment progress. Takes ~2–3 minutes.

Your live URL will be:
```
https://YOUR_ACCOUNT_NAME.shinyapps.io/risk-intelligence-dashboard/
```

---

## Step 7 — Test the Live App

Check each panel loads correctly:

- [ ] KPI bar shows numbers (not 0)
- [ ] Detection Map shows pins across multiple NZ cities
- [ ] Movement Timeline shows coloured points
- [ ] Detection Volume shows a bar chart
- [ ] Vehicle Activity shows bars (not "no vehicle detections")
- [ ] Detection Log table loads with all columns including Plate and Out of District
- [ ] Executive Summary shows a written briefing

If any panel fails, check the Shinyapps.io logs:
- Go to shinyapps.io dashboard → your app → **Logs** tab

---

## Step 8 — Update GitHub with the Live URL

In your README.md, add a live demo badge at the top:

```markdown
[![Live Demo](https://img.shields.io/badge/Live%20Demo-Shinyapps.io-blue)](https://YOUR_ACCOUNT.shinyapps.io/risk-intelligence-dashboard/)
```

And update the README intro line to include the URL so recruiters can click it directly from GitHub.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `there is no package called 'odbc'` | Add soft-load as described in Step 5 |
| `demo_data.csv not found` | Run `generate_demo_data.R` locally first, then redeploy with the CSV |
| App loads but panels are blank | Check Logs tab — usually a column name mismatch in the CSV |
| Deployment times out | Free tier limit — wait 1 hour and retry |
| `OutOfDistrict` column error in Detection Log | Ensure you're using the latest `app.R` with `formatStyle("OutOfDistrict", ...)` |
