{{ config(materialized='table') }}

SELECT
    filing_id,
    ticker,
    filing_type,
    filing_date,
    item_type,
    risk_category,
    sentiment_polarity,

    {# On paid Enterprise, use Cortex embeddings:
       {{ cortex_embeddings('section_text', 'snowflake-arctic-embed-m') }} AS embedding_vector #}

    -- Simulated embedding for trial (5-dimensional vector)
    ARRAY_CONSTRUCT(
        ROUND((MD5(filing_id)::FLOAT / 1e18 - 0.5) * 2, 6),
        ROUND((SHA2(filing_id, 256)::FLOAT / 1e18 - 0.5) * 2, 6),
        ROUND((MD5(CONCAT(filing_id, 'x'))::FLOAT / 1e18 - 0.5) * 2, 6),
        ROUND((SHA2(CONCAT(filing_id, 'y'), 256)::FLOAT / 1e18 - 0.5) * 2, 6),
        ROUND((MD5(CONCAT(filing_id, 'z'))::FLOAT / 1e18 - 0.5) * 2, 6)
    ) AS embedding_vector,

    CURRENT_TIMESTAMP() AS _embedded_at
FROM {{ ref('int_filing_classifications') }}
WHERE risk_category != 'OPERATIONAL'
