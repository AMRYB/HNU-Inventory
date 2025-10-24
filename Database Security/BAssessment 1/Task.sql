-- SETUP: Create Database & Employee Table
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'mohanad')
    CREATE DATABASE mohanad
GO
USE mohanad
GO
-- Drop existing objects
IF OBJECT_ID('Employee', 'U') IS NOT NULL DROP TABLE Employee;
IF OBJECT_ID('PublicNames', 'U') IS NOT NULL DROP TABLE PublicNames;
IF OBJECT_ID('PublicSalary', 'U') IS NOT NULL DROP TABLE PublicSalary;
IF OBJECT_ID('AdminMap', 'U') IS NOT NULL DROP TABLE AdminMap;
IF OBJECT_ID('Departments', 'U') IS NOT NULL DROP TABLE Departments;

IF OBJECT_ID('vSafeTable', 'V') IS NOT NULL DROP VIEW vSafeTable;
IF OBJECT_ID('vAttackTable', 'V') IS NOT NULL DROP VIEW vAttackTable;
IF OBJECT_ID('vPublicWithDept', 'V') IS NOT NULL DROP VIEW vPublicWithDept;
IF OBJECT_ID('vPublicNames', 'V') IS NOT NULL DROP VIEW vPublicNames;
IF OBJECT_ID('vPublicSalaries', 'V') IS NOT NULL DROP VIEW vPublicSalaries;
IF OBJECT_ID('vAttackSalary', 'V') IS NOT NULL DROP VIEW vAttackSalary;
IF OBJECT_ID('vAvgAll', 'V') IS NOT NULL DROP VIEW vAvgAll;
IF OBJECT_ID('vAvgWithoutTarget', 'V') IS NOT NULL DROP VIEW vAvgWithoutTarget;

-- Create Employee Table
CREATE TABLE Employee (
    EmpId INT PRIMARY KEY,
    Full_name VARCHAR(50),
    Salary INT
);
INSERT INTO Employee VALUES 
(1, 'Ali', 120000), (2, 'Asser', 110000), (3, 'Mona', 100000),
(4, 'Fatma', 90000), (5, 'Gehad', 80000), (6, 'Ahmed', 70000);
GO
-- PART 1: DAC Implementation
-- 1. Create Logins
IF SUSER_ID('user_public') IS NULL
    CREATE LOGIN user_public WITH PASSWORD = 'UserStr0ng#1234', DEFAULT_DATABASE = mohanad;
IF SUSER_ID('user_admin') IS NULL
    CREATE LOGIN user_admin WITH PASSWORD = 'AdminStr0ng#1234', DEFAULT_DATABASE = mohanad;

-- 2. Create Database Users
IF USER_ID('general') IS NULL
    CREATE USER general FOR LOGIN user_public;
IF USER_ID('admin1') IS NULL
    CREATE USER admin1 FOR LOGIN user_admin;

-- 3. Create Roles
IF DATABASE_PRINCIPAL_ID('public_role') IS NULL CREATE ROLE public_role;
IF DATABASE_PRINCIPAL_ID('admin_role') IS NULL CREATE ROLE admin_role;

-- 4. Assign Users to Roles
ALTER ROLE public_role ADD MEMBER general;
ALTER ROLE admin_role ADD MEMBER admin1;

-- Grant full access to admin_role
ALTER ROLE db_owner ADD MEMBER admin_role;

-- Create Safe View (anonymized: no salary)
CREATE VIEW vSafeTable AS
SELECT EmpId, Full_name FROM Employee;

-- Grant limited access to public_role
GRANT SELECT ON vSafeTable TO public_role;

-- 5. Test Access
PRINT 'Testing DAC Access...'

EXEC AS USER = 'general';
    SELECT 'Public User' AS UserType, EmpId, Full_name FROM vSafeTable;  -- Should work
    SELECT * FROM Employee;  -- Should fail
REVERT;

EXEC AS USER = 'admin1';
    SELECT 'Admin User' AS UserType, * FROM Employee;  -- Should work
REVERT;

-- 6. Indirect Access Attack via View + PUBLIC Table
PRINT 'Creating Indirect Access Attack...'

-- Public Table
CREATE TABLE Departments (
    EmpId INT,
    DeptName VARCHAR(50)
);
INSERT INTO Departments VALUES (1, 'IT'), (2, 'HR'), (3, 'Finance');

-- View that leaks salary via join
CREATE VIEW vPublicWithDept AS
SELECT e.EmpId, e.Full_name, e.Salary, d.DeptName
FROM Employee e
INNER JOIN Departments d ON e.EmpId = d.EmpId;

