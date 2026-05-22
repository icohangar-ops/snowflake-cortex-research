-- Test: Earnings sentiment scores should be within valid range [-1, 1]
-- This is a custom dbt test that identifies data quality issues
-- Add to tests/ directory and reference from _staging_models.yml

SELECT
    ticker,
    call_date,
    sentiment_score,
    speaker_name,
    speaker_role
FROM {{ ref('int_earnings_sentiment') }}
WHERE sentiment_score < -1.0 OR sentiment_score > 1.0
