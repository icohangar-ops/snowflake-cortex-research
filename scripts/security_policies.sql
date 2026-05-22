-- Dynamic Data Masking and Row Access Policies
-- Snowflake-native security for column-level and row-level access control

USE DATABASE CORTEX_RESEARCH;

-- =====================================================
-- DYNAMIC DATA MASKING
-- Masks sensitive data based on the current user's role
-- =====================================================

-- -----------------------------------------------------
-- Policy 1: Transcript Text Masking
-- Hides full transcript from non-analyst roles
-- -----------------------------------------------------

CREATE OR REPLACE MASKING POLICY transcript_mask
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ANALYST_ROLE', 'DATA_SCIENCE_ROLE', 'ADMIN_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('SECTOR_TECH_ROLE', 'SECTOR_ENERGY_ROLE')
            THEN CONCAT(LEFT(val, 200), '... [REDACTED - ', LENGTH(val), ' total characters]')
        ELSE CONCAT(LEFT(val, 100), '... [REDACTED - Contact administrator for full access]')
    END
COMMENT = 'Masking policy for earnings call transcripts - full text available to analysts only';

-- Apply masking to staging earnings calls
ALTER TABLE CORTEX_RESEARCH.STAGING.STG_EARNINGS_CALLS
    MODIFY COLUMN transcript_text SET MASKING POLICY transcript_mask;

-- Apply masking to intermediate sentiment table
ALTER TABLE CORTEX_RESEARCH.STAGING.INT_EARNINGS_SENTIMENT
    MODIFY COLUMN transcript_text SET MASKING POLICY transcript_mask;

-- -----------------------------------------------------
-- Policy 2: Sentiment Score Range Masking
-- Masks exact scores to ranges for non-analyst roles
-- -----------------------------------------------------

CREATE OR REPLACE MASKING POLICY sentiment_range_mask
    AS (val FLOAT) RETURNS FLOAT ->
    CASE
        WHEN CURRENT_ROLE() IN ('ANALYST_ROLE', 'DATA_SCIENCE_ROLE', 'ADMIN_ROLE') THEN val
        ELSE CASE
            WHEN val > 0.5 THEN 0.75
            WHEN val > 0.0 THEN 0.25
            WHEN val > -0.5 THEN -0.25
            ELSE -0.75
        END
    END
COMMENT = 'Masking policy for sentiment scores - exact values available to analysts only';

-- Apply masking to earnings summary mart
ALTER TABLE CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY
    MODIFY COLUMN sentiment_score SET MASKING POLICY sentiment_range_mask;

-- Apply masking to research signals mart
ALTER TABLE CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
    MODIFY COLUMN ceo_sentiment SET MASKING POLICY sentiment_range_mask;

-- -----------------------------------------------------
-- Policy 3: Embedding Vector Masking
-- Hides embedding vectors from non-ML roles
-- -----------------------------------------------------

CREATE OR REPLACE MASKING POLICY embedding_mask
    AS (val ARRAY) RETURNS ARRAY ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_SCIENCE_ROLE', 'ADMIN_ROLE') THEN val
        ELSE [0.0, 0.0, 0.0, 0.0, 0.0]
    END
COMMENT = 'Masking policy for embedding vectors - full vectors available to data science only';

-- Apply masking to ML embeddings
ALTER TABLE CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS
    MODIFY COLUMN embedding_vector SET MASKING POLICY embedding_mask;

-- -----------------------------------------------------
-- Policy 4: File Size Masking
-- Rounds file sizes for non-admin roles
-- -----------------------------------------------------

CREATE OR REPLACE MASKING POLICY file_size_round_mask
    AS (val NUMBER) RETURNS NUMBER ->
    CASE
        WHEN CURRENT_ROLE() = 'ADMIN_ROLE' THEN val
        ELSE ROUND(val / 10) * 10  -- Round to nearest 10 KB
    END
COMMENT = 'Masking policy for file sizes - rounded for non-admin users';

-- =====================================================
-- ROW ACCESS POLICIES
-- Controls which rows users can see based on their role
-- =====================================================

-- -----------------------------------------------------
-- Policy 1: Ticker-based Sector Access
-- Tech analysts see tech stocks, energy analysts see energy stocks
-- -----------------------------------------------------

CREATE OR REPLACE ROW ACCESS POLICY ticker_access_policy
    AS (ticker_val VARCHAR) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() = 'ADMIN_ROLE' THEN TRUE
        WHEN CURRENT_ROLE() IN ('ANALYST_ROLE', 'DATA_SCIENCE_ROLE') THEN TRUE
        WHEN CURRENT_ROLE() = 'SECTOR_TECH_ROLE'
            AND ticker_val IN ('AAPL', 'MSFT', 'GOOGL', 'NVDA', 'META') THEN TRUE
        WHEN CURRENT_ROLE() = 'SECTOR_ENERGY_ROLE'
            AND ticker_val IN ('TSLA') THEN TRUE
        ELSE FALSE
    END
COMMENT = 'Row access policy restricting ticker visibility by sector role';

-- Apply row access to research signals
ALTER TABLE CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

-- Apply row access to earnings summary
ALTER TABLE CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

-- Apply row access to filing dashboard
ALTER TABLE CORTEX_RESEARCH.ANALYTICS.MART_FILING_DASHBOARD
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

-- Apply row access to raw tables
ALTER TABLE CORTEX_RESEARCH.RAW.EARNINGS_CALLS
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

ALTER TABLE CORTEX_RESEARCH.RAW.SEC_FILINGS
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

ALTER TABLE CORTEX_RESEARCH.RAW.STOCK_PRICES
    ADD ROW ACCESS POLICY ticker_access_policy ON (ticker);

-- =====================================================
-- TAG-BASED DATA CLASSIFICATION
-- Adds sensitivity tags to columns for data governance
-- =====================================================

-- Create tag schema and tags
CREATE SCHEMA IF NOT EXISTS CORTEX_RESEARCH.GOVERNANCE;

CREATE OR REPLACE TAG CORTEX_RESEARCH.GOVERNANCE.sensitivity
    COMMENT = 'Data sensitivity classification';

CREATE OR REPLACE TAG CORTEX_RESEARCH.GOVERNANCE.pii
    COMMENT = 'Personally identifiable information indicator';

-- Apply tags to columns
ALTER TABLE CORTEX_RESEARCH.STAGING.STG_EARNINGS_CALLS
    MODIFY COLUMN transcript_text
    SET TAG CORTEX_RESEARCH.GOVERNANCE.sensitivity = 'CONFIDENTIAL',
              CORTEX_RESEARCH.GOVERNANCE.pii = 'FALSE';

ALTER TABLE CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS
    MODIFY COLUMN embedding_vector
    SET TAG CORTEX_RESEARCH.GOVERNANCE.sensitivity = 'INTERNAL';

-- =====================================================
-- AUDIT AND MONITORING
-- =====================================================

-- Query to check masking policies in effect
-- SELECT
--     TABLE_SCHEMA,
--     TABLE_NAME,
--     COLUMN_NAME,
--     POLICY_NAME
-- FROM SNOWFLAKE.INFORMATION_SCHEMA.TABLE_CONSTRAINTS
-- WHERE CONSTRAINT_TYPE = 'MASKING_POLICY'
-- ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- Query to check row access policies
-- SELECT
--     TABLE_SCHEMA,
--     TABLE_NAME,
--     POLICY_NAME
-- FROM SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES
-- WHERE POLICY_KIND = 'ROW_ACCESS'
-- ORDER BY TABLE_SCHEMA, TABLE_NAME;
