# Risk Intelligence Dashboard

> **Production-grade data integration system** | Multi-source risk analytics  
> **Live demo in under 2 minutes** — `git clone` → open `app.R` → Run App

---

## Executive Summary

This is an operational consulting problem solved end-to-end: integrating internal asset tracking data with external risk context to automate decision-making under uncertainty. It demonstrates the analytical DNA required in advisory — database design, API integration, scoring logic, and stakeholder-ready communication.

**Context**: Built as a capstone project during my Master's degree at University of Auckland. Designed to demonstrate the analytical patterns and systems thinking required in consulting environments: multi-source data integration, operational resilience, and stakeholder communication.

---

## The Problem It Solves

Most organisations collect data in **silos**. This project shows what happens when you break them down:

- **Internal state**: Personnel locations, assigned assets, surveillance feeds
- **External context**: Regional crime patterns from government open data
- **Decision point**: Which detections actually require immediate action?

**The gap**: A detection is only "critical" if two things are true simultaneously. Miss either and you flag false positives (operational noise) or miss real threats (operational liability).

**The solution**: A normalised relational database merged with live API context, filtered through a priority scoring engine, surfaced to decision-makers in under 5 seconds.

This is how audit teams in Big 4 firms structure analytical procedures. This project demonstrates you understand the pattern.

---

## What's Built Here

### 1. **Database Architecture** — *Demonstrates relational modelling*

Five normalised tables with enforced referential integrity:

| Table | Purpose | Materiality |
|-------|---------|-------------|
| `Staff` | Personnel directory with risk classification | Controls who can trigger alerts |
| `CurrentAssignments` | Asset allocation ledger | Tracks ownership and responsibility |
| `Assets` | Inventory of monitored items | Links to barcode detection logs |
| `Cameras` | Surveillance hardware registry | GPS-indexed; one change, zero cascade |
| `SurveillanceLog` | Detection events (time-stamped, immutable) | Event stream for pattern analysis |

**Recruiter translation**: This schema solves a real business problem — moving a camera should NOT require batch updates to thousands of historical records. The normalisation pattern here is how you'd structure a financial control log or asset register in an audit client engagement.

### 2. **Multi-Source Data Pipeline** — *Demonstrates integration discipline*

Live NZ Police Crime Data (data.govt.nz CKAN API) → Structured + cached + fallback → Internal SQL Database (5-table normalised schema) → Transform & Score (Risk classification logic) → R Shiny Dashboard (6 reactive panels) → Real-time KPIs, geospatial visualisation, exec summary

**Why this matters**: In advisory, you often have messy internal systems (SQL Server, Access databases, Excel dumps) alongside government datasets. This project shows you can build reliable pipelines that don't break when APIs go down or servers restart.

### 3. **Risk Scoring Logic** — *Demonstrates analytical judgment*

IF (Individual.RiskLevel == "Restricted") AND (Regional_CrimeIndex == "High Risk") THEN Priority = "CRITICAL" ELSE Priority = "ROUTINE"

This looks simple. It's not. In consulting, the hard part is deciding which two factors matter and what threshold to set. This project shows how to cross-reference independent risk dimensions and document business logic for audit trails.

### 4. **Executive Communication Layer** — *Demonstrates stakeholder management*

The Executive Summary panel is the most important part — it's not a dashboard panel, it's a consulting deliverable. It takes raw data and translates it into two paragraphs that a C-suite executive can read in 90 seconds and act on immediately.

---

## Dashboard Panels (What Decision-Makers See)

| Panel | Audience | Time-to-Action |
|-------|----------|---|
| **KPI Bar** | Command centre operators | 3 seconds (critical count jumps out) |
| **Detection Map** | Incident response teams | 10 seconds (visual geospatial context) |
| **Movement Timeline** | Investigators | 20 seconds (pattern identification) |
| **Detection Volume** | Operations leadership | 15 seconds (peak activity windows) |
| **Detection Log** | Audit/compliance teams | 60 seconds (filterable drill-down) |
| **Executive Summary** | C-suite decision-makers | 90 seconds (action-ready narrative) |

