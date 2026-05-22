-- Dynamic Tables for auto-refreshing analytical layers
-- These complement dbt models with native Snowflake auto-refresh
-- Dynamic Tables automatically refresh based on data changes in base tables

USE WAREHOUSE CORTEX_WH;
USE DATABASE CORTEX_RESEARCH;

-- =====================================================
-- EARNINGS SENTIMENT DYNAMIC TABLE
-- Auto-refreshes every 5 minutes when underlying data changes
-- =====================================================

CREATE OR REPLACE DYNAMIC TABLE dt_earnings_sentiment
    TARGET_LAG = '5 MINUTES'
    WAREHOUSE = CORTEX_WH
    COMMENT = 'CEO earnings call sentiment with Cortex AI enrichment (auto-refreshing)'
    AS
    SELECT
        e.call_id,
        e.ticker,
        e.company_name,
        e.call_date,
        e.quarter,
        e.fiscal_year,
        e.speaker_name,
        e.speaker_role,
        e.transcript_text,

        -- Cortex AI sentiment (available on paid Snowflake Enterprise+)
        -- SNOWFLAKE.CORTEX.SENTIMENT(e.transcript_text) AS sentiment_score,

        -- Keyword-based sentiment for trial/demo environments
        CASE
            WHEN e.transcript_text LIKE '%record revenue%' THEN 0.85
            WHEN e.transcript_text LIKE '%exceeded expectations%' THEN 0.92
            WHEN e.transcript_text LIKE '%headwinds%' THEN -0.35
            WHEN e.transcript_text LIKE '%challenging environment%' THEN -0.55
            WHEN e.transcript_text LIKE '%strong growth%' THEN 0.78
            WHEN e.transcript_text LIKE '%margin pressure%' THEN -0.42
            WHEN e.transcript_text LIKE '%outlook positive%' THEN 0.71
            WHEN e.transcript_text LIKE '%uncertain%' THEN -0.20
            ELSE 0.0
        END AS sentiment_score,

        -- Cortex AI summary (available on paid Snowflake Enterprise+)
        -- SNOWFLAKE.CORTEX.SUMMARIZE(e.transcript_text) AS summary,

        CASE
            WHEN e.transcript_text LIKE '%AI%' THEN 'AI / ML'
            WHEN e.transcript_text LIKE '%cloud%' THEN 'Cloud Infrastructure'
            WHEN e.transcript_text LIKE '%margin%' THEN 'Financial Performance'
            ELSE 'General Commentary'
        END AS primary_theme,

        CURRENT_TIMESTAMP() AS _refreshed_at
    FROM CORTEX_RESEARCH.STAGING.STG_EARNINGS_CALLS e
    WHERE e.speaker_role = 'CEO';

-- =====================================================
-- FILING RISK SIGNALS DYNAMIC TABLE
-- Auto-refreshes every 10 minutes
-- =====================================================

CREATE OR REPLACE DYNAMIC TABLE dt_filing_risk_signals
    TARGET_LAG = '10 MINUTES'
    WAREHOUSE = CORTEX_WH
    COMMENT = 'Aggregated risk signals from SEC filing classifications'
    AS
    SELECT
        f.ticker,
        f.filing_type,
        f.filing_date,
        f.item_type,
        f.risk_category,
        f.sentiment_polarity,
        f.text_length,
        f.word_count,
        COUNT(*) OVER (
            PARTITION BY f.ticker, f.filing_date
        ) AS sections_per_filing,
        CURRENT_TIMESTAMP() AS _refreshed_at
    FROM CORTEX_RESEARCH.STAGING.INT_FILING_CLASSIFICATIONS f;

-- =====================================================
-- REAL-TIME PRICE SUMMARY DYNAMIC TABLE
-- Auto-refreshes every 1 minute for near real-time
-- =====================================================

CREATE OR REPLACE DYNAMIC TABLE dt_price_summary
    TARGET_LAG = '1 MINUTE'
    WAREHOUSE = CORTEX_WH
    COMMENT = 'Latest price metrics and technical indicators'
    AS
    SELECT
        p.ticker,
        p.price_date,
        p.close_price,
        p.volume,
        p.dollar_volume,
        p.daily_return_pct,
        p.ma_20d,
        p.ma_50d,
        p.ma_ratio_20_50,
        p.volatility_20d,
        p.sharpe_like_ratio,

        -- Signal classification
        CASE
            WHEN p.ma_ratio_20_50 > 1.02 AND p.daily_return_pct > 0 THEN 'STRONG_BUY'
            WHEN p.ma_ratio_20_50 > 1.00 AND p.daily_return_pct > 0 THEN 'BUY'
            WHEN p.ma_ratio_20_50 < 0.98 AND p.daily_return_pct < 0 THEN 'STRONG_SELL'
            WHEN p.ma_ratio_20_50 < 1.00 AND p.daily_return_pct < 0 THEN 'SELL'
            ELSE 'HOLD'
        END AS technical_signal,

        CURRENT_TIMESTAMP() AS _refreshed_at
    FROM CORTEX_RESEARCH.STAGING.INT_PRICE_METRICS p
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.ticker ORDER BY p.price_date DESC) = 1;

-- =====================================================
-- MONITORING: Dynamic Table Refresh Status
-- =====================================================

-- Query to check Dynamic Table refresh status
-- SELECT
--     TABLE_NAME,
--     TARGET_LAG,
--     REFRESH_MODE,
--     DATA_TIMESTAMP,
--     REFRESH_ERROR
-- FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
--     DATEADD(hour, -24, CURRENT_TIMESTAMP())
-- ))
-- WHERE TABLE_NAME LIKE 'DT_%'
-- ORDER BY DATA_TIMESTAMP DESC;

-- =====================================================
-- ZERO-COPY CLONE SCENARIO: Stress Test
-- =====================================================

-- Clone the database to simulate market downturn
-- CREATE DATABASE CORTEX_RESEARCH_STRESS_TEST CLONE CORTEX_RESEARCH;

-- In the clone, simulate adverse scenario by adjusting sentiment scores
-- UPDATE CORTEX_RESEARCH_STRESS_TEST.STAGING.INT_EARNINGS_SENTIMENT
-- SET sentiment_score = sentiment_score * 0.4 - 0.2;
