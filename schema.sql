-- ==============================================================================
-- RiskIntelDB — Database Schema & Seed Data
-- Author: Michael Dang | Master of Business Analytics, University of Auckland
--
-- Description: Normalised relational schema for the Risk Intelligence Dashboard.
--              Five tables track staff, assets, camera infrastructure,
--              assignments, and detection scan logs.
--
-- BUG FIXES vs previous version:
--   - Cameras table expanded: was 3 locations (Auckland, Wellington, Canterbury)
--     now 7 locations matching the app's synthetic data districts
--   - Staff seed data expanded from 3 to 7 records to generate richer demo data
--   - Assets and SurveillanceLog seed data expanded accordingly
--   - CameraLocation names now match actual NZ Police district names used in
--     the app's DISTRICT_COORDS and NZ_POLICE_FALLBACK lookups
--
-- HOW TO USE:
--   First run  → Execute SECTIONS 1–4 in full (creates + seeds the database)
--   Later runs → Execute SECTION 5 ONLY to refresh timestamps without re-seeding
-- ==============================================================================

-- ==============================================================================
-- SECTION 1: SAFE RESET — drop FK constraints first, then tables
-- ==============================================================================
-- BUG FIX: Added WHERE clause to scope FK drop to THIS DATABASE ONLY.
-- Without it, the query hits sys.foreign_keys which is instance-wide and
-- drops FK constraints from every database on the SQL Server instance.
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += 'ALTER TABLE '
    + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
    + '.' + QUOTENAME(OBJECT_NAME(parent_object_id))
    + ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.foreign_keys
WHERE OBJECT_SCHEMA_NAME(parent_object_id) IN (
    SELECT s.name FROM sys.schemas s
);
EXEC sp_executesql @sql;
GO

IF OBJECT_ID('CurrentAssignments', 'U') IS NOT NULL DROP TABLE CurrentAssignments;
IF OBJECT_ID('SurveillanceLog',    'U') IS NOT NULL DROP TABLE SurveillanceLog;
IF OBJECT_ID('Cameras',            'U') IS NOT NULL DROP TABLE Cameras;
IF OBJECT_ID('Assets',             'U') IS NOT NULL DROP TABLE Assets;
IF OBJECT_ID('Staff',              'U') IS NOT NULL DROP TABLE Staff;
GO

-- ==============================================================================
-- SECTION 2: CREATE TABLES
-- ==============================================================================

-- Individuals in system
CREATE TABLE Staff (
    StaffID   INT          PRIMARY KEY,
    FullName  VARCHAR(100) NOT NULL,
    RiskLevel VARCHAR(50)  NOT NULL  -- 'Restricted' | 'Moderate' | 'Low' | 'Unknown'
);

-- Physical assets (access cards, devices)
CREATE TABLE Assets (
    AssetID       INT         PRIMARY KEY,
    BarcodeString VARCHAR(50) UNIQUE NOT NULL,
    DeviceType    VARCHAR(50)
);

-- Junction table: which staff member holds which asset
CREATE TABLE CurrentAssignments (
    AssignmentID INT PRIMARY KEY,
    AssetID      INT NOT NULL,
    StaffID      INT NOT NULL,
    FOREIGN KEY (AssetID) REFERENCES Assets(AssetID),
    FOREIGN KEY (StaffID) REFERENCES Staff(StaffID)
);

-- Surveillance camera registry with GPS coordinates (Option B architecture)
-- CameraLocation = NZ Police district name (used to join NZ Police API context)
-- CameraLat/CameraLng = real GPS pin on map (two different jobs, two columns)
CREATE TABLE Cameras (
    CameraID       INT           PRIMARY KEY,
    CameraName     VARCHAR(100),
    CameraLocation VARCHAR(100),  -- Must match NZ Police district names exactly
    CameraLat      DECIMAL(9,6),  -- WGS84 latitude
    CameraLng      DECIMAL(9,6)   -- WGS84 longitude
);

