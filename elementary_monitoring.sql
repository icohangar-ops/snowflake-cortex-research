-- =============================================================================
-- Elementary Monitoring Queries for CortexEdge
-- =============================================================================
-- Run these queries in Snowflake to monitor the CortexEdge dbt pipeline.
-- Requires the elementary package installed via `dbt deps`.
-- =============================================================================

-- =============================================================================
-- 1. SOURCE FRESHNESS CHECKS
-- =============================================================================

-- Check freshness of raw earnings calls
SELECT
  MAX(call_date) AS latest_call_date,
  DATEDIFF(hour, MAX(call_date), CURRENT_TIMESTAMP()) AS hours_since_latest,
  COUNT(*) AS total_records
FROM CORTEX_RESEARCH.RAW.EARNINGS_CALLS;

-- Check freshness of raw SEC filings
SELECT
  MAX(filing_date) AS latest_filing_date,
  DATEDIFF(hour, MAX(filing_date), CURRENT_TIMESTAMP()) AS hours_since_latest,
  COUNT(*) AS total_records
FROM CORTEX_RESEARCH.RAW.SEC_FILINGS;

-- Check freshness of raw stock prices
SELECT
  MAX(price_date) AS latest_price_date,
  DATEDIFF(hour, MAX(price_date), CURRENT_TIMESTAMP()) AS hours_since_latest,
  COUNT(*) AS total_records
FROM CORTEX_RESEARCH.RAW.STOCK_PRICES;

-- =============================================================================
-- 2. VOLUME ANOMALY DETECTION
-- =============================================================================

