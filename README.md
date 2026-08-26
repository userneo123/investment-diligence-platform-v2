# Investment Diligence & Financial Data Intelligence Platform

Python, SQL, MySQL, Power BI

## What this project does

1. **ETL (Python, runs in Google Colab)** — pulls company financial data from
   **SEC EDGAR** (`companyfacts` API) and **Alpha Vantage** (fundamentals + prices)
   for a list of tickers, reconciles the two sources against each other, and
   exports clean CSVs.
2. **MySQL (runs in MySQL Workbench, no extra installs)** — a normalized schema
   with validation constraints, a load step for the CSVs, and a SQL script that
   flags anomalies using joins, CTEs, and window functions.
3. **Power BI** — a dashboard on top of the MySQL tables showing flagged metrics
   and company-level financial health.

```
finance-diligence-platform/
├── README.md
├── etl/
│   └── etl_pipeline.ipynb        <- open this in Google Colab
├── sql/
│   ├── 01_schema.sql             <- run first, in MySQL Workbench
│   ├── 02_load_data.sql          <- loads the CSVs the notebook produces
│   └── 03_anomaly_detection.sql  <- joins / CTEs / window functions
├── data/                         <- CSVs land here after step 1
└── powerbi/
    └── README.md                 <- dashboard build guide
```

## Step 1 — ETL in Colab (no installs needed)

1. Upload `etl/etl_pipeline.ipynb` to Google Colab (**File → Upload notebook**),
   or push it to GitHub and open it via **File → Open notebook → GitHub** in Colab.
2. Get a free Alpha Vantage API key: https://www.alphavantage.co/support/#api-key
   (takes 20 seconds, no card needed).
3. Run the cells top to bottom. The notebook will prompt you for:
   - Your Alpha Vantage API key
   - A "User-Agent" string for SEC EDGAR (SEC requires `Your Name your@email.com`
     on every request — it's a courtesy policy, not a real signup)
   - The list of tickers you want to analyze (a default list of 8 is provided)
4. At the end, the notebook writes 4 CSVs and gives you a download button:
   - `companies.csv`
   - `financial_statements.csv`
   - `stock_prices.csv`
   - `reconciliation_log.csv`

Alpha Vantage's free tier is rate-limited (5 calls/minute, 25/day) — the notebook
already paces its requests to respect that, so a run with ~8 tickers takes a
few minutes and won't get you blocked.

## Step 2 — MySQL (MySQL Workbench only, no config files)

1. Open MySQL Workbench, connect to your local instance.
2. Open and run `sql/01_schema.sql`. This creates a `investment_diligence`
   database with 5 tables and validation constraints (CHECK constraints,
   foreign keys, NOT NULL).
3. Load the 4 CSVs from Step 1 using Workbench's built-in GUI importer —
   no `LOAD DATA INFILE` permissions or config needed:
   - Right-click each table in the schema tree → **Table Data Import Wizard**
   - Point it at the matching CSV from `data/`
   - Import order matters: `companies` → `financial_statements` →
     `stock_prices` → `reconciliation_log` (foreign keys depend on `companies`
     existing first)
   - `sql/02_load_data.sql` is included as a scripted alternative if you'd
     rather use `LOAD DATA INFILE` instead of the wizard — it's optional.
4. Open and run `sql/03_anomaly_detection.sql`. This is the analytical core:
   CTEs + window functions (`LAG`, `AVG() OVER`, `STDDEV() OVER`) to compute
   YoY growth, margin z-scores, balance-sheet-equation checks, and
   cross-source discrepancy flags, joined back to company info.

## Step 3 — Power BI

See `powerbi/README.md`. One honest caveat: **building the actual dashboard
requires Power BI Desktop** (or the Power BI web service) — that's the one
piece of this project that isn't scriptable, since Power BI files (`.pbix`)
aren't plain text and there's no meaningful headless/no-install path to a real
Power BI report. Everything else (queries, DAX measures, layout plan) is
written out for you in that README so the build itself is just pointing
Power BI at your MySQL tables and dragging in the fields.

## Pushing to GitHub

This folder is a normal repo layout — `git init`, add a `.gitignore` for
`data/*.csv` if you don't want raw pulled data in the repo (recommended,
since re-running the notebook regenerates it), commit, and push.
