{{ config(materialized='table') }}

WITH filings AS (
    SELECT * FROM {{ ref('int_filing_classifications') }}
),

filing_summary AS (
    SELECT
        ticker,
        filing_type,
        fiscal_year,
        fiscal_quarter,
        COUNT(*) AS total_filings,
        COUNT(CASE WHEN risk_category != 'OPERATIONAL' THEN 1 END) AS risk_flagged_filings,
        COUNT(CASE WHEN sentiment_polarity = 'NEGATIVE' THEN 1 END) AS negative_sections,
        COUNT(CASE WHEN sentiment_polarity = 'POSITIVE' THEN 1 END) AS positive_sections,
        AVG(LENGTH(section_text)) AS avg_section_length
    FROM filings
    GROUP BY 1, 2, 3, 4
)

SELECT
    ticker,
    filing_type,
    fiscal_year,
    fiscal_quarter,
    total_filings,
    risk_flagged_filings,
    ROUND(risk_flagged_filings * 100.0 / NULLIF(total_filings, 0), 1) AS risk_pct,
    negative_sections,
    positive_sections,
    ROUND(avg_section_length, 0) AS avg_section_length,
    CASE
        WHEN risk_flagged_filings > total_filings * 0.4 THEN 'HIGH_RISK'
        WHEN risk_flagged_filings > total_filings * 0.2 THEN 'MEDIUM_RISK'
        ELSE 'LOW_RISK'
    END AS risk_level
FROM filing_summary
ORDER BY fiscal_year DESC, fiscal_quarter DESC
