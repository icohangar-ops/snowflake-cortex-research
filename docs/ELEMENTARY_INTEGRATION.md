# Elementary Data Observability for CortexEdge

## Overview

[Elementary](https://docs.elementary-data.com/) provides dbt-native data observability with built-in freshness checks, volume monitoring, schema change detection, and custom anomaly detection — all running inside your Snowflake warehouse.

This integration adds observability to CortexEdge's financial NLP pipeline, covering the full dbt model hierarchy: staging → intermediate → marts.

---

## Why Elementary for CortexEdge?

CortexEdge processes SEC filings, earnings calls, and market data through Cortex AI. Data quality issues at any layer cascade into incorrect sentiment signals, risk classifications, and composite research scores. Elementary catches these problems before downstream consumers see them.

| Elementary Feature | CortexEdge Use Case |
|--------------------|---------------------|
| **Freshness monitoring** | Detect stale raw feeds (earnings calls, SEC filings, stock prices) |
| **Volume anomaly detection** | Alert on sudden drops in SEC filing ingestion (e.g., missing ticker data) |
| **Schema change detection** | Catch upstream feed schema drift in raw tables |
| **Column-level anomalies** | Detect sentiment scores outside expected bounds, embedding dimension changes |
| **Custom SQL checks** | Validate composite signal score distribution, risk flag counts |

---

## Installation

### 1. Add Elementary to packages.yml

```yaml
packages:
  - package: elementary-data/elementary
    version: [">=0.15.0", "<1.0.0"]
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

### 2. Install packages

```bash
dbt deps
```

### 3. Configure Elementary in dbt_project.yml

```yaml
models:
  elementary:
    +schema: elementary
```

### 4. Create a dedicated warehouse (optional)

```sql
CREATE WAREHOUSE ELEMENTARY_WH WITH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Elementary data observability queries';

GRANT USAGE ON WAREHOUSE ELEMENTARY_WH TO ROLE CORTEX_RESEARCH_ROLE;
```

### 5. Run Elementary

```bash
# Run Elementary's staging models
dbt run --select elementary

# Generate Elementary report
dbt run --select elementary.elementary.cli
```

---

## Monitored Model Layers

### Staging Models (Views)

| Model | What It Monitors |
|-------|------------------|
| `stg_earnings_calls` | Raw earnings transcript ingestion, null filtering, date range |
| `stg_sec_filings` | SEC filing extraction, section completeness |
| `stg_stock_prices` | Market data feed health, price validity |

### Intermediate Models (Tables/Ephemeral)

| Model | What It Monitors |
|-------|------------------|
| `int_earnings_sentiment` | Cortex AI sentiment output distribution, summary generation |
| `int_filing_classifications` | Risk classification distribution, sentiment polarity balance |
| `int_price_metrics` | Moving average calculations, volatility bounds, ratio validity |

### Mart Models (Tables)

| Model | What It Monitors |
|-------|------------------|
| `mart_research_signals` | Composite signal score distribution, signal direction balance |
| `mart_earnings_summary` | Post-earnings price reaction, prediction accuracy rates |
| `mart_filing_dashboard` | Risk level distribution, filing coverage by ticker |
| `ml_filing_embeddings` | Embedding dimension consistency, non-operational filing coverage |
| `ml_sentiment_training` | Training label distribution, label balance for ML |

---

## Snowflake-Specific Monitoring

### Dynamic Tables

CortexEdge uses Dynamic Tables for auto-refreshing materialized views. Monitor their health:

```sql
-- Check Dynamic Table refresh status
SELECT
  name,
  target_lag,
  state,
  last_refresh_time,
  seconds_since_last_refresh,
  refresh_reason
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY
WHERE name IN ('MART_RESEARCH_SIGNALS', 'MART_EARNINGS_SUMMARY', 'MART_FILING_DASHBOARD')
ORDER BY last_refresh_time DESC;
```

### Streams (CDC Pipeline)

Monitor the streams that feed the dbt pipeline:

```sql
-- Stream freshness and latency
SELECT
  s.name AS stream_name,
  s.table_name AS source_table,
  s.created_on,
  s.mode,
  SUM(t.rows_inserted) AS rows_inserted,
  SUM(t.rows_updated) AS rows_updated,
  SUM(t.rows_deleted) AS rows_deleted,
  MAX(t.insertion_time) AS last_insertion
FROM CORTEX_RESEARCH.INFORMATION_SCHEMA.STREAMS s
JOIN TABLE(INFORMATION_SCHEMA.CHANGE_TRACKING_TABLES()) t
  ON s.name = t.stream_name
GROUP BY 1, 2, 3, 4
ORDER BY last_insertion DESC;
```

### Tasks

Monitor scheduled tasks that trigger Cortex AI processing:

```sql
-- Task execution history
SELECT
  task_name,
  completed_time,
  state,
  error_code,
  error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE task_name LIKE '%CORTEX_RESEARCH%'
  AND completed_time >= DATEADD(hour, -24, CURRENT_DATE())
ORDER BY completed_time DESC;
```

---

## Alert Rules for Financial NLP Pipeline

### Critical Alerts (Immediate)

| Alert | Condition | Impact |
|-------|-----------|--------|
| **Raw feed stale** | `source_freshness` > 6 hours for any raw table | NLP pipeline producing stale signals |
| **Sentiment score anomaly** | Mean sentiment outside [-0.8, 0.8] | Cortex AI output degraded |
| **Embedding dimension drift** | `ARRAY_SIZE(embedding_vector) != 5` | Similarity search broken |
| **Zero new filings** | `COUNT(*) = 0` on new filings in 48h | Upstream data collection failure |

### Warning Alerts (Review)

| Alert | Condition | Impact |
|-------|-----------|--------|
| **Volume drop** | Row count < 50% of 7-day average | Partial data loss in feed |
| **Risk flag surge** | `risk_flagged_filings > 60%` | Potential data quality or market event |
| **Prediction accuracy drop** | `prediction_accuracy = 'Contrary Signal'` > 30% | Sentiment model degraded |
| **Null sentiment > 5%** | `sentiment_score IS NULL` > 5% of rows | Cortex AI quota or permission issue |

### Info Alerts (Monitor)

| Alert | Condition | Impact |
|-------|-----------|--------|
| **Schema change detected** | Elementary `schema_changes` | Review upstream feed changes |
| **Volume trend shift** | 30-day rolling average change > 20% | Natural or artificial trend |
| **New ticker detected** | Ticker not in historical set | Review for inclusion |

---

## Running Elementary

```bash
# Full Elementary run
dbt run --select elementary

# Run only freshness checks
dbt test --select elementary.source_freshness

# Run only anomaly detection
dbt run --select elementary.elementary_cli

# Generate HTML report
dbt run --select elementary.elementary_cli
# Open: target/elementary.html
```

---

## Integration with CortexEdge Pipeline

```
Raw Data (SEC, Earnings, Prices)
    ↓
dbt source freshness check (Elementary)
    ↓
Staging Models (Elementary monitors freshness + volume)
    ↓
Intermediate Models (Elementary monitors schema + anomalies)
    ↓
Mart Models (Elementary monitors custom business metrics)
    ↓
Elementary Report + Alerts
```

---

## References

- [Elementary Documentation](https://docs.elementary-data.com/)
- [Elementary Snowflake Integration](https://docs.elementary-data.com/guides/modules/elementary-in-cloud/quickstart)
- [dbt Source Freshness](https://docs.getdbt.com/docs/deploy/source-freshness)
