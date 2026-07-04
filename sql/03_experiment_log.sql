-- =========================================================
-- 03_experiment_log.sql
-- Experiment logging framework for adaptive indexing experiments
-- Author: Venkata Charan Sai (Adaptive Optimization, Implementation
-- & Risk Analysis Lead)
--
-- Tables:
--   experiment_run    - one row per test run (baseline vs adaptive)
--   query_sample      - one row per query executed during a run
--   adaptive_action    - one row per index create/drop taken by the
--                        adaptive engine in response to query patterns
-- =========================================================

-- Drop in dependency order so this script is safely re-runnable
DROP TABLE IF EXISTS adaptive_action CASCADE;
DROP TABLE IF EXISTS query_sample CASCADE;
DROP TABLE IF EXISTS experiment_run CASCADE;

-- ---------------------------------------------------------
-- experiment_run: top-level record for a single test run
-- ---------------------------------------------------------
CREATE TABLE experiment_run (
    run_id          SERIAL PRIMARY KEY,
    run_label       TEXT NOT NULL,                 -- e.g. 'baseline_static', 'adaptive_v1'
    strategy        TEXT NOT NULL CHECK (strategy IN ('baseline', 'adaptive')),
    description     TEXT,
    started_at      TIMESTAMP NOT NULL DEFAULT now(),
    ended_at        TIMESTAMP,
    total_queries   INTEGER DEFAULT 0,
    notes           TEXT
);

COMMENT ON TABLE experiment_run IS
    'One row per experiment execution (baseline or adaptive indexing strategy).';

-- ---------------------------------------------------------
-- query_sample: one row per query executed within a run
-- ---------------------------------------------------------
CREATE TABLE query_sample (
    query_id            SERIAL PRIMARY KEY,
    run_id              INTEGER NOT NULL REFERENCES experiment_run(run_id) ON DELETE CASCADE,
    query_label         TEXT,                      -- e.g. 'Q1_sales_by_region'
    query_text          TEXT NOT NULL,
    executed_at         TIMESTAMP NOT NULL DEFAULT now(),
    planning_time_ms    NUMERIC(10,3),
    execution_time_ms   NUMERIC(10,3),
    rows_returned       INTEGER,
    used_index          TEXT                       -- name of index used, if any (from EXPLAIN)
);

COMMENT ON TABLE query_sample IS
    'One row per query executed during an experiment run, with timing captured from EXPLAIN ANALYZE.';

CREATE INDEX idx_query_sample_run_id ON query_sample(run_id);

-- ---------------------------------------------------------
-- adaptive_action: index create/drop actions taken by the
-- adaptive engine in response to observed query patterns
-- ---------------------------------------------------------
CREATE TABLE adaptive_action (
    action_id           SERIAL PRIMARY KEY,
    run_id              INTEGER NOT NULL REFERENCES experiment_run(run_id) ON DELETE CASCADE,
    triggered_by_query  INTEGER REFERENCES query_sample(query_id) ON DELETE SET NULL,
    action_type         TEXT NOT NULL CHECK (action_type IN ('CREATE_INDEX', 'DROP_INDEX')),
    target_table        TEXT NOT NULL,
    target_columns      TEXT NOT NULL,
    index_name          TEXT,
    reason              TEXT,                      -- e.g. 'high frequency filter on item_key'
    executed_at         TIMESTAMP NOT NULL DEFAULT now(),
    execution_time_ms   NUMERIC(10,3)
);

COMMENT ON TABLE adaptive_action IS
    'One row per adaptive index action (create/drop) taken during an adaptive experiment run.';

CREATE INDEX idx_adaptive_action_run_id ON adaptive_action(run_id);

-- ---------------------------------------------------------
-- Sanity check output
-- ---------------------------------------------------------
\echo 'Experiment logging tables created: experiment_run, query_sample, adaptive_action'