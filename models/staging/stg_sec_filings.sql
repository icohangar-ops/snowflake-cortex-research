{{ config(materialized='view') }}

SELECT
    filing_id,
    UPPER(TRIM(ticker)) AS ticker,
    company_name,
    filing_type,
    filing_date,
    period_end_date,
    EXTRACT(YEAR FROM period_end_date) AS fiscal_year,
    EXTRACT(QUARTER FROM period_end_date) AS fiscal_quarter,
    TRIM(filing_title) AS filing_title,
    TRIM(section_text) AS section_text,
    item_type,
    pages_count,
    file_size_kb,
    _loaded_at
FROM {{ source('raw', 'sec_filings') }}
WHERE filing_date >= DATEADD(year, -3, CURRENT_DATE())
  AND section_text IS NOT NULL
