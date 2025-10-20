CREATE DATABASE taskdb;
USE taskdb;

-- Tables
CREATE TABLE Clients (
   ClientID INT IDENTITY(1,1) PRIMARY KEY,
   FullName NVARCHAR(120) NOT NULL,
   Email NVARCHAR(255) NOT NULL UNIQUE,
   Phone NVARCHAR(50) NULL
);

CREATE TABLE Purchases (
   PurchaseID INT IDENTITY(1,1) PRIMARY KEY,
   ClientID INT NOT NULL
        CONSTRAINT FK_Purchases_Clients REFERENCES dbo.Clients(ClientID),
   Amount DECIMAL(10,2) NOT NULL CHECK (Amount >= 0),
   Status NVARCHAR(20) NOT NULL DEFAULT('pending')
);

/* Seed data */

INSERT INTO dbo.Clients (FullName, Email, Phone)
VALUES
(N'Amr Yasser', N'amr10tuf@gmail.com', N'01211774738'),
(N'Dr.Amr Yasser',    N'amrybhh@gmail.com',    N'01019720641');



INSERT INTO dbo.Purchases (ClientID, Amount, Status)
VALUES
(1, 150.00, N'paid'),
(2,  75.25, N'pending');



-- Logins & Users
CREATE LOGIN ClientReader WITH PASSWORD = 'Reader#123', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE LOGIN ClientWriter WITH PASSWORD = 'Writer#123', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE LOGIN ClientManager WITH PASSWORD = 'Manager#123', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;

CREATE USER ClientReaderUser FOR LOGIN ClientReader WITH DEFAULT_SCHEMA = dbo;
CREATE USER ClientWriterUser FOR LOGIN ClientWriter WITH DEFAULT_SCHEMA = dbo;
CREATE USER ClientManagerUser FOR LOGIN ClientManager WITH DEFAULT_SCHEMA = dbo;

-- Roles
CREATE ROLE client_read;
CREATE ROLE client_write;
CREATE ROLE client_manage;

-- Assign Users to Roles
EXEC sp_addrolemember 'client_read', 'ClientReaderUser';
EXEC sp_addrolemember 'client_write', 'ClientWriterUser';
EXEC sp_addrolemember 'client_manage', 'ClientManagerUser';

-- Permissions
GRANT CONNECT TO ClientReaderUser, ClientWriterUser, ClientManagerUser;

-- Reader: can only SELECT Clients
GRANT SELECT ON dbo.Clients TO client_read;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Purchases TO ClientReaderUser;

-- Writer: can only INSERT Purchases
GRANT INSERT ON dbo.Purchases TO client_write;
DENY SELECT, UPDATE, DELETE ON dbo.Purchases TO ClientWriterUser;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Clients TO ClientWriterUser;

-- Manager: can SELECT + INSERT Purchases
GRANT SELECT, INSERT ON dbo.Purchases TO client_manage;
DENY UPDATE, DELETE ON dbo.Purchases TO ClientManagerUser;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Clients TO ClientManagerUser;

-- Hide everything else
DENY VIEW DEFINITION TO PUBLIC;

GRANT VIEW DEFINITION ON dbo.Clients TO ClientReaderUser;
GRANT VIEW DEFINITION ON dbo.Purchases TO ClientWriterUser;
GRANT VIEW DEFINITION ON dbo.Purchases TO ClientManagerUser;



EXECUTE AS USER = 'ClientReaderUser';
SELECT * FROM dbo.Clients;          
SELECT * FROM dbo.Purchases;        
REVERT;



EXECUTE AS USER = 'ClientWriterUser';
INSERT INTO dbo.Purchases (ClientID, Amount, Status) VALUES (1, 500.00, 'pending');             
SELECT * FROM dbo.Purchases;                        
REVERT;




EXECUTE AS USER = 'ClientManagerUser';
SELECT * FROM dbo.Purchases;   
INSERT INTO dbo.Purchases (ClientID, Amount, Status) VALUES (2, 600.00, 'paid');           
SELECT * FROM dbo.Clients;                 
REVERT;
