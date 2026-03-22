# Case Study: Risk Intelligence Dashboard

**Author:** Michael Dang · Master of Business Analytics, University of Auckland  
**Stack:** R · SQL Server · R Shiny · NZ Government CKAN API  
**Repo:** github.com/dangminhcuong07-cpu/risk-intelligence-dashboard

---

## Problem

Security and risk operations teams typically manage two disconnected information streams: internal asset and personnel records held in structured databases, and external event data from government or public sources. Decisions about whether a detection event is routine or critical are made manually, inconsistently, and without a repeatable scoring framework. The result is analyst time spent on low-priority events and genuine risks that surface too late.

---

## Data

| Source | Type | Description |
|---|---|---|
| RiskIntelDB (SQL Server) | Internal | 5 normalised tables: Staff, Assets, CurrentAssignments, Cameras, SurveillanceLog |
| NZ Government CKAN API | External (live) | Open data feeds — refreshed at dashboard load |

The internal database tracks which staff members are assigned to which assets, camera locations, and a running surveillance log of detection events. The external API provides contextual public data that enriches each detection record. The two streams are joined at query time — no manual data preparation required after initial setup.

---

## Methodology

1. **Schema design:** Normalised the operational data into five tables to eliminate redundancy and enable clean multi-table JOINs across staff, assets, assignments, and camera records.
2. **API integration:** Wrote an R function that calls the NZ Government CKAN API on each dashboard load, parses the JSON response, and appends it to the internal query result — ensuring the dashboard always reflects current external data without manual refresh.
3. **Priority scoring engine:** Built a rule-based scoring function in R that evaluates each detection event across multiple factors (asset criticality, staff assignment status, detection frequency, camera zone) and classifies each event as **CRITICAL** or **ROUTINE**. The scoring logic is parameterised — thresholds can be adjusted without rewriting the function.
4. **Dashboard build:** Deployed as a five-panel R Shiny application: Detection Map, Movement Timeline, Detection Volume, Detection Log, and Executive Summary. Each panel is driven by a single reactive data object — changing the date filter or asset selector updates all five panels simultaneously.

---

## Finding

The priority scoring engine revealed that approximately **30% of detection events** flagged under a naive frequency-based approach were reclassified as ROUTINE once asset criticality and assignment status were incorporated. Conversely, a subset of low-frequency detections in high-criticality asset zones were elevated to CRITICAL — events that a frequency-only model would have deprioritised.

This is the same pattern as Moneyball: the obvious signal (volume) was overriding a more predictive one (zone × asset criticality).

---

## Recommendation

For any team managing detection or surveillance data at scale:

- **Do not use frequency alone as a proxy for priority.** Frequency is visible and easy to measure; it is not the same as risk.
- **Fuse internal and external data at query time**, not at export time. Manual data preparation introduces lag and error.
- **Build scoring logic as a parameterised function**, not hardcoded rules. Thresholds shift as operational context changes — the model should adapt without a rewrite.

The dashboard reduces time-to-decision by surfacing only CRITICAL events on the Executive Summary panel, with full drill-down available for any event in the Detection Log.

---

*Full source code, schema, and setup instructions available in this repository.*
