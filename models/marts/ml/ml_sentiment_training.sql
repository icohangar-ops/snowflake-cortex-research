{{ config(materialized='table') }}

WITH earnings_sentiment AS (
    SELECT * FROM {{ ref('int_earnings_sentiment') }}
),

price_outcomes AS (
    SELECT
        e.ticker,
        e.call_date AS event_date,
        e.sentiment_score,
        AVG(p.daily_return_pct) AS subsequent_5d_return,
        AVG(p.daily_return_pct) AS subsequent_10d_return,
        MAX(ABS(p.daily_return_pct)) AS max_abs_return
    FROM earnings_sentiment e
    JOIN {{ ref('stg_stock_prices') }} p
        ON e.ticker = p.ticker
        AND p.price_date > e.call_date
        AND p.price_date <= DATEADD(day, 10, e.call_date)
    GROUP BY 1, 2, 3
)

SELECT
    event_date,
    ticker,
    ROUND(sentiment_score, 4) AS sentiment_feature,
    ROUND(COALESCE(subsequent_5d_return, 0), 6) AS label_5d_return,
    ROUND(COALESCE(subsequent_10d_return, 0), 6) AS label_10d_return,
    CASE WHEN subsequent_5d_return > 0.005 THEN 1 ELSE 0 END AS label_positive_5d,
    CASE WHEN subsequent_5d_return < -0.005 THEN 1 ELSE 0 END AS label_negative_5d,
    CURRENT_TIMESTAMP() AS _training_snapshot_at
FROM price_outcomes