GRANT SELECT ON vPublicWithDept TO public_role;

-- Attack Demo
EXEC AS USER = 'general';
    SELECT * FROM vPublicWithDept;  -- Salary leaked!
REVERT;

-- Fix: Revoke access
REVOKE SELECT ON vPublicWithDept FROM public_role;
DROP VIEW vPublicWithDept;
PRINT 'Indirect Access Fixed.'
GO
-- PART 2: RBAC Implementation (CORRECTED - INSERT FAILS AFTER REVOKE)
-- 1. Create Roles
IF DATABASE_PRINCIPAL_ID('read_onlyX') IS NULL CREATE ROLE read_onlyX;
IF DATABASE_PRINCIPAL_ID('insert_onlyX') IS NULL CREATE ROLE insert_onlyX;
IF DATABASE_PRINCIPAL_ID('power_user') IS NULL CREATE ROLE power_user;

-- 2. Clean all memberships
ALTER ROLE read_onlyX DROP MEMBER general;
ALTER ROLE insert_onlyX DROP MEMBER general;
ALTER ROLE power_user DROP MEMBER general;

ALTER ROLE read_onlyX DROP MEMBER power_user;
ALTER ROLE insert_onlyX DROP MEMBER power_user;

-- 3. Grant permissions to base roles
GRANT SELECT ON vSafeTable TO read_onlyX;
GRANT INSERT ON Employee TO insert_onlyX;

-- 4. Build Hierarchy: power_user inherits from both
ALTER ROLE read_onlyX ADD MEMBER power_user;
ALTER ROLE insert_onlyX ADD MEMBER power_user;

-- 5. Add general ONLY to power_user (NOT to base roles)
ALTER ROLE power_user ADD MEMBER general;

-- Test: power_user should have both SELECT and INSERT
PRINT 'Testing power_user: Should have SELECT + INSERT'
EXEC AS USER = 'general';
    SELECT TOP 1 'READ OK' AS Test, * FROM vSafeTable;
    INSERT INTO Employee VALUES (100, 'Power_Insert', 99999);  -- نجح
REVERT;

-- Revoke insert_onlyX from power_user
PRINT 'Revoking insert_onlyX from power_user...'
ALTER ROLE insert_onlyX DROP MEMBER power_user;

-- Test again: INSERT should FAIL
PRINT 'Testing after REVOKE: INSERT should FAIL'
EXEC AS USER = 'general';
    SELECT TOP 1 'READ STILL OK' AS Test, * FROM vSafeTable;  -- success
    INSERT INTO Employee VALUES (101, 'Fail', 0); -- faild
REVERT;

-- Clean up test data
DELETE FROM Employee WHERE EmpId >= 100;
GO

-- PART 3: Inference Attack Simulation 
-- Create Public Tables
IF OBJECT_ID('PublicNames', 'U') IS NOT NULL DROP TABLE PublicNames;
IF OBJECT_ID('PublicSalary', 'U') IS NOT NULL DROP TABLE PublicSalary;

CREATE TABLE PublicNames (
    EmpId INT PRIMARY KEY,
    EmpName VARCHAR(50)
);
INSERT INTO PublicNames SELECT EmpId, Full_name FROM Employee;

CREATE TABLE PublicSalary (
    SalId INT PRIMARY KEY,
    Salary INT
);
INSERT INTO PublicSalary SELECT EmpId, Salary FROM Employee;

-- Admin-only mapping
IF OBJECT_ID('AdminMap', 'U') IS NOT NULL DROP TABLE AdminMap;
CREATE TABLE AdminMap (
    EmpId INT, EmpName VARCHAR(50), SalId INT, Salary INT
);
INSERT INTO AdminMap 
SELECT n.EmpId, n.EmpName, s.SalId, s.Salary 
FROM PublicNames n JOIN PublicSalary s ON n.EmpId = s.SalId;

IF OBJECT_ID('vAttackSalary', 'V') IS NOT NULL DROP VIEW vAttackSalary;
CREATE VIEW vAttackSalary AS
SELECT n.EmpId, n.EmpName, s.Salary
FROM PublicNames n
JOIN PublicSalary s ON n.EmpId = s.SalId;
-- Grant access
GRANT SELECT ON vAttackSalary TO public_role;

-- INFERENCE ATTACK: User orders the results to align names & salaries
PRINT 'Malicious User Executes:'
EXEC AS USER = 'general';
    SELECT EmpName, Salary
    FROM vAttackSalary
    ORDER BY EmpId;  
