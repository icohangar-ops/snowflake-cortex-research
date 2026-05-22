-- Streams and Tasks for automated CDC and scheduled ELT
-- This script sets up Change Data Capture streams and scheduled tasks

USE WAREHOUSE CORTEX_WH;
USE DATABASE CORTEX_RESEARCH;

-- =====================================================
-- CHANGE DATA CAPTURE (CDC) STREAMS
-- Streams track all DML changes (INSERT, UPDATE, DELETE) on source tables
-- =====================================================

-- Stream on earnings calls table
CREATE OR REPLACE STREAM raw_earnings_stream
    ON TABLE CORTEX_RESEARCH.RAW.EARNINGS_CALLS
    COMMENT = 'CDC stream for new/modified earnings call data';

-- Stream on SEC filings table
CREATE OR REPLACE STREAM raw_filings_stream
    ON TABLE CORTEX_RESEARCH.RAW.SEC_FILINGS
    COMMENT = 'CDC stream for new/modified SEC filing data';

-- Stream on stock prices table
CREATE OR REPLACE STREAM raw_prices_stream
    ON TABLE CORTEX_RESEARCH.RAW.STOCK_PRICES
    COMMENT = 'CDC stream for new/modified stock price data';

-- =====================================================
-- SCHEDULED TASKS
-- Tasks automate recurring ETL operations on a cron schedule
-- =====================================================

-- Task: Run dbt models on new earnings data
-- Runs at 8 AM and 8 PM Eastern Time (after market close/pre-market)
CREATE OR REPLACE TASK dbt_run_earnings
    WAREHOUSE = DBT_WH
    SCHEDULE = 'USING CRON 0 8,20 * * * America/New_York'
    COMMENT = 'Run dbt earnings models after market hours'
    AS
    EXECUTE IMMEDIATE FROM
    $$ SELECT SYSTEM$DBT_RUN('CORTEX_RESEARCH.STAGING.STG_EARNINGS_CALLS', 'CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY') $$;

-- Task: Process new filings (runs daily at 6:30 AM ET - before market open)
CREATE OR REPLACE TASK dbt_run_filings
    WAREHOUSE = DBT_WH
    SCHEDULE = 'USING CRON 30 6 * * * America/New_York'
    COMMENT = 'Run dbt filing models before market open'
    AS
    EXECUTE IMMEDIATE FROM
    $$ SELECT SYSTEM$DBT_RUN('CORTEX_RESEARCH.STAGING.STG_SEC_FILINGS', 'CORTEX_RESEARCH.ANALYTICS.MART_FILING_DASHBOARD') $$;

-- Task: Process new stock price data (runs at 6 PM ET - after market close)
CREATE OR REPLACE TASK dbt_run_prices
    WAREHOUSE = DBT_WH
    SCHEDULE = 'USING CRON 0 18 * * 1-5 America/New_York'
    COMMENT = 'Run dbt price models after market close'
    AS
    EXECUTE IMMEDIATE FROM
    $$ SELECT SYSTEM$DBT_RUN('CORTEX_RESEARCH.STAGING.STG_STOCK_PRICES', 'CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS') $$;

-- Task: Generate ML embeddings weekly (Sundays at 2 AM)
CREATE OR REPLACE TASK dbt_run_ml
    WAREHOUSE = CORTEX_WH
    SCHEDULE = 'USING CRON 0 2 * * 0 America/New_York'
    COMMENT = 'Weekly ML model refresh for embeddings and training data'
    AS
    EXECUTE IMMEDIATE FROM
    $$ SELECT SYSTEM$DBT_RUN('CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS', 'CORTEX_RESEARCH.ML.ML_SENTIMENT_TRAINING') $$;

-- =====================================================
-- EVENT-DRIVEN TASK CHAIN (CDC-triggered)
-- Tasks execute when new data arrives via streams
-- =====================================================

