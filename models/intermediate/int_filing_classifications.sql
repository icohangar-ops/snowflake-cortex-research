{{ config(materialized='table') }}

SELECT
    f.filing_id,
    f.ticker,
    f.company_name,
    f.filing_type,
    f.filing_date,
    f.fiscal_year,
    f.fiscal_quarter,
    f.filing_title,
    f.section_text,
    f.item_type,

    -- Risk detection using keyword analysis (Cortex equivalent on paid)
    CASE
        WHEN f.section_text LIKE '%litigation%' OR f.section_text LIKE '%lawsuit%' THEN 'LITIGATION_RISK'
        WHEN f.section_text LIKE '%impairment%' OR f.section_text LIKE '%write-down%' THEN 'IMPAIRMENT_RISK'
        WHEN f.section_text LIKE '%competition%' OR f.section_text LIKE '%market share%' THEN 'COMPETITIVE_RISK'
        WHEN f.section_text LIKE '%regulation%' OR f.section_text LIKE '%compliance%' THEN 'REGULATORY_RISK'
        WHEN f.section_text LIKE '%cybersecurity%' OR f.section_text LIKE '%data breach%' THEN 'CYBER_RISK'
        WHEN f.section_text LIKE '%supply chain%' OR f.section_text LIKE '%disruption%' THEN 'SUPPLY_CHAIN_RISK'
        ELSE 'OPERATIONAL'
    END AS risk_category,

    -- Sentiment polarity
    CASE
        WHEN f.section_text LIKE '%substantial%' AND f.section_text LIKE '%risk%' THEN 'NEGATIVE'
        WHEN f.section_text LIKE '%may adversely%' THEN 'NEGATIVE'
        WHEN f.section_text LIKE '%growth%' AND f.section_text NOT LIKE '%risk%' THEN 'POSITIVE'
        WHEN f.section_text LIKE '%innovation%' THEN 'POSITIVE'
        ELSE 'NEUTRAL'
    END AS sentiment_polarity,

    LENGTH(f.section_text) AS text_length,
    ARRAY_SIZE(REGEXP_SUBSTR_ALL(f.section_text, '\\w+')) AS word_count

FROM {{ ref('stg_sec_filings') }} f