REVERT;
GO
-- PART 4: Inference Control by Randomization
-- Add random PublicID
ALTER TABLE PublicNames ADD PublicID UNIQUEIDENTIFIER NULL;
UPDATE PublicNames SET PublicID = NEWID() WHERE PublicID IS NULL;
ALTER TABLE PublicNames ALTER COLUMN PublicID UNIQUEIDENTIFIER NOT NULL;
CREATE UNIQUE INDEX UQ_PublicNames_PublicID ON PublicNames(PublicID);

ALTER TABLE PublicSalary ADD PublicID UNIQUEIDENTIFIER NULL;
UPDATE PublicSalary SET PublicID = NEWID() WHERE PublicID IS NULL;
ALTER TABLE PublicSalary ALTER COLUMN PublicID UNIQUEIDENTIFIER NOT NULL;
CREATE UNIQUE INDEX UQ_PublicSalary_PublicID ON PublicSalary(PublicID);

-- Public Views with random IDs
CREATE OR ALTER VIEW vPublicNames AS
SELECT PublicID, EmpName FROM PublicNames;
CREATE OR ALTER VIEW vPublicSalaries AS
SELECT PublicID, Salary FROM PublicSalary;
GRANT SELECT ON vPublicNames TO public_role;
GRANT SELECT ON vPublicSalaries TO public_role;
-- Restrict direct access
REVOKE SELECT ON Employee FROM public_role;
REVOKE SELECT ON PublicNames FROM public_role;
REVOKE SELECT ON PublicSalary FROM public_role;
DENY SELECT ON AdminMap TO public_role;
DENY CREATE VIEW TO public_role;

-- Drop attack view
IF OBJECT_ID('vAttackSalary') IS NOT NULL DROP VIEW vAttackSalary;

-- Test: Inference should fail
EXEC AS USER = 'general';
    -- Cannot join on PublicID → no correlation
    SELECT TOP 1 n.EmpName, s.Salary 
    FROM vPublicNames n 
    JOIN vPublicSalaries s ON n.PublicID = s.PublicID;
REVERT;
PRINT 'Inference Blocked via Randomization.'
GO
-- PART 5: Functional Dependency Inference (Practical Implementation)
-- Begin Part 5 execution
-- Step 1: Create table to demonstrate functional dependencies
CREATE TABLE EmployeeFD (
    EmpID INT,
    Dept VARCHAR(50),
    Title VARCHAR(50),
    Grade VARCHAR(10),
    Salary INT  
);
-- Step 2: Insert sample data respecting the given FDs
-- FD1: EmpID → Dept (same Dept for same EmpID)
-- FD2: Title → Grade (same Grade for same Title)
-- FD3: Dept, Grade → Salary (modified to reflect sensitive data)
INSERT INTO EmployeeFD VALUES
(1, 'IT', 'Engineer', 'A', 120000),    
(2, 'HR', 'Manager', 'B', 110000),     
(3, 'IT', 'Engineer', 'A', 100000),   
(4, 'HR', 'Manager', 'B', 90000);      
-- Step 3: Compute closure Q⁺ of {Dept, Title} practically
PRINT 'Step 1: Compute Q⁺ of {Dept, Title}';
-- Start with {Dept, Title} and derive Grade and Salary
SELECT DISTINCT Dept, Title, Grade, Salary
FROM EmployeeFD
WHERE Dept = 'IT' AND Title = 'Engineer';  -- Shows Grade and Salary derived
-- Verify FD2: Title → Grade
SELECT DISTINCT Title, Grade
FROM EmployeeFD;  -- All Engineers have Grade A, all Managers have Grade B
-- Verify FD3: Dept, Grade → Salary (approximated range)
SELECT DISTINCT Dept, Grade, Salary
FROM EmployeeFD;  -- IT/A → 100000-120000, HR/B → 90000-110000
PRINT 'Result: Q⁺ = {Dept, Title, Grade, Salary} based on derived attributes';
-- Step 4: Show Salary ∈ Q⁺
PRINT 'Step 2: Salary ∈ Q⁺ (True)';
-- Demonstrate that Salary is derivable from {Dept, Title} (via Grade)
SELECT Dept, Title, Salary
FROM EmployeeFD
WHERE Dept = 'IT' AND Title = 'Engineer';  -- Salary range (100000-120000) is inferred
-- Step 5: Decide on Query and apply transformation
PRINT 'Step 3: Query like SELECT Salary WHERE Dept = ''IT'' AND Title = ''Engineer''';
PRINT 'Decision: REJECT direct query or TRANSFORM to aggregated data';
-- Original query (rejected in practice)
 SELECT Salary FROM EmployeeFD WHERE Dept = 'IT' AND Title = 'Engineer';
