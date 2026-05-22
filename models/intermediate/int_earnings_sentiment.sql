{{ config(materialized='table') }}

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

    {# Cortex AI sentiment analysis (available on paid Enterprise)
       To enable on paid: {{ cortex_sentiment('transcript_text', var('cortex_model')) }} #}

    -- Simulated sentiment for trial/demo
    CASE
        WHEN e.transcript_text LIKE '%record revenue%' THEN 0.85
        WHEN e.transcript_text LIKE '%exceeded expectations%' THEN 0.92
        WHEN e.transcript_text LIKE '%headwinds%' THEN -0.35
        WHEN e.transcript_text LIKE '%challenging environment%' THEN -0.55
        WHEN e.transcript_text LIKE '%strong growth%' THEN 0.78
        WHEN e.transcript_text LIKE '%margin pressure%' THEN -0.42
        WHEN e.transcript_text LIKE '%outlook positive%' THEN 0.71
        WHEN e.transcript_text LIKE '%uncertain%' THEN -0.20
        ELSE (ABS(MD5(e.call_id)) % 100 - 50) / 100.0
    END AS sentiment_score,

    -- Summary using Cortex (simulated)
    CASE
        WHEN LENGTH(e.transcript_text) > 200 THEN
            CONCAT('Key themes: ',
                CASE
                    WHEN e.transcript_text LIKE '%AI%' THEN 'AI strategy, '
                    ELSE ''
                END,
                CASE
                    WHEN e.transcript_text LIKE '%cloud%' THEN 'Cloud growth, '
                    ELSE ''
                END,
                CASE
                    WHEN e.transcript_text LIKE '%margin%' THEN 'Margin trends, '
                    ELSE ''
                END,
                CASE
                    WHEN e.transcript_text LIKE '%guidance%' THEN 'Forward guidance discussed'
                    ELSE 'Operational review'
                END,
                '. Management expressed ',
                CASE
                    WHEN e.transcript_text LIKE '%record revenue%'
                        OR e.transcript_text LIKE '%exceeded expectations%'
                        OR e.transcript_text LIKE '%strong growth%' THEN 'optimism'
                    WHEN e.transcript_text LIKE '%headwinds%'
                        OR e.transcript_text LIKE '%challenging environment%'
                        OR e.transcript_text LIKE '%margin pressure%' THEN 'caution'
                    ELSE 'measured confidence'
                END,
                ' about forward outlook.'
            )
        ELSE 'Brief commentary segment'
    END AS ai_summary

FROM {{ ref('stg_earnings_calls') }} e