-- Event table for tracking task executions
CREATE OR REPLACE TABLE CORTEX_RESEARCH.ANALYTICS.event_log (
    event_id STRING DEFAULT UUID_STRING(),
    event_type STRING NOT NULL,
    event_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    details VARIANT DEFAULT NULL,
    records_affected INTEGER DEFAULT 0
);

-- Root task: Detect new earnings data
CREATE OR REPLACE TASK detect_new_earnings
    WAREHOUSE = DBT_WH
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Check for new earnings data every minute'
    AS
    BEGIN
        INSERT INTO CORTEX_RESEARCH.ANALYTICS.event_log (event_type, records_affected, details)
        SELECT
            'EARNINGS_CDC',
            SYSTEM$STREAM_HAS_DATA('raw_earnings_stream')::INTEGER,
            PARSE_JSON('{"source": "earnings_calls_stream", "action": "pending"}')
        WHERE SYSTEM$STREAM_HAS_DATA('raw_earnings_stream') = TRUE;
    END;

-- Downstream task: Process detected earnings data
CREATE OR REPLACE TASK process_new_earnings
    WAREHOUSE = DBT_WH
    AFTER detect_new_earnings
    COMMENT = 'Process new earnings data from CDC stream'
    AS
    BEGIN
        -- Process CDC records
        MERGE INTO CORTEX_RESEARCH.STAGING.STG_EARNINGS_CALLS target
        USING (
            SELECT * FROM CORTEX_RESEARCH.RAW.EARNINGS_CALLS
            WHERE METADATA$ACTION = 'INSERT'
        ) source
        ON target.call_id = source.call_id
        WHEN MATCHED THEN
            UPDATE SET
                target.ticker = source.ticker,
                target.company_name = source.company_name,
                target.transcript_text = source.transcript_text
        WHEN NOT MATCHED THEN
            INSERT (call_id, ticker, company_name, call_date, call_type,
                    quarter, fiscal_year, speaker_name, speaker_role,
                    transcript_text, confidence_score, _loaded_at)
            VALUES (source.call_id, source.ticker, source.company_name,
                    source.call_date, source.call_type, source.quarter,
                    source.fiscal_year, source.speaker_name, source.speaker_role,
                    source.transcript_text, source.confidence_score, source._loaded_at);

        INSERT INTO CORTEX_RESEARCH.ANALYTICS.event_log (event_type, records_affected, details)
        SELECT 'EARNINGS_PROCESSED', SQL_ROW_COUNT, PARSE_JSON('{"status": "completed"}');
    END;

-- =====================================================
-- RESUME TASKS
-- Tasks are created in SUSPENDED state by default
-- =====================================================

ALTER TASK detect_new_earnings RESUME;
ALTER TASK process_new_earnings RESUME;
ALTER TASK dbt_run_earnings RESUME;
ALTER TASK dbt_run_filings RESUME;
ALTER TASK dbt_run_prices RESUME;
ALTER TASK dbt_run_ml RESUME;

-- =====================================================
-- MONITORING QUERIES
-- =====================================================

-- Check task status
-- SELECT
--     TASK_NAME,
--     SCHEDULE,
--     STATE,
--     LAST_COMPLETION_TIME,
--     NEXT_SCHEDULED_TIME,
--     LAST_SUCCESSFUL_RUN_TIME
-- FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD(day, -7, CURRENT_TIMESTAMP())
-- ))
-- WHERE STATE = 'SUCCEEDED'
-- ORDER BY LAST_COMPLETION_TIME DESC;

-- Check stream status (data available for processing)
-- SELECT
--     'raw_earnings_stream' AS stream_name,
--     SYSTEM$STREAM_HAS_DATA('raw_earnings_stream') AS has_data
-- UNION ALL
-- SELECT
--     'raw_filings_stream' AS stream_name,
--     SYSTEM$STREAM_HAS_DATA('raw_filings_stream') AS has_data
-- UNION ALL
-- SELECT
--     'raw_prices_stream' AS stream_name,
--     SYSTEM$STREAM_HAS_DATA('raw_prices_stream') AS has_data;
