-- Run by Setup.bat as the "postgres" superuser: psql -v pw=<password> -f setup-db.sql
-- Creates (or updates) the app's own login "erp" and the "ERP" database it owns. Safe to run again.
\set ON_ERROR_STOP on

SELECT 'CREATE ROLE erp' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'erp')\gexec
ALTER ROLE erp WITH LOGIN CREATEDB PASSWORD :'pw';

SELECT 'CREATE DATABASE "ERP" OWNER erp ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ERP')\gexec
ALTER DATABASE "ERP" OWNER TO erp;