-- Daily volume trend for earnings calls (7-day rolling average)
SELECT
  call_date,
  COUNT(*) AS daily_count,
  AVG(COUNT(*)) OVER (ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg,
  COUNT(*) / NULLIF(AVG(COUNT(*)) OVER (ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS volume_ratio
FROM CORTEX_RESEARCH.RAW.EARNINGS_CALLS
WHERE call_date >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY call_date
ORDER BY call_date DESC;

-- Daily volume trend for SEC filings
SELECT
  filing_date,
  COUNT(*) AS daily_count,
  AVG(COUNT(*)) OVER (ORDER BY filing_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg,
  COUNT(*) / NULLIF(AVG(COUNT(*)) OVER (ORDER BY filing_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS volume_ratio
FROM CORTEX_RESEARCH.RAW.SEC_FILINGS
WHERE filing_date >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY filing_date
ORDER BY filing_date DESC;

-- Detect significant volume drops (>50% below 7-day average)
SELECT
  call_date,
  daily_count,
  rolling_7d_avg,
  ROUND(volume_ratio * 100, 1) AS volume_pct_of_avg
FROM (
  SELECT
    call_date,
    COUNT(*) AS daily_count,
    AVG(COUNT(*)) OVER (ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg,
    COUNT(*) / NULLIF(AVG(COUNT(*)) OVER (ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS volume_ratio
  FROM CORTEX_RESEARCH.RAW.EARNINGS_CALLS
  WHERE call_date >= DATEADD(day, -30, CURRENT_DATE())
  GROUP BY call_date
) t
WHERE volume_ratio < 0.5
ORDER BY call_date DESC;

-- =============================================================================
-- 3. SCHEMA CHANGE DETECTION
-- =============================================================================

-- Detect schema changes in raw earnings calls
SELECT
  column_name,
  data_type,
  is_nullable,
  MAX(create_date) AS last_altered
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.COLUMNS
WHERE table_catalog = 'CORTEX_RESEARCH'
  AND table_schema = 'RAW'
  AND table_name = 'EARNINGS_CALLS'
GROUP BY 1, 2, 3
ORDER BY last_altered DESC;

-- Compare current schema against expected columns
SELECT
  column_name,
  data_type
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.COLUMNS
WHERE table_catalog = 'CORTEX_RESEARCH'
  AND table_schema = 'RAW'
  AND table_name = 'EARNINGS_CALLS'
  AND column_name NOT IN (
    'CALL_ID', 'TICKER', 'COMPANY_NAME', 'CALL_DATE', 'CALL_TYPE',
    'QUARTER', 'FISCAL_YEAR', 'SPEAKER_NAME', 'SPEAKER_ROLE',
    'TRANSCRIPT_TEXT', 'CONFIDENCE_SCORE', '_LOADED_AT'
  );

-- =============================================================================
-- 4. SENTIMENT SCORE ANOMALIES
-- =============================================================================

-- Sentiment score distribution (should be roughly centered around 0)
SELECT
  COUNT(*) AS total_records,
  ROUND(AVG(sentiment_score), 4) AS mean_sentiment,
  ROUND(STDDEV(sentiment_score), 4) AS std_sentiment,
  MIN(sentiment_score) AS min_sentiment,
  MAX(sentiment_score) AS max_sentiment,
  COUNT(CASE WHEN sentiment_score IS NULL THEN 1 END) AS null_count,
  ROUND(COUNT(CASE WHEN sentiment_score IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) AS null_pct
FROM CORTEX_RESEARCH.STAGING.INT_EARNINGS_SENTIMENT;

-- Detect sentiment outliers (beyond 3 standard deviations)
WITH stats AS (
  SELECT
    AVG(sentiment_score) AS mean_val,
    STDDEV(sentiment_score) AS std_val
  FROM CORTEX_RESEARCH.STAGING.INT_EARNINGS_SENTIMENT
)
SELECT
  e.call_id,
  e.ticker,
  e.sentiment_score,
  e.call_date,
  ROUND(ABS(e.sentiment_score - s.mean_val) / NULLIF(s.std_val, 0), 2) AS z_score
FROM CORTEX_RESEARCH.STAGING.INT_EARNINGS_SENTIMENT e
CROSS JOIN stats s
WHERE ABS(e.sentiment_score - s.mean_val) / NULLIF(s.std_val, 0) > 3
ORDER BY z_score DESC;

-- =============================================================================
-- 5. RISK CLASSIFICATION DISTRIBUTION
-- =============================================================================

-- Risk category distribution (should not shift dramatically)
SELECT
  risk_category,
  COUNT(*) AS record_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM CORTEX_RESEARCH.STAGING.INT_FILING_CLASSIFICATIONS
GROUP BY risk_category
ORDER BY record_count DESC;

-- Detect unusual risk flag surge
SELECT
  filing_date,
  COUNT(*) AS total_filings,
  COUNT(CASE WHEN risk_category != 'OPERATIONAL' THEN 1 END) AS risk_flagged,
  ROUND(COUNT(CASE WHEN risk_category != 'OPERATIONAL' THEN 1 END) * 100.0 / COUNT(*), 1) AS risk_pct
FROM CORTEX_RESEARCH.STAGING.INT_FILING_CLASSIFICATIONS
WHERE filing_date >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY filing_date
HAVING COUNT(CASE WHEN risk_category != 'OPERATIONAL' THEN 1 END) * 100.0 / COUNT(*) > 60
ORDER BY filing_date DESC;

-- =============================================================================
-- 6. EMBEDDING CONSISTENCY CHECKS
-- =============================================================================

-- Verify all embeddings have correct dimensions
SELECT
  COUNT(*) AS total_embeddings,
  COUNT(CASE WHEN ARRAY_SIZE(embedding_vector) != 5 THEN 1 END) AS wrong_dimension_count,
  COUNT(CASE WHEN embedding_vector IS NULL THEN 1 END) AS null_embedding_count
FROM CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS;

-- Detect any embedding dimension drift
SELECT
  ARRAY_SIZE(embedding_vector) AS dimension,
  COUNT(*) AS count
FROM CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS
GROUP BY 1;

-- =============================================================================
-- 7. COMPOSITE SIGNAL VALIDATION
-- =============================================================================

-- Signal direction distribution (should be balanced)
SELECT
  signal_direction,
  COUNT(*) AS ticker_count,
  ROUND(AVG(composite_signal_score), 2) AS avg_composite_score,
  MIN(composite_signal_score) AS min_score,
  MAX(composite_signal_score) AS max_score
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
GROUP BY signal_direction;

-- Detect stale signals (not refreshed in last 24 hours)
SELECT
  ticker,
  signal_generated_at,
  DATEDIFF(hour, signal_generated_at, CURRENT_TIMESTAMP()) AS hours_stale
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
WHERE DATEDIFF(hour, signal_generated_at, CURRENT_TIMESTAMP()) > 24
ORDER BY hours_stale DESC;

-- =============================================================================
-- 8. PREDICTION ACCURACY MONITORING
-- =============================================================================

-- Prediction accuracy over time (should not degrade)
SELECT
  prediction_accuracy,
  COUNT(*) AS occurrence_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY
GROUP BY prediction_accuracy
ORDER BY occurrence_count DESC;

-- Detect accuracy degradation (high contrary signal rate)
SELECT
  fiscal_year,
  fiscal_quarter,
  COUNT(*) AS total_predictions,
  COUNT(CASE WHEN prediction_accuracy = 'Contrary Signal' THEN 1 END) AS contrary_count,
  ROUND(COUNT(CASE WHEN prediction_accuracy = 'Contrary Signal' THEN 1 END) * 100.0 / COUNT(*), 1) AS contrary_pct
FROM CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY
GROUP BY 1, 2
HAVING COUNT(CASE WHEN prediction_accuracy = 'Contrary Signal' THEN 1 END) * 100.0 / COUNT(*) > 30
ORDER BY 1 DESC, 2 DESC;

-- =============================================================================
-- 9. DYNAMIC TABLE REFRESH MONITORING
-- =============================================================================

-- Check Dynamic Table refresh health
SELECT
  name AS table_name,
  state,
  target_lag,
  last_refresh_time,
  seconds_since_last_refresh,
  refresh_reason,
  DATEDIFF(minute, last_refresh_time, CURRENT_TIMESTAMP()) AS minutes_since_refresh
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY
WHERE name IN (
  'MART_RESEARCH_SIGNALS',
  'MART_EARNINGS_SUMMARY',
  'MART_FILING_DASHBOARD'
)
ORDER BY last_refresh_time DESC;

-- Detect stuck Dynamic Tables
SELECT
  name AS table_name,
  state,
  DATEDIFF(hour, last_refresh_time, CURRENT_TIMESTAMP()) AS hours_since_refresh
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY
WHERE state != 'FRONTEND_REFRESHING'
  AND DATEDIFF(hour, last_refresh_time, CURRENT_TIMESTAMP()) > 6
ORDER BY hours_since_refresh DESC;

-- =============================================================================
-- 10. STREAM AND CDC MONITORING
-- =============================================================================

-- Stream lag and throughput
SELECT
  s.name AS stream_name,
  s.table_name AS source_table,
  s.created_on AS stream_created,
  SUM(t.rows_inserted) AS total_inserts,
  SUM(t.rows_updated) AS total_updates,
  SUM(t.rows_deleted) AS total_deletes,
  MAX(t.insertion_time) AS last_activity
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.STREAMS s
LEFT JOIN TABLE(INFORMATION_SCHEMA.CHANGE_TRACKING_TABLES()) t
  ON s.name = t.stream_name
GROUP BY 1, 2, 3
ORDER BY last_activity DESC;

-- Detect inactive streams (no changes in 24 hours)
SELECT
  s.name AS stream_name,
  s.table_name,
  MAX(t.insertion_time) AS last_activity,
  DATEDIFF(hour, MAX(t.insertion_time), CURRENT_TIMESTAMP()) AS hours_inactive
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.STREAMS s
LEFT JOIN TABLE(INFORMATION_SCHEMA.CHANGE_TRACKING_TABLES()) t
  ON s.name = t.stream_name
GROUP BY 1, 2
HAVING DATEDIFF(hour, MAX(t.insertion_time), CURRENT_TIMESTAMP()) > 24
ORDER BY hours_inactive DESC;

-- =============================================================================
-- 11. BUSINESS METRIC VALIDATION
-- =============================================================================

-- Validate composite signal score is within expected bounds
SELECT
  COUNT(*) AS total_tickers,
  COUNT(CASE WHEN composite_signal_score < -10 OR composite_signal_score > 10 THEN 1 END) AS out_of_bounds,
  MIN(composite_signal_score) AS min_score,
  MAX(composite_signal_score) AS max_score
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS;

-- Validate post-earnings returns are reasonable
SELECT
  COUNT(*) AS total_records,
  COUNT(CASE WHEN ABS(post_earnings_5d_return_pct) > 50 THEN 1 END) AS extreme_moves,
  COUNT(CASE WHEN post_earnings_5d_return_pct IS NULL THEN 1 END) AS null_returns
FROM CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY;

-- =============================================================================
-- 12. DATA QUALITY SUMMARY
-- =============================================================================

-- Overall data quality score card
SELECT
  'Earnings Calls' AS metric_group,
  COUNT(*) AS total_rows,
  COUNT(CASE WHEN sentiment_score IS NOT NULL THEN 1 END) AS complete_rows,
  ROUND(COUNT(CASE WHEN sentiment_score IS NOT NULL THEN 1 END) * 100.0 / COUNT(*), 1) AS completeness_pct
FROM CORTEX_RESEARCH.STAGING.INT_EARNINGS_SENTIMENT
UNION ALL
SELECT
  'SEC Filings' AS metric_group,
  COUNT(*) AS total_rows,
  COUNT(CASE WHEN risk_category IS NOT NULL THEN 1 END) AS complete_rows,
  ROUND(COUNT(CASE WHEN risk_category IS NOT NULL THEN 1 END) * 100.0 / COUNT(*), 1) AS completeness_pct
FROM CORTEX_RESEARCH.STAGING.INT_FILING_CLASSIFICATIONS
UNION ALL
SELECT
  'Stock Prices' AS metric_group,
  COUNT(*) AS total_rows,
  COUNT(CASE WHEN close_price IS NOT NULL THEN 1 END) AS complete_rows,
  ROUND(COUNT(CASE WHEN close_price IS NOT NULL THEN 1 END) * 100.0 / COUNT(*), 1) AS completeness_pct
FROM CORTEX_RESEARCH.STAGING.INT_PRICE_METRICS
UNION ALL
SELECT
  'Research Signals' AS metric_group,
  COUNT(*) AS total_rows,
  COUNT(CASE WHEN composite_signal_score IS NOT NULL THEN 1 END) AS complete_rows,
  ROUND(COUNT(CASE WHEN composite_signal_score IS NOT NULL THEN 1 END) * 100.0 / COUNT(*), 1) AS completeness_pct
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
ORDER BY completeness_pct ASC;
