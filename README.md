<div align="center">

# CortexEdge

**Real-time financial NLP on Snowflake.** AI-powered earnings sentiment, filing risk detection, and composite research signals — auto-refreshing via Dynamic Tables with zero-copy scenario analysis.

[![dbt](https://img.shields.io/badge/dbt-1.8+-orange)](https://docs.getdbt.com/)
[![Snowflake](https://img.shields.io/badge/Snowflake-Cortex_AI-blue)](https://www.snowflake.com/en/data-cloud/cortex/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## The Problem

Investment research teams analyze thousands of pages of SEC filings and earnings call transcripts. The work is manual, slow, and loses institutional knowledge. Existing NLP tools require moving data out of the warehouse, creating security and latency problems.

CortexEdge keeps everything inside Snowflake — using Cortex AI for NLP, Dynamic Tables for auto-refresh, and Streams & Tasks for CDC — so research signals update automatically as new filings land.

---

## What CortexEdge Does

```
SEC Filings + Earnings Calls + Market Data
    → Streams (CDC)
    → dbt Staging + Intermediate (Cortex AI Sentiment, Summarize, Embed)
    → Analytics Marts (Research Signals, Earnings Summary, Filing Dashboard)
    → Dynamic Tables (auto-refresh)
    → Zero-Copy Cloning (scenario analysis)
```

### Key Capabilities

| Feature | What It Does |
|---------|-------------|
| **AI Sentiment Analysis** | Cortex `SENTIMENT` on earnings transcripts and filing sections |
| **AI Summarization** | Cortex `SUMMARIZE` for executive summaries from lengthy docs |
| **Vector Embeddings** | Cortex `EMBED_TEXT` for semantic similarity across filings |
| **Auto-Refresh** | Dynamic Tables with configurable target lag |
| **CDC Pipeline** | Streams + Tasks eliminate full-refresh ETL (up to 90% compute savings) |
| **Scenario Analysis** | Zero-Copy Cloning for instant stress testing |
| **Enterprise Security** | Dynamic Data Masking + Row Access Policies |

---

## What Makes This Different

Other Snowflake demos are **static** — you run `dbt run` and get a table. CortexEdge is **live**:

- Dynamic Tables auto-refresh when new SEC filings land
- Streams capture changes incrementally (no full refresh)
- Zero-Copy Cloning lets you stress-test scenarios in seconds
- Everything stays in Snowflake — no data movement, no external NLP APIs

---

## Quick Start

```bash
git clone https://github.com/icohangar-ops/cortexedge.git
cd cortexedge
dbt deps

# Configure Snowflake connection
export SNOWFLAKE_ACCOUNT="your-account-id"
export SNOWFLAKE_USER="your-username"
export SNOWFLAKE_PASSWORD="your-password"

# Set up infrastructure (requires ACCOUNTADMIN)
# Run scripts/setup_snowflake.sql in Snowflake Worksheet

# Load seed data
dbt seed --full-refresh

# Run all models
dbt run

# Run tests
dbt test

# Generate docs
dbt docs generate && dbt docs serve
```

---

## Sample Queries

### Top 10 Bullish Signals

```sql
SELECT ticker, close_price, ceo_sentiment, composite_signal_score, signal_direction
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS
WHERE signal_direction = 'BULLISH'
ORDER BY composite_signal_score DESC
LIMIT 10;
```

### Post-Earnings Price Reaction

```sql
SELECT ticker, sentiment_label, post_earnings_5d_return_pct, prediction_accuracy
FROM CORTEX_RESEARCH.ANALYTICS.MART_EARNINGS_SUMMARY
WHERE prediction_accuracy IN ('Accurate Positive', 'Accurate Negative')
ORDER BY ABS(post_earnings_5d_return_pct) DESC;
```

### Similarity Search

```sql
-- Find filings similar to a target filing
SELECT a.filing_id, a.ticker, a.risk_category,
  VECTOR_DOT_PRODUCT(a.embedding_vector, (
    SELECT embedding_vector FROM CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS
    WHERE filing_id = 'SF-001'
  )) / (VECTOR_NORM(a.embedding_vector) * VECTOR_NORM((
    SELECT embedding_vector FROM CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS
    WHERE filing_id = 'SF-001'
  ))) AS cosine_similarity
FROM CORTEX_RESEARCH.ML.ML_FILING_EMBEDDINGS a
WHERE a.filing_id != 'SF-001'
ORDER BY cosine_similarity DESC LIMIT 10;
```

---

## Scenario Analysis with Zero-Copy Cloning

```sql
-- Clone the entire database for a stress test (instant, no data movement)
CREATE DATABASE CORTEX_RESEARCH_STRESS_TEST CLONE CORTEX_RESEARCH;

-- Simulate 40% sentiment degradation
UPDATE STAGING.INT_EARNINGS_SENTIMENT
SET sentiment_score = sentiment_score * 0.6 - 0.2;

-- Compare baseline vs stress test
SELECT a.ticker, a.composite_signal_score AS baseline,
       b.composite_signal_score AS stress_test,
       a.composite_signal_score - b.composite_signal_score AS delta
FROM CORTEX_RESEARCH.ANALYTICS.MART_RESEARCH_SIGNALS a
JOIN CORTEX_RESEARCH_STRESS_TEST.ANALYTICS.MART_RESEARCH_SIGNALS b
  ON a.ticker = b.ticker;

-- Drop when done (no cost)
DROP DATABASE CORTEX_RESEARCH_STRESS_TEST;
```

---

## Tech Stack

| Component | Purpose |
|-----------|---------|
| Snowflake Cortex AI | Sentiment, Summarize, Embed functions |
| dbt Core | Version-controlled SQL transformations |
| Dynamic Tables | Auto-refreshing materialized views |
| Streams & Tasks | CDC + scheduled ELT |
| Zero-Copy Cloning | Instant scenario analysis |
| Dynamic Data Masking | Role-based column masking |
| Row Access Policies | Sector-based row access |

---

## Warehouse Strategy

| Warehouse | Size | Use Case | Auto-Suspend |
|---|---|---|---|
| `CORTEX_WH` | X-Small | Cortex AI, Dynamic Tables, ML | 60s |
| `DBT_WH` | X-Small | dbt transforms, Tasks | 60s |

---

## Project Structure

```
cortexedge/
├── dbt_project.yml
├── models/
│   ├── sources.yml
│   ├── staging/          # stg_earnings_calls, stg_sec_filings, stg_stock_prices
│   ├── intermediate/     # int_earnings_sentiment, int_filing_classifications, int_price_metrics
│   └── marts/
│       ├── analytics/    # mart_research_signals, mart_earnings_summary, mart_filing_dashboard
│       └── ml/           # ml_filing_embeddings, ml_sentiment_training
├── macros/               # Cortex AI wrappers (sentiment, summarize, embeddings)
├── seeds/                # Sample data (earnings, filings, prices)
├── scripts/              # Setup SQL, Dynamic Tables DDL, security policies
└── tests/                # dbt tests
```

---

## License

MIT. See [`LICENSE`](./LICENSE).