Notice the architecture: raw → analytical → executive. This is the pyramid of communication.

---

## Technical Stack & Rationale

| Component | Choice | Why This Choice |
|-----------|--------|---|
| **Database** | SQL Server (T-SQL) | Industry standard in audit |
| **Data API** | CKAN (data.govt.nz) | Public data, realistic integration challenge |
| **Analytics Language** | R (Shiny) | Reproducible analytical workflows |
| **BI Layer** | Leaflet + Shiny | Lightweight, no external dependencies |
| **Fallback Strategy** | CSV + cached API | Resilience design — dashboard never shows blank screen |

These aren't flashy choices. They're reliable, documented, enterprise-grade choices.

---

## How It Demonstrates Consulting Competencies

| Competency | Evidence |
|------------|----------|
| **Problem Structuring** | Identified the gap between internal data and external risk context |
| **Systems Thinking** | Built a pipeline, not a report; designed for repeatability |
| **Technical Architecture** | Normalised database; API resilience; graceful fallbacks |
| **Analytical Rigour** | Scoring logic is documented, testable, and audit-ready |
| **Stakeholder Communication** | Executive Summary translates findings into decisions |
| **Version Control & Documentation** | Repo is clean, README structured for other analysts |

---

## Quick Start (No Setup Required)

The app runs in **demo mode** by default — no SQL Server needed.

```bash
git clone https://github.com/dangminhcuong07-cpu/risk-intelligence-dashboard
cd risk-intelligence-dashboard
Rscript -e "install.packages(c('shiny', 'bslib', 'leaflet', 'DT', 'DBI', 'odbc', 'dplyr', 'ggplot2', 'ckanr'))"
Rscript -e "shiny::runApp('app.R')"
```

Then open your browser to http://localhost:3838

---

## Key Architectural Decisions

### Why Separate Immutable Logs from Master Data?

Early version: GPS coordinates stored directly in the surveillance log.

Problem: Move one camera = update 3,000+ rows. Risk of corruption. Audit trail breaks.

Solution: Separate `Cameras` table. One INSERT to add a camera. Zero historical records touched ever.

**Why this matters**: This is exactly how financial control logs are structured. You never corrupt the transaction record. The audit log is the source of truth. This is the pattern Big 4 auditors require.

### Why Three-Layer Fallback Chain?

Production scenario: 10 minutes before the board demo, the NZ Police API goes down.

Design:
- **Layer 1**: Live SQL + live API (normal operation)
- **Layer 2**: Live SQL + cached API data (API failure)
- **Layer 3**: Fallback CSV + cached data (SQL Server offline)

**Result**: Dashboard never shows a blank screen. That's not over-engineering. That's professionalism.

**Why it matters**: Client systems fail. Your job is to ensure your analytical system doesn't fail when they do. This is resilience design — the thinking that separates junior developers from systems engineers.

### Why the Executive Summary Panel?

The hardest panel to build wasn't the interactive map or the SQL joins. It was translating everything into two paragraphs that a C-suite executive could read in 90 seconds and act on immediately.

Raw data: 47 critical detections across 8 districts, 12 staff members, peak at 14:00.

Insight: Detection spike correlated with high-crime region + restricted-access personnel. Recommend immediate review of access protocols for Districts 2 and 5.

**Why this matters**: Data without narrative is just noise. A consultant's job is to turn data into decisions. This is what separates junior analysts from consultants.

---

## About the Author

Built by Michael Dang as a capstone project during Master of Business Analytics at University of Auckland.

**Background**: Big 4 Audit (EY Vietnam) → Now pursuing Data Systems Design

Currently open to consulting and analytics opportunities with Big 4 firms and finance-dominant organisations in New Zealand. This project demonstrates my 
understanding of how consulting teams operationalise analytical systems.

**Connect**: https://linkedin.com/in/michael-dang-964622193
```

---
