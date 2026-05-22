-- Create sample raw data tables for the Cortex Research Intelligence project
-- Run this script to set up the base tables before loading seed data via dbt

USE WAREHOUSE CORTEX_WH;
USE DATABASE CORTEX_RESEARCH;
USE SCHEMA RAW;

-- =====================================================
-- EARNINGS CALLS TABLE
-- Stores raw earnings call transcripts with metadata
-- =====================================================

CREATE OR REPLACE TABLE earnings_calls (
    call_id              VARCHAR(50)  PRIMARY KEY,
    ticker               VARCHAR(10)  NOT NULL,
    company_name         VARCHAR(200),
    call_date            DATE         NOT NULL,
    call_type            VARCHAR(20),
    quarter              NUMBER(1),
    fiscal_year          NUMBER(4),
    speaker_name         VARCHAR(200),
    speaker_role         VARCHAR(100),
    transcript_text      TEXT,
    confidence_score     FLOAT        DEFAULT 0.85,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw earnings call transcripts with speaker metadata and confidence scores';

-- Create search optimization for transcript text queries
ALTER TABLE earnings_calls ADD SEARCH OPTIMIZATION ON EQUALITY(ticker, speaker_role);

-- =====================================================
-- SEC FILINGS TABLE
-- Stores extracted sections from 10-K, 10-Q, 8-K filings
-- =====================================================

CREATE OR REPLACE TABLE sec_filings (
    filing_id            VARCHAR(50)  PRIMARY KEY,
    ticker               VARCHAR(10)  NOT NULL,
    company_name         VARCHAR(200),
    filing_type          VARCHAR(10),
    filing_date          DATE         NOT NULL,
    period_end_date      DATE,
    filing_title         VARCHAR(500),
    section_text         TEXT,
    item_type            VARCHAR(50),
    pages_count          NUMBER,
    file_size_kb         NUMBER,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw SEC filing sections extracted from 10-K, 10-Q, and 8-K filings';

-- Search optimization for filing queries
ALTER TABLE sec_filings ADD SEARCH OPTIMIZATION ON EQUALITY(ticker, filing_type, item_type);

-- =====================================================
-- STOCK PRICES TABLE
-- Daily OHLCV stock price data
-- =====================================================

CREATE OR REPLACE TABLE stock_prices (
    price_id             VARCHAR(50)  PRIMARY KEY,
    ticker               VARCHAR(10)  NOT NULL,
    price_date           DATE         NOT NULL,
    open_price           FLOAT,
    high_price           FLOAT,
    low_price            FLOAT,
    close_price          FLOAT,
    adj_close_price      FLOAT,
    volume               BIGINT,
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Daily OHLCV stock price data from market feeds';

-- Search optimization for price queries
ALTER TABLE stock_prices ADD SEARCH OPTIMIZATION ON EQUALITY(ticker);

-- Create composite clustering key for efficient time-series queries
ALTER TABLE stock_prices CLUSTER BY (ticker, price_date);

-- =====================================================
-- EVENT LOG TABLE (in Analytics schema)
-- Tracks task executions and CDC events
-- =====================================================

CREATE OR REPLACE TABLE CORTEX_RESEARCH.ANALYTICS.event_log (
    event_id             STRING       DEFAULT UUID_STRING(),
    event_type           STRING       NOT NULL,
    event_time           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    details              VARIANT      DEFAULT NULL,
    records_affected     INTEGER      DEFAULT 0
)
COMMENT = 'Task execution and CDC event log for monitoring';

-- =====================================================
-- DATA LOADING NOTES
-- =====================================================

-- Option 1: Load data via dbt seed (recommended for development)
-- dbt seed --select sample_earnings_calls sample_sec_filings sample_stock_prices

-- Option 2: Load data directly into raw tables
-- COPY INTO earnings_calls FROM @~/earnings_calls.csv
--     FILE_FORMAT = (TYPE = 'CSV' FIELD_DELIMITER = ',' SKIP_HEADER = 1);

-- Option 3: Insert from dbt seed tables
-- INSERT INTO earnings_calls
-- SELECT * FROM CORTEX_RESEARCH.STAGING.SAMPLE_EARNINGS_CALLS;

-- =====================================================
-- DATA QUALITY CHECKS
-- =====================================================

-- Verify row counts after loading
SELECT 'earnings_calls' AS table_name, COUNT(*) AS row_count FROM earnings_calls
UNION ALL
SELECT 'sec_filings', COUNT(*) FROM sec_filings
UNION ALL
SELECT 'stock_prices', COUNT(*) FROM stock_prices;

-- Check date ranges
SELECT 'earnings_calls' AS table_name,
       MIN(call_date) AS min_date, MAX(call_date) AS max_date
FROM earnings_calls
UNION ALL
SELECT 'sec_filings', MIN(filing_date), MAX(filing_date)
FROM sec_filings
UNION ALL
SELECT 'stock_prices', MIN(price_date), MAX(price_date)
FROM stock_prices;

-- Check ticker coverage
SELECT ticker, COUNT(*) AS record_count
FROM earnings_calls
GROUP BY ticker
ORDER BY record_count DESC;
