# Power BI Dashboard

**Honest caveat:** this is the one piece of the project that needs real
software — Power BI files (`.pbix`) are a binary format, and there's no
meaningful headless equivalent that produces an actual dashboard artifact.
Two ways to avoid a *desktop* install if you want to:

- **Power BI web (app.powerbi.com)** — browser-only, no download, works fine
  for connecting to a database and building report visuals. Some advanced
  authoring features are Desktop-only, but everything below works in the
  browser version.
- **Power BI Desktop** — free download, most common path, if you don't mind
  the install.

Everything else here — the connection, the DAX, the layout — is written out
so the actual "build" is mechanical.

## 1. Connect to MySQL

1. Get Data → **MySQL database**
2. Server: `localhost` (or wherever your MySQL instance lives), Database:
   `investment_diligence`
3. Import these tables/views:
   - `companies`
   - `financial_statements`
   - `stock_prices`
   - `anomaly_flags`
   - `v_company_flag_summary` (the view from `03_anomaly_detection.sql`)
4. Power BI's MySQL connector needs the MySQL Connector/NET driver — if it
   prompts for that, it's the one dependency that isn't avoidable either
   (Power BI can't talk to MySQL without it).

## 2. Model relationships

Power BI should auto-detect these from the foreign keys, but confirm:

- `companies[company_id]` → `financial_statements[company_id]` (1 → many)
- `companies[company_id]` → `stock_prices[company_id]` (1 → many)
- `companies[company_id]` → `anomaly_flags[company_id]` (1 → many)

## 3. DAX measures to add

```dax
Net Margin % =
DIVIDE(SUM(financial_statements[net_income]), SUM(financial_statements[revenue]))

Revenue YoY Growth % =
VAR CurrentRevenue = SUM(financial_statements[revenue])
VAR PriorRevenue =
    CALCULATE(
        SUM(financial_statements[revenue]),
        DATEADD('financial_statements'[fiscal_year], -1, YEAR)
    )
RETURN DIVIDE(CurrentRevenue - PriorRevenue, PriorRevenue)

Total Anomaly Flags = COUNTROWS(anomaly_flags)

High Severity Flags =
CALCULATE(COUNTROWS(anomaly_flags), anomaly_flags[severity] = "HIGH")

Debt to Equity =
DIVIDE(SUM(financial_statements[total_liabilities]), SUM(financial_statements[total_equity]))
```

*(`fiscal_year` is a plain integer column, not a date — if you want `DATEADD`
to work as written, add a small calculated date column
`FYDate = DATE(financial_statements[fiscal_year], 12, 31)` and mark it as a
date table, or just swap `DATEADD` for a `LAG`-style pattern using
`CALCULATE` filtered on `fiscal_year - 1` directly.)*

## 4. Suggested dashboard layout (3 pages)

**Page 1 — Portfolio Overview**
- KPI cards: Total Companies Tracked, Total Anomaly Flags, High-Severity Flags
- Bar chart: Revenue by company, current fiscal year
- Table: `v_company_flag_summary` sorted by `total_flags_for_company`

**Page 2 — Company Deep Dive** (with a ticker slicer)
- Line chart: Revenue and Net Income by fiscal year
- Line chart: Net Margin % trend
- Line chart: Stock close price over time (from `stock_prices`)
- Card: Debt to Equity

**Page 3 — Anomaly Review**
- Table: `anomaly_flags` filtered/sorted by severity, with `flag_detail`
- Matrix: flag_type × company, values = count of flags
- Slicer: severity, flag_type, fiscal_year

## 5. Publishing

If you want a shareable link instead of a local `.pbix`, use **Publish** from
Desktop (or save directly if working in the web app) to push to your Power BI
workspace.