-- Every detection scan event
CREATE TABLE SurveillanceLog (
    LogID          INT         PRIMARY KEY,
    BarcodeScanned VARCHAR(50) NOT NULL,
    ScanTime       DATETIME    NOT NULL,
    CameraID       INT         NOT NULL,
    FOREIGN KEY (CameraID) REFERENCES Cameras(CameraID)
);
GO

-- ==============================================================================
-- SECTION 3: SEED DATA
--
-- Staff RiskLevels match the app's STAFF_PROFILES lookup exactly:
--   'Restricted' | 'Moderate' | 'Low' | 'Unknown'
--
-- CameraLocation values match the app's DISTRICT_COORDS and NZ_POLICE_FALLBACK:
--   These are the 12 actual NZ Police district names.
--   Using sub-area names like 'Hawke's Bay' or 'Southland' would break the join.
--
-- NOTE: Timestamps use GETDATE() at insert time.
--       If the dashboard shows 0 rows later, run SECTION 5 to refresh them.
-- ==============================================================================

-- 7 staff covering a range of risk levels
INSERT INTO Staff VALUES (1, 'Alex Turner',  'Restricted');
INSERT INTO Staff VALUES (2, 'Sarah Kim',    'Restricted');
INSERT INTO Staff VALUES (3, 'James Patel',  'Restricted');
INSERT INTO Staff VALUES (4, 'Michael Chen', 'Moderate');
INSERT INTO Staff VALUES (5, 'David Nguyen', 'Moderate');
INSERT INTO Staff VALUES (6, 'Nina Sharma',  'Low');
INSERT INTO Staff VALUES (7, 'Tom Bradley',  'Low');
GO

INSERT INTO Assets VALUES (1, 'NZ-1234', 'Access Card');
INSERT INTO Assets VALUES (2, 'NZ-5678', 'Access Card');
INSERT INTO Assets VALUES (3, 'NZ-9999', 'Access Card');
INSERT INTO Assets VALUES (4, 'NZ-4321', 'Access Card');
INSERT INTO Assets VALUES (5, 'NZ-8765', 'Access Card');
INSERT INTO Assets VALUES (6, 'NZ-2468', 'Access Card');
INSERT INTO Assets VALUES (7, 'NZ-1357', 'Access Card');
GO

-- Each staff member holds one asset
INSERT INTO CurrentAssignments VALUES (1, 1, 1);
INSERT INTO CurrentAssignments VALUES (2, 2, 2);
INSERT INTO CurrentAssignments VALUES (3, 3, 3);
INSERT INTO CurrentAssignments VALUES (4, 4, 4);
INSERT INTO CurrentAssignments VALUES (5, 5, 5);
INSERT INTO CurrentAssignments VALUES (6, 6, 6);
INSERT INTO CurrentAssignments VALUES (7, 7, 7);
GO

-- 7 cameras across key NZ Police districts
-- BUG FIX: Was only 3 cameras (Auckland, Wellington, Canterbury).
-- App synthetic data generates detections for 7 districts — schema now matches.
-- GPS coordinates source: Google Maps / NZ Police district headquarters.
INSERT INTO Cameras VALUES (1, 'CAM-AKL-01', 'Auckland City',    -36.850900, 174.764500);
INSERT INTO Cameras VALUES (2, 'CAM-WLG-01', 'Wellington',       -41.286500, 174.776200);
INSERT INTO Cameras VALUES (3, 'CAM-CHC-01', 'Canterbury',       -43.532100, 172.636200);
INSERT INTO Cameras VALUES (4, 'CAM-CMK-01', 'Counties Manukau', -37.008200, 174.899600);
INSERT INTO Cameras VALUES (5, 'CAM-WKT-01', 'Waikato',          -37.787000, 175.279300);
INSERT INTO Cameras VALUES (6, 'CAM-BOP-01', 'Bay of Plenty',    -37.687800, 176.165100);
INSERT INTO Cameras VALUES (7, 'CAM-NTH-01', 'Northland',        -35.727500, 174.322800);
GO

