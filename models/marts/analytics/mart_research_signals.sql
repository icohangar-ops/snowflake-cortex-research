{{ config(materialized='table') }}

WITH earnings AS (
    SELECT * FROM {{ ref('int_earnings_sentiment') }}
),

filings AS (
    SELECT
        ticker,
        filing_date,
        risk_category,
        sentiment_polarity,
        filing_type
    FROM {{ ref('int_filing_classifications') }}
),

prices AS (
    SELECT * FROM {{ ref('int_price_metrics') }}
),

risk_counts AS (
    SELECT
        ticker,
        COUNT(*) AS total_risk_flags,
        COUNT(CASE WHEN risk_category != 'OPERATIONAL' THEN 1 END) AS high_risk_count
    FROM filings
    WHERE filing_date >= DATEADD(day, -30, CURRENT_DATE())
    GROUP BY ticker
),

latest_earnings AS (
    SELECT
        ticker,
        call_date,
        sentiment_score,
        speaker_role,
        ROW_NUMBER() OVER (PARTITION BY ticker ORDER BY call_date DESC) AS rn
    FROM earnings
    WHERE speaker_role = 'CEO'
),

latest_prices AS (
    SELECT
        ticker,
        price_date,
        close_price,
        ma_20d,
        ma_50d,
        volatility_20d,
        sharpe_like_ratio
    FROM prices
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ticker ORDER BY price_date DESC) = 1
)

SELECT
    COALESCE(p.ticker, le.ticker, rc.ticker) AS ticker,
    p.close_price,
    p.ma_20d,
    p.ma_50d,
    ROUND(p.volatility_20d * 100, 2) AS volatility_pct,
    ROUND(p.sharpe_like_ratio, 2) AS sharpe_ratio,
    le.sentiment_score AS ceo_sentiment,
    rc.total_risk_flags,
    rc.high_risk_count,

    -- Composite research signal
    ROUND(
        COALESCE(p.sharpe_like_ratio, 0) * 0.3 +
        COALESCE(le.sentiment_score, 0) * 25 * 0.4 +
        (1 - COALESCE(rc.high_risk_count, 0) * 0.1) * 10 * 0.3,
        2
    ) AS composite_signal_score,

    CASE
        WHEN COALESCE(le.sentiment_score, 0) > 0.5
            AND COALESCE(rc.high_risk_count, 0) <= 1
            AND COALESCE(p.sharpe_like_ratio, 0) > 0
        THEN 'BULLISH'
        WHEN COALESCE(le.sentiment_score, 0) < -0.3
            OR COALESCE(rc.high_risk_count, 0) >= 3
        THEN 'BEARISH'
        ELSE 'NEUTRAL'
    END AS signal_direction,

    CURRENT_TIMESTAMP() AS signal_generated_at

FROM latest_prices p
LEFT JOIN latest_earnings le ON p.ticker = le.ticker AND le.rn = 1
LEFT JOIN risk_counts rc ON p.ticker = rc.ticker
