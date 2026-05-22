-- Cortex Research Intelligence - Snowflake Setup
-- Run this as ACCOUNTADMIN to create all required infrastructure

-- =====================================================
-- WAREHOUSE CREATION
-- =====================================================

-- Cortex AI compute warehouse (for Dynamic Tables and Cortex AI functions)
CREATE WAREHOUSE IF NOT EXISTS CORTEX_WH
    WAREHOUSE_SIZE = 'X-Small'
    AUTO_SUSPEND = 60
    AUTO_RESUME = True
    INITIALLY_SUSPENDED = True
    COMMENT = 'Cortex Research Intelligence compute warehouse';

-- dbt transformation warehouse
CREATE WAREHOUSE IF NOT EXISTS DBT_WH
    WAREHOUSE_SIZE = 'X-Small'
    AUTO_SUSPEND = 60
    AUTO_RESUME = True
    INITIALLY_SUSPENDED = True
    COMMENT = 'dbt transformation warehouse';

-- =====================================================
-- DATABASE AND SCHEMA CREATION
-- =====================================================

CREATE DATABASE IF NOT EXISTS CORTEX_RESEARCH;

-- Raw landing zone for source data
CREATE SCHEMA IF NOT EXISTS CORTEX_RESEARCH.RAW
    COMMENT = 'Raw source data landing zone';

-- Staging layer (dbt-managed)
CREATE SCHEMA IF NOT EXISTS CORTEX_RESEARCH.STAGING
    COMMENT = 'Cleaned and validated staging data';

-- Analytics layer (business-facing marts)
CREATE SCHEMA IF NOT EXISTS CORTEX_RESEARCH.ANALYTICS
    COMMENT = 'Business-facing analytical marts';

-- ML layer (machine learning features and embeddings)
CREATE SCHEMA IF NOT EXISTS CORTEX_RESEARCH.ML
    COMMENT = 'ML features, embeddings, and training data';

-- =====================================================
-- ROLE AND PRIVILEGE SETUP
-- =====================================================

-- Grant privileges to SYSADMIN for dbt execution
GRANT ALL ON DATABASE CORTEX_RESEARCH TO SYSADMIN;
GRANT USAGE ON WAREHOUSE CORTEX_WH TO SYSADMIN;
GRANT USAGE ON WAREHOUSE DBT_WH TO SYSADMIN;
GRANT ALL ON ALL SCHEMAS IN DATABASE CORTEX_RESEARCH TO SYSADMIN;
GRANT ALL ON ALL TABLES IN DATABASE CORTEX_RESEARCH TO SYSADMIN;
GRANT ALL ON ALL VIEWS IN DATABASE CORTEX_RESEARCH TO SYSADMIN;

-- Create custom roles for row-level security
CREATE ROLE IF NOT EXISTS ANALYST_ROLE;
CREATE ROLE IF NOT EXISTS DATA_SCIENCE_ROLE;
CREATE ROLE IF NOT EXISTS ADMIN_ROLE;
CREATE ROLE IF NOT EXISTS SECTOR_TECH_ROLE;
CREATE ROLE IF NOT EXISTS SECTOR_ENERGY_ROLE;

GRANT USAGE ON DATABASE CORTEX_RESEARCH TO ROLE ANALYST_ROLE;
GRANT USAGE ON DATABASE CORTEX_RESEARCH TO ROLE DATA_SCIENCE_ROLE;
GRANT USAGE ON DATABASE CORTEX_RESEARCH TO ROLE ADMIN_ROLE;
GRANT USAGE ON DATABASE CORTEX_RESEARCH TO ROLE SECTOR_TECH_ROLE;
GRANT USAGE ON DATABASE CORTEX_RESEARCH TO ROLE SECTOR_ENERGY_ROLE;

GRANT USAGE ON WAREHOUSE DBT_WH TO ROLE ANALYST_ROLE;
GRANT USAGE ON WAREHOUSE DBT_WH TO ROLE DATA_SCIENCE_ROLE;

-- =====================================================
-- INTEGRATION SETUP (for Cortex AI access)
-- =====================================================

-- Ensure Cortex AI access is enabled
-- Note: Cortex AI functions require Enterprise Edition or above
-- and the appropriate feature bundle enabled by account admin

-- =====================================================
-- ZERO-COPY CLONE TEMPLATE
-- =====================================================

-- Example: Clone the entire database for scenario analysis
-- CREATE DATABASE CORTEX_RESEARCH_SCENARIO_A CLONE CORTEX_RESEARCH;

-- Example: Clone just the analytics layer for testing
-- CREATE SCHEMA CORTEX_RESEARCH.ANALYTICS_SCENARIO CLONE CORTEX_RESEARCH.ANALYTICS;

-- =====================================================
-- VERIFICATION
-- =====================================================

-- Verify setup
SELECT
    'Warehouses' AS object_type,
    COUNT(*) AS count
FROM SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSES
WHERE WAREHOUSE_NAME IN ('CORTEX_WH', 'DBT_WH')
UNION ALL
SELECT
    'Schemas' AS object_type,
    COUNT(*) AS count
FROM SNOWFLAKE.INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = 'CORTEX_RESEARCH'
UNION ALL
SELECT
    'Roles' AS object_type,
    COUNT(*) AS count
FROM SNOWFLAKE.INFORMATION_SCHEMA.ROLES
WHERE ROLE_NAME IN ('ANALYST_ROLE', 'DATA_SCIENCE_ROLE', 'ADMIN_ROLE', 'SECTOR_TECH_ROLE', 'SECTOR_ENERGY_ROLE');
