-- ==============================================================================
-- ForensicDB — Database Schema & Seed Data
-- Author: Michael Dang
--
-- Description: Normalised relational schema for the Risk Intelligence Dashboard.
--              Five tables track staff, assets, camera infrastructure,
--              assignments, and surveillance scan logs.
--
-- HOW TO USE:
--   First run  → Execute SECTIONS 1–4 in full (creates + seeds the database)
--   Later runs → Execute SECTION 5 ONLY to refresh timestamps without re-seeding
-- ==============================================================================

-- ==============================================================================
-- SECTION 1: SAFE RESET — drop FK constraints first, then tables
-- ==============================================================================
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += 'ALTER TABLE '
    + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))
    + '.' + QUOTENAME(OBJECT_NAME(parent_object_id))
    + ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
FROM sys.foreign_keys;
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

-- Individuals being monitored
CREATE TABLE Staff (
    StaffID   INT          PRIMARY KEY,
    FullName  VARCHAR(100) NOT NULL,
    RiskLevel VARCHAR(50)  NOT NULL  -- 'Restricted' | 'Moderate'
);

-- Physical assets assigned to staff (e.g. access cards, devices)
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

-- Physical surveillance camera registry with GPS coordinates
CREATE TABLE Cameras (
    CameraID       INT           PRIMARY KEY,
    CameraName     VARCHAR(100),
    CameraLocation VARCHAR(100),
    CameraLat      DECIMAL(9,6),   -- WGS84 latitude
    CameraLng      DECIMAL(9,6)    -- WGS84 longitude
);

-- Every asset scan event detected by a camera
CREATE TABLE SurveillanceLog (
    LogID          INT         PRIMARY KEY,
    BarcodeScanned VARCHAR(50) NOT NULL,
    ScanTime       DATETIME    NOT NULL,
    CameraID       INT         NOT NULL,
    FOREIGN KEY (CameraID) REFERENCES Cameras(CameraID)
);
GO

-- ==============================================================================
-- SECTION 3: SEED DATA — NZ locations
-- NOTE: Timestamps are set to GETDATE() at insert time.
--       If the dashboard later shows 0 rows, run SECTION 5 to refresh them.
-- ==============================================================================

INSERT INTO Staff VALUES (1, 'Alex Turner',  'Restricted');
INSERT INTO Staff VALUES (2, 'Sarah Kim',    'Moderate');
INSERT INTO Staff VALUES (3, 'James Patel',  'Restricted');

INSERT INTO Assets VALUES (1, 'NZ-1234', 'Access Card');
INSERT INTO Assets VALUES (2, 'NZ-5678', 'Access Card');
INSERT INTO Assets VALUES (3, 'NZ-9999', 'Access Card');

-- Junction: Asset 1→Staff 1, Asset 2→Staff 2, Asset 3→Staff 3
INSERT INTO CurrentAssignments VALUES (1, 1, 1);
INSERT INTO CurrentAssignments VALUES (2, 2, 2);
INSERT INTO CurrentAssignments VALUES (3, 3, 3);

-- GPS coordinates: Auckland, Wellington, Canterbury
INSERT INTO Cameras VALUES (1, 'CAM-AKL-01', 'Auckland City', -36.850900, 174.764500);
INSERT INTO Cameras VALUES (2, 'CAM-WLG-01', 'Wellington',    -41.286500, 174.776200);
INSERT INTO Cameras VALUES (3, 'CAM-CHC-01', 'Canterbury',    -43.532100, 172.636200);

-- Detection events spanning the past 6 hours
INSERT INTO SurveillanceLog VALUES (1, 'NZ-1234', GETDATE(),                       1);
INSERT INTO SurveillanceLog VALUES (2, 'NZ-5678', DATEADD(hour,   -2, GETDATE()),  2);
INSERT INTO SurveillanceLog VALUES (3, 'NZ-9999', DATEADD(hour,   -4, GETDATE()),  3);
INSERT INTO SurveillanceLog VALUES (4, 'NZ-1234', DATEADD(hour,   -6, GETDATE()),  3);
INSERT INTO SurveillanceLog VALUES (5, 'NZ-9999', DATEADD(minute,-30, GETDATE()),  1);
GO

-- ==============================================================================
-- SECTION 4: VERIFY — confirms all JOINs are working correctly
--            Expected: 5 rows with FullName, RiskLevel, CameraLocation populated
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
JOIN Assets             A  ON L.BarcodeScanned  = A.BarcodeString
JOIN CurrentAssignments CA ON A.AssetID         = CA.AssetID
JOIN Staff              S  ON CA.StaffID        = S.StaffID
ORDER BY L.ScanTime DESC;
GO

-- ==============================================================================
-- SECTION 5: REFRESH TIMESTAMPS (run this block alone, any time)
--
-- BUG FIX 5: Separated from the INSERT block above so it is clearly a
-- standalone maintenance operation — not a duplicate of the seed inserts.
--
-- Run this in SSMS whenever the dashboard shows stale or missing data.
-- Highlight just this section and press F5.
-- ==============================================================================
UPDATE SurveillanceLog SET ScanTime = GETDATE()                      WHERE LogID = 1;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -2, GETDATE()) WHERE LogID = 2;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -4, GETDATE()) WHERE LogID = 3;
UPDATE SurveillanceLog SET ScanTime = DATEADD(hour,   -6, GETDATE()) WHERE LogID = 4;
UPDATE SurveillanceLog SET ScanTime = DATEADD(minute,-30, GETDATE()) WHERE LogID = 5;
GO
