{{ config(materialized='table') }}

WITH earnings AS (
    SELECT * FROM {{ ref('int_earnings_sentiment') }}
),

price_impact AS (
    SELECT
        ticker,
        price_date,
        daily_return_pct,
        LAG(close_price) OVER (PARTITION BY ticker ORDER BY price_date) AS prev_close
    FROM {{ ref('stg_stock_prices') }}
),

post_earnings_move AS (
    SELECT
        e.ticker,
        e.call_date,
        e.sentiment_score,
        e.company_name,
        e.quarter,
        e.fiscal_year,
        AVG(p.daily_return_pct) AS avg_5d_return,
        MAX(ABS(p.daily_return_pct)) AS max_daily_move
    FROM earnings e
    LEFT JOIN price_impact p
        ON e.ticker = p.ticker
        AND p.price_date BETWEEN e.call_date AND DATEADD(day, 5, e.call_date)
    GROUP BY 1, 2, 3, 4, 5, 6
)

SELECT
    ticker,
    company_name,
    quarter,
    fiscal_year,
    call_date,
    ROUND(sentiment_score, 3) AS sentiment_score,
    CASE
        WHEN sentiment_score > 0.5 THEN 'Very Positive'
        WHEN sentiment_score > 0.1 THEN 'Positive'
        WHEN sentiment_score > -0.1 THEN 'Neutral'
        WHEN sentiment_score > -0.5 THEN 'Negative'
        ELSE 'Very Negative'
    END AS sentiment_label,
    COALESCE(ROUND(avg_5d_return * 100, 2), 0) AS post_earnings_5d_return_pct,
    COALESCE(ROUND(max_daily_move * 100, 2), 0) AS max_daily_move_pct,
    CASE
        WHEN sentiment_score > 0.3 AND avg_5d_return > 0.01 THEN 'Accurate Positive'
        WHEN sentiment_score < -0.3 AND avg_5d_return < -0.01 THEN 'Accurate Negative'
        WHEN SIGN(sentiment_score) = SIGN(avg_5d_return) THEN 'Directionally Correct'
        ELSE 'Contrary Signal'
    END AS prediction_accuracy
FROM post_earnings_move
ORDER BY call_date DESC