-- Detection events spanning the past 8 hours across all 7 camera locations
INSERT INTO SurveillanceLog VALUES ( 1, 'NZ-1234', GETDATE(),                        1);
INSERT INTO SurveillanceLog VALUES ( 2, 'NZ-5678', DATEADD(hour,  -1, GETDATE()),    2);
INSERT INTO SurveillanceLog VALUES ( 3, 'NZ-9999', DATEADD(hour,  -2, GETDATE()),    3);
INSERT INTO SurveillanceLog VALUES ( 4, 'NZ-4321', DATEADD(hour,  -3, GETDATE()),    4);
INSERT INTO SurveillanceLog VALUES ( 5, 'NZ-8765', DATEADD(hour,  -4, GETDATE()),    5);
INSERT INTO SurveillanceLog VALUES ( 6, 'NZ-2468', DATEADD(hour,  -5, GETDATE()),    6);
INSERT INTO SurveillanceLog VALUES ( 7, 'NZ-1357', DATEADD(hour,  -6, GETDATE()),    7);
INSERT INTO SurveillanceLog VALUES ( 8, 'NZ-1234', DATEADD(hour,  -7, GETDATE()),    4);
INSERT INTO SurveillanceLog VALUES ( 9, 'NZ-5678', DATEADD(hour,  -8, GETDATE()),    1);
INSERT INTO SurveillanceLog VALUES (10, 'NZ-9999', DATEADD(minute,-30, GETDATE()),   2);
INSERT INTO SurveillanceLog VALUES (11, 'NZ-4321', DATEADD(minute,-90, GETDATE()),   3);
INSERT INTO SurveillanceLog VALUES (12, 'NZ-8765', DATEADD(minute,-45, GETDATE()),   5);
GO

-- ==============================================================================
-- SECTION 4: VERIFY — confirms JOINs work and all columns are present
--            Expected: 12 rows with FullName, RiskLevel, CameraLocation,
--                      CameraLat, CameraLng all populated
-- ==============================================================================
SELECT
    L.LogID,
    L.ScanTime,
    C.CameraName,
    C.CameraLocation,
    C.CameraLat,
    C.CameraLng,
    S.FullName,
    S.RiskLevel
FROM SurveillanceLog    L
JOIN Cameras            C  ON L.CameraID       = C.CameraID
JOIN Assets             A  ON L.BarcodeScanned = A.BarcodeString
JOIN CurrentAssignments CA ON A.AssetID        = CA.AssetID
JOIN Staff              S  ON CA.StaffID       = S.StaffID
ORDER BY L.ScanTime DESC;
GO

-- ==============================================================================
-- SECTION 5: REFRESH TIMESTAMPS (run this block alone, any time)
--
-- Run this in SSMS whenever the dashboard shows stale or missing data.
-- Highlight just this section and press F5.
-- The WHERE clause uses LogID so it is safe to run multiple times.
-- ==============================================================================
UPDATE SurveillanceLog SET ScanTime = GETDATE()                        WHERE LogID = 1;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -1, GETDATE())   WHERE LogID = 2;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -2, GETDATE())   WHERE LogID = 3;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -3, GETDATE())   WHERE LogID = 4;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -4, GETDATE())   WHERE LogID = 5;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -5, GETDATE())   WHERE LogID = 6;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -6, GETDATE())   WHERE LogID = 7;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -7, GETDATE())   WHERE LogID = 8;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -8, GETDATE())   WHERE LogID = 9;
UPDATE SurveillanceLog SET ScanTime = DATEADD(minute, -30, GETDATE())  WHERE LogID = 10;
UPDATE SurveillanceLog SET ScanTime = DATEADD(minute, -90, GETDATE())  WHERE LogID = 11;
UPDATE SurveillanceLog SET ScanTime = DATEADD(minute, -45, GETDATE())  WHERE LogID = 12;
GO
