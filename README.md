# Adaptive Global Sales Data Warehouse

A PostgreSQL 16 data warehouse that studies whether **workload-aware adaptive
optimization** (runtime index creation + partition strategy) beats a **static**
physical design when OLAP query patterns shift and ETL keeps writing rows
concurrently.

This repo is the implementation of the IEEE proposal *"Global Sales Data
Warehouse for Adaptive Analytical Query Optimization"* (COMP 8157, University of
Windsor).

## The core experiment

Build two systems on the same star schema:

1. **Static** — indexes set once, never changed (the control group).
2. **Adaptive** — a closed loop watches `pg_stat_statements`, detects hot access
   paths, and creates/drops indexes at runtime with safety guards.

Then run **12 configurations** (3 workload types × 4 ETL ingestion rates) against
both and compare latency, index usage, and plan-regression counts.

| | Product-centric | Customer-centric | Temporal-centric |
|---|---|---|---|
| **Zero ETL**   | C1 | C5 | C9 |
| **Low ETL**    | C2 | C6 | C10 |
| **Medium ETL** | C3 | C7 | C11 |
| **High ETL**   | C4 | C8 | C12 |

## Architecture

```
Workload Generator ─┐
                    ├─► PostgreSQL 16 (star schema) ─► pg_stat_statements
ETL Injector ───────┘             ▲                          │
                                  │                          ▼
                          CREATE/DROP INDEX ◄──── Adaptive Engine
                          (guarded DDL)          (monitor→decide→execute)
                                                          │
                                                          ▼
                                                  experiment_log tables
                                                          │
                                                          ▼
                                                   Matplotlib charts
```

### Star schema

- `fact_sales` — central fact, **range-partitioned by year** on `date_key`.
- `dim_item` — drives the *product-centric* query phase.
- `dim_customer` — drives the *customer-centric* query phase.
- `dim_store` — regional dimension.
- `dim_date` — drives the *temporal-centric* query phase.

Synthetic data is **skewed on purpose**: sales concentrate on a few hot items
and customers (Zipf) and on recent dates (recency). That skew is exactly what
makes adaptive indexing worth studying.

## Quick start

### Option A — Docker (recommended for the team)

```bash
cp .env.example .env
pip install -r requirements.txt
make db-up      # start Postgres 16 with pg_stat_statements preloaded
make setup      # schema + baseline indexes + log tables + data load
make psql       # poke around
```

### Option B — existing local Postgres 16

```bash
pip install -r requirements.txt
# ensure pg_stat_statements is in shared_preload_libraries and DB restarted
createdb salesdw   # (and a 'wh' role, or edit .env)
make setup
```

## Project layout

```
adaptive-warehouse/
├── docker-compose.yml         # Postgres 16 + pg_stat_statements
├── Makefile                   # make db-up / setup / load / psql ...
├── requirements.txt
├── .env.example
├── sql/
│   ├── 01_schema.sql          # star schema (partitioned fact table)
│   ├── 02_baseline_indexes.sql# STATIC control-group indexes
│   └── 03_experiment_log.sql  # run / query_sample / adaptive_action tables
├── src/
│   ├── config.py              # connection + scale + experiment matrix + tuning
│   ├── db.py                  # psycopg2 helpers
│   ├── data_gen/generate.py   # ✅ synthetic TPC-DS-shaped data loader
│   ├── workload/              # ⏳ Phase 2: query pools + generator
│   ├── etl/                   # ⏳ Phase 2: incremental ETL injector
│   ├── adaptive/              # ⏳ Phase 3: monitor / decision / executor
│   └── harness/               # ⏳ Phase 4: run the 12-config matrix
└── analysis/                  # ⏳ Phase 4: Matplotlib comparison charts
```

## Roadmap

- [x] **Phase 1** — Environment, star schema, baseline indexes, log tables, data loader.
- [ ] **Phase 2** — Workload generator (3 query pools) + concurrent ETL injector.
- [ ] **Phase 3** — Adaptive engine: monitor `pg_stat_statements`, decide, execute guarded DDL.
- [ ] **Phase 4** — Run the 12×2 matrix, collect logs, plot static vs adaptive.

## Notes on TPC-DS

The proposal targets TPC-DS. `dsdgen` needs a licensed download from tpc.org, so
this repo ships a self-contained synthetic generator producing TPC-DS-*shaped*
data (same star-schema roles). For the final report you can swap in real TPC-DS
data without changing the workload/ETL/adaptive code — only the loader changes.