-- Transformed query to prevent inference
SELECT AVG(Salary) AS Safe_Avg_Salary
FROM EmployeeFD
WHERE Dept IN ('IT', 'HR');  -- Aggregated value instead of individual Salary
-- Clean up (optional) to maintain original state
DROP TABLE EmployeeFD;
GO
USE mohanad;
GO

-- =========================================
-- PART 6 — Inference via Aggregates (ATTACK & DEFENSE)
-- =========================================
USE mohanad;
GO

-- Clean up any old artifacts
IF OBJECT_ID('vAvgAll', 'V') IS NOT NULL DROP VIEW vAvgAll;
IF OBJECT_ID('vAvgWithoutTarget', 'V') IS NOT NULL DROP VIEW vAvgWithoutTarget;
IF OBJECT_ID('vAvgAll_KAnon', 'V') IS NOT NULL DROP VIEW vAvgAll_KAnon;
IF OBJECT_ID('vAvgWithoutTarget_KAnon', 'V') IS NOT NULL DROP VIEW vAvgWithoutTarget_KAnon;
GO

PRINT '=== PART 6: Aggregate Inference Attack (before K-anonymity) ===';
-- We pick a small group (3 employees) and target employee EmpId = 1
-- vAvgAll: average salary of the whole group (includes the target)
CREATE VIEW vAvgAll AS
SELECT 
    AVG(CAST(Salary AS DECIMAL(18,2))) AS AvgAll,
    COUNT(*) AS CountAll
FROM Employee
WHERE EmpId IN (1,2,3);
GO

-- vAvgWithoutTarget: average salary of the group without the target
CREATE VIEW vAvgWithoutTarget AS
SELECT 
    AVG(CAST(Salary AS DECIMAL(18,2))) AS AvgWithout,
    COUNT(*) AS CountWithout
FROM Employee
WHERE EmpId IN (1,2,3) AND EmpId <> 1;  -- target is EmpId = 1
GO

-- Grant read permission on the aggregate views to the public role
GRANT SELECT ON vAvgAll TO public_role;
GRANT SELECT ON vAvgWithoutTarget TO public_role;
GO

-- Attack execution: infer the target's salary from the two averages
-- InferredSalary = (AvgAll * CountAll) - (AvgWithout * (CountAll - 1))
PRINT '>>> Attack as public (general): inferring target salary via averages';
EXEC AS USER = 'general';
    SELECT 
        a.AvgAll, a.CountAll, w.AvgWithout, (a.CountAll - 1) AS CountWithout,
        (a.AvgAll * a.CountAll) - (w.AvgWithout * (a.CountAll - 1)) AS InferredSalary
    FROM vAvgAll a CROSS JOIN vAvgWithoutTarget w;
REVERT;
GO

PRINT '=== DEFENSE: Apply K-anonymity (k = 4) to block inference ===';
-- Apply K-anonymity: do not return averages if the group size < 4

CREATE VIEW vAvgAll_KAnon AS
WITH G AS (
    SELECT 
        AVG(CAST(Salary AS DECIMAL(18,2))) AS AvgAll,
        COUNT(*) AS CountAll
    FROM Employee
    WHERE EmpId IN (1,2,3)         -- the same small group
)
SELECT * FROM G WHERE CountAll >= 4; -- will return no rows because CountAll = 3
GO

CREATE VIEW vAvgWithoutTarget_KAnon AS
WITH G AS (
    SELECT 
        AVG(CAST(Salary AS DECIMAL(18,2))) AS AvgWithout,
        COUNT(*) AS CountWithout
    FROM Employee
    WHERE EmpId IN (1,2,3) AND EmpId <> 1
)
SELECT * FROM G WHERE CountWithout >= 4; -- will return no rows because CountWithout = 2
GO

GRANT SELECT ON vAvgAll_KAnon TO public_role;
GRANT SELECT ON vAvgWithoutTarget_KAnon TO public_role;
GO

-- Verification: public user should not be able to perform the inference because the views return no rows
PRINT '>>> Test as public (general): K-anonymity should block results (no rows returned)';
EXEC AS USER = 'general';
    SELECT * FROM vAvgAll_KAnon;             -- expected: no results
    SELECT * FROM vAvgWithoutTarget_KAnon;   -- expected: no results
    -- therefore it's not possible to compute (AvgAll*CountAll) - (AvgWithout*(CountAll-1))
REVERT;
GO

PRINT 'PART 6 Completed: Aggregate inference demonstrated and then blocked by K-anonymity (k=4).';
