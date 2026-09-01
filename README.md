# Investment Diligence & Financial Data Intelligence Platform

Python, SQL, MySQL, Power BI, FastAPI, LangChain + Groq

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
4. **API layer (FastAPI + LangChain/Groq)** — a thin read-only API over the same
   MySQL data: two endpoints that expose metrics and anomaly flags as JSON, and
   one LLM-powered endpoint that turns already-flagged anomalies into a
   plain-English explanation.

```
investment-diligence-platform/
├── README.md
├── .gitignore
├── etl/
│   └── etl_pipeline.ipynb        <- open this in Google Colab
├── sql/
│   ├── 01_schema.sql             <- run first, in MySQL Workbench
│   ├── 02_load_data.sql          <- loads the CSVs the notebook produces
│   └── 03_anomaly_detection.sql  <- joins / CTEs / window functions
├── data/                         <- CSVs land here after step 1
├── powerbi/
│   ├── PortfolioOverview.pbix
│   └── README.md                 <- dashboard build guide
├── images/
└── api/
    ├── __init__.py
    ├── main.py                   <- FastAPI app, 3 endpoints
    ├── db.py                     <- MySQL connection helper
    └── llm.py                    <- LangChain + Groq anomaly explainer
```

---

## Step 1 — ETL in Colab (no installs needed)

1. Upload `etl/etl_pipeline.ipynb` to Google Colab (**File → Upload notebook**),
   or push it to GitHub and open it via **File → Open notebook → GitHub** in Colab.
2. Get a free Alpha Vantage API key: https://www.alphavantage.co/support/#api-key
   (takes 20 seconds, no card needed).
3. Run the cells top to bottom. The notebook will prompt you for:
   - Your Alpha Vantage API key
   - A "User-Agent" string for SEC EDGAR (SEC requires `Your Name your@email.com`
     on every request — it's a courtesy policy, not a real signup)
   - The list of tickers you want to analyze (a default list of 5 is provided)
4. At the end, the notebook writes 4 CSVs and gives you a download button:
   - `companies.csv`
   - `financial_statements.csv`
   - `stock_prices.csv`
   - `reconciliation_log.csv`

Alpha Vantage's free tier is rate-limited (5 calls/minute, 25/day) — the notebook
already paces its requests to respect that.

## Step 2 — MySQL (MySQL Workbench only, no config files)

1. Open MySQL Workbench, connect to your local instance.
2. Open and run `sql/01_schema.sql`. This creates an `investment_diligence`
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
   cross-source discrepancy flags, joined back to company info. It also
   creates `v_company_flag_summary`, the view the API layer reads from.

## Step 3 — Power BI

See `powerbi/README.md`. One honest caveat: **building the actual dashboard
requires Power BI Desktop** (or the Power BI web service) — that's the one
piece of this project that isn't scriptable. Everything else (queries, DAX
measures, layout plan) is written out for you in that README.

## Step 4 — API layer (FastAPI + LangChain/Groq)

A thin read-only layer over the same `investment_diligence` MySQL database.
It does **not** modify the ETL, SQL, or Power BI pieces above, and it never
writes back to MySQL.

### What it adds

- `GET /company/{ticker}/anomalies` — returns anomaly flags for a ticker from
  `v_company_flag_summary`. Unknown ticker → `404`. Zero flags is a valid
  result → `200 []`.
- `GET /company/{ticker}/metrics` — returns yearly financials for a ticker
  from `financial_statements`. Unknown ticker → `404`.
- `POST /company/{ticker}/explain-anomalies` — fetches that ticker's anomaly
  rows and asks an LLM (via LangChain + Groq) to explain them in plain
  English. If there are zero flags, it returns a canned message and skips
  the LLM call entirely. Response shape:

  ```json
  {
    "ticker": "MSFT",
    "explanation": "...",
    "flags_considered": [ ... ]
  }
  ```

  This is **not RAG** — there's no retrieval, vector store, or embeddings.
  The "grounding" is just the structured anomaly rows already computed by
  `03_anomaly_detection.sql`, formatted directly into the prompt.

### Setup

```bash
cd api/..                      # repo root
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file in the repo root (gitignored, never commit this):

```
DB_HOST=<your MySQL host>
DB_USER=<your MySQL user>
DB_PASSWORD=<your MySQL password>
DB_NAME=investment_diligence
GROQ_API_KEY=<your Groq API key>
```

> **Note on WSL2 + Windows MySQL:** if MySQL runs on Windows while your
> project lives in WSL2, `localhost` won't resolve to the Windows host from
> inside WSL2. Use the Windows vEthernet (WSL) adapter IP instead (find it
> via `ipconfig` on Windows), and make sure your MySQL user has a grant for
> that subnet, e.g. `GRANT ALL ON investment_diligence.* TO 'user'@'172.x.%'`.

### Run it

```bash
uvicorn api.main:app --reload
```

Then try it against a ticker that exists in your loaded data:

```bash
curl -s http://127.0.0.1:8000/company/MSFT/metrics
curl -s http://127.0.0.1:8000/company/MSFT/anomalies
curl -s -X POST http://127.0.0.1:8000/company/MSFT/explain-anomalies
```

And confirm 404 behavior with a ticker that doesn't exist:

```bash
curl -i http://127.0.0.1:8000/company/ZZZZ/metrics
```

### Error handling

- Unknown ticker → `404`
- Empty/whitespace ticker path parameter → `400`
- Database connection failure → `500`, with a generic message — no
  credentials, hostnames, or connection strings are ever leaked in the
  response.

### Out of scope (by design)

No authentication, rate limiting, caching, or connection pooling. No new
frontend. No vector store, embeddings, RAG, or agent framework. No second
cloud/LLM provider. No ORM beyond the parameterized queries in `api/db.py`.

---

## Pushing to GitHub

This folder is a normal repo layout. Add a `.gitignore` covering at least:

```
venv/
__pycache__/
*.pyc
.env
data/*.csv
!data/.gitkeep
```

`data/*.csv` is excluded since re-running the ETL notebook regenerates it,
and `.env` is excluded since it holds real database and API credentials.
