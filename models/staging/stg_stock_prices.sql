{{ config(materialized='view') }}

SELECT
    price_id,
    UPPER(TRIM(ticker)) AS ticker,
    price_date,
    open_price,
    high_price,
    low_price,
    close_price,
    adj_close_price,
    volume,
    (close_price - open_price) / NULLIF(open_price, 0) AS daily_return_pct,
    volume * close_price AS dollar_volume
FROM {{ source('raw', 'stock_prices') }}
WHERE price_date >= DATEADD(year, -3, CURRENT_DATE())
