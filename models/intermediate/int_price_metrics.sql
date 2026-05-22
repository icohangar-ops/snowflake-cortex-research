{{ config(materialized='table') }}

WITH daily_prices AS (
    SELECT * FROM {{ ref('stg_stock_prices') }}
),

price_metrics AS (
    SELECT
        ticker,
        price_date,
        close_price,
        volume,
        dollar_volume,
        daily_return_pct,
        AVG(close_price) OVER (
            PARTITION BY ticker
            ORDER BY price_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS ma_20d,
        AVG(close_price) OVER (
            PARTITION BY ticker
            ORDER BY price_date
            ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
        ) AS ma_50d,
        STDDEV(daily_return_pct) OVER (
            PARTITION BY ticker
            ORDER BY price_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS volatility_20d
    FROM daily_prices
)

SELECT
    ticker,
    price_date,
    close_price,
    volume,
    dollar_volume,
    daily_return_pct,
    ROUND(ma_20d, 4) AS ma_20d,
    ROUND(ma_50d, 4) AS ma_50d,
    ROUND(ma_20d / NULLIF(ma_50d, 0), 6) AS ma_ratio_20_50,
    ROUND(volatility_20d, 6) AS volatility_20d,
    ROUND(daily_return_pct / NULLIF(volatility_20d, 0), 4) AS sharpe_like_ratio
FROM price_metrics
WHERE ma_50d IS NOT NULL
