{{ config(materialized='view') }}

SELECT
    call_id,
    UPPER(TRIM(ticker)) AS ticker,
    company_name,
    call_date,
    call_type,
    quarter,
    fiscal_year,
    TRIM(speaker_name) AS speaker_name,
    TRIM(speaker_role) AS speaker_role,
    TRIM(transcript_text) AS transcript_text,
    COALESCE(confidence_score, 0.85) AS confidence_score,
    _loaded_at
FROM {{ source('raw', 'earnings_calls') }}
WHERE call_date >= DATEADD(year, -3, CURRENT_DATE())
  AND transcript_text IS NOT NULL
  AND LENGTH(transcript_text) > 50
