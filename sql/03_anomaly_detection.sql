-- ============================================================================
-- Anomaly detection: joins + CTEs + window functions over the reconciled
-- financial data. Each block below both SELECTs the flagged rows (so you can
-- eyeball them) and INSERTs them into anomaly_flags for Power BI to consume.
-- ============================================================================

USE investment_diligence;

-- ----------------------------------------------------------------------------
-- 1. Year-over-year growth using LAG(), flag any YoY revenue drop > 15%
-- ----------------------------------------------------------------------------
WITH yoy AS (
    SELECT
        fs.company_id,
        fs.fiscal_year,
        fs.revenue,
        LAG(fs.revenue) OVER (
            PARTITION BY fs.company_id ORDER BY fs.fiscal_year
        ) AS prior_year_revenue
    FROM financial_statements fs
),
yoy_growth AS (
    SELECT
        company_id,
        fiscal_year,
        revenue,
        prior_year_revenue,
        ROUND((revenue - prior_year_revenue) / prior_year_revenue * 100, 2) AS revenue_growth_pct
    FROM yoy
    WHERE prior_year_revenue IS NOT NULL AND prior_year_revenue > 0
)
SELECT c.ticker, c.company_name, g.fiscal_year, g.revenue,
       g.prior_year_revenue, g.revenue_growth_pct
FROM yoy_growth g
JOIN companies c ON c.company_id = g.company_id
WHERE g.revenue_growth_pct < -15
ORDER BY g.revenue_growth_pct ASC;

INSERT INTO anomaly_flags (company_id, fiscal_year, flag_type, metric_name, flag_detail, severity)
SELECT
    g.company_id,
    g.fiscal_year,
    'REVENUE_DECLINE',
    'revenue',
    CONCAT('Revenue fell ', ABS(g.revenue_growth_pct), '% YoY (', g.prior_year_revenue, ' -> ', g.revenue, ')'),
    CASE WHEN g.revenue_growth_pct < -30 THEN 'HIGH' ELSE 'MEDIUM' END
FROM (
    SELECT
        company_id, fiscal_year, revenue, prior_year_revenue, revenue_growth_pct
    FROM (
        SELECT
            fs.company_id,
            fs.fiscal_year,
            fs.revenue,
            LAG(fs.revenue) OVER (PARTITION BY fs.company_id ORDER BY fs.fiscal_year) AS prior_year_revenue
        FROM financial_statements fs
    ) t
    WHERE prior_year_revenue IS NOT NULL AND prior_year_revenue > 0
) g
WHERE g.revenue_growth_pct < -15;

-- ----------------------------------------------------------------------------
-- 2. Margin z-score anomaly detection: flag any (company, year) where net
-- margin is more than 2 standard deviations from that company's own
-- historical average margin -- catches one-off blowups/writedowns.
-- ----------------------------------------------------------------------------
WITH margins AS (
    SELECT
        company_id,
        fiscal_year,
        revenue,
        net_income,
        CASE WHEN revenue > 0 THEN net_income / revenue ELSE NULL END AS net_margin
    FROM financial_statements
    WHERE revenue IS NOT NULL AND net_income IS NOT NULL
),
margin_stats AS (
    SELECT
        company_id,
        fiscal_year,
        net_margin,
        AVG(net_margin) OVER (PARTITION BY company_id) AS avg_margin,
        STDDEV(net_margin) OVER (PARTITION BY company_id) AS stddev_margin
    FROM margins
),
margin_z AS (
    SELECT
        company_id,
        fiscal_year,
        net_margin,
        avg_margin,
        stddev_margin,
        CASE WHEN stddev_margin > 0
             THEN (net_margin - avg_margin) / stddev_margin
             ELSE 0 END AS z_score
    FROM margin_stats
)
SELECT c.ticker, c.company_name, mz.fiscal_year,
       ROUND(mz.net_margin * 100, 2) AS net_margin_pct,
       ROUND(mz.avg_margin * 100, 2) AS company_avg_margin_pct,
       ROUND(mz.z_score, 2) AS z_score
FROM margin_z mz
JOIN companies c ON c.company_id = mz.company_id
WHERE ABS(mz.z_score) > 2
ORDER BY ABS(mz.z_score) DESC;

WITH margins2 AS (
    SELECT
        company_id,
        fiscal_year,
        CASE WHEN revenue > 0 THEN net_income / revenue ELSE NULL END AS net_margin
    FROM financial_statements
    WHERE revenue IS NOT NULL AND net_income IS NOT NULL
),
margin_stats2 AS (
    SELECT
        company_id,
        fiscal_year,
        net_margin,
        AVG(net_margin) OVER (PARTITION BY company_id) AS avg_margin,
        STDDEV(net_margin) OVER (PARTITION BY company_id) AS stddev_margin
    FROM margins2
),
margin_z2 AS (
    SELECT
        company_id,
        fiscal_year,
        avg_margin,
        CASE WHEN stddev_margin > 0
             THEN (net_margin - avg_margin) / stddev_margin
             ELSE 0 END AS z_score
    FROM margin_stats2
)
INSERT INTO anomaly_flags (company_id, fiscal_year, flag_type, metric_name, flag_detail, severity)
SELECT
    company_id,
    fiscal_year,
    'MARGIN_OUTLIER',
    'net_margin',
    CONCAT('Net margin z-score of ', ROUND(z_score, 2),
           ' vs company historical average of ', ROUND(avg_margin * 100, 2), '%'),
    CASE WHEN ABS(z_score) > 3 THEN 'HIGH' ELSE 'MEDIUM' END
FROM margin_z2
WHERE ABS(z_score) > 2;

-- ----------------------------------------------------------------------------
-- 3. Balance sheet equation check: Assets should equal Liabilities + Equity.
-- Flag any year where they're off by more than 2% -- usually a data quality
-- issue rather than a real anomaly, which is exactly what diligence wants to
-- catch before trusting a dashboard number.
-- ----------------------------------------------------------------------------
SELECT c.ticker, c.company_name, fs.fiscal_year,
       fs.total_assets, fs.total_liabilities, fs.total_equity,
       ROUND(ABS(fs.total_assets - (fs.total_liabilities + fs.total_equity))
             / NULLIF(fs.total_assets, 0) * 100, 2) AS imbalance_pct
FROM financial_statements fs
JOIN companies c ON c.company_id = fs.company_id
WHERE fs.total_assets IS NOT NULL
  AND fs.total_liabilities IS NOT NULL
  AND fs.total_equity IS NOT NULL
  AND fs.total_assets > 0
  AND ABS(fs.total_assets - (fs.total_liabilities + fs.total_equity)) / fs.total_assets > 0.02
ORDER BY imbalance_pct DESC;

INSERT INTO anomaly_flags (company_id, fiscal_year, flag_type, metric_name, flag_detail, severity)
SELECT
    fs.company_id,
    fs.fiscal_year,
    'BALANCE_SHEET_MISMATCH',
    'total_assets',
    CONCAT('Assets (', fs.total_assets, ') vs Liabilities+Equity (',
           fs.total_liabilities + fs.total_equity, ') off by ',
           ROUND(ABS(fs.total_assets - (fs.total_liabilities + fs.total_equity)) / fs.total_assets * 100, 2), '%'),
    'HIGH'
FROM financial_statements fs
WHERE fs.total_assets IS NOT NULL
  AND fs.total_liabilities IS NOT NULL
  AND fs.total_equity IS NOT NULL
  AND fs.total_assets > 0
  AND ABS(fs.total_assets - (fs.total_liabilities + fs.total_equity)) / fs.total_assets > 0.02;

-- ----------------------------------------------------------------------------
-- 4. Cross-source discrepancies already logged during ETL: promote anything
-- above threshold into the same anomaly_flags table so Power BI has one
-- place to read all flags from.
-- ----------------------------------------------------------------------------
INSERT INTO anomaly_flags (company_id, fiscal_year, flag_type, metric_name, flag_detail, severity)
SELECT
    r.company_id,
    r.fiscal_year,
    'CROSS_SOURCE_DISCREPANCY',
    r.metric_name,
    CONCAT(r.source_a, '=', r.value_a, ' vs ', r.source_b, '=', r.value_b,
           ' (', r.discrepancy_pct, '% apart)'),
    CASE WHEN r.discrepancy_pct > 15 THEN 'HIGH' ELSE 'MEDIUM' END
FROM data_reconciliation_log r;

-- ----------------------------------------------------------------------------
-- 5. Negative equity flag (simple filter, kept separate since it needs no
-- window function -- straightforward but important for diligence)
-- ----------------------------------------------------------------------------
INSERT INTO anomaly_flags (company_id, fiscal_year, flag_type, metric_name, flag_detail, severity)
SELECT company_id, fiscal_year, 'NEGATIVE_EQUITY', 'total_equity',
       CONCAT('Total equity is negative: ', total_equity), 'HIGH'
FROM financial_statements
WHERE total_equity IS NOT NULL AND total_equity < 0;

-- ----------------------------------------------------------------------------
-- Summary view for Power BI / quick review: every flag joined back to
-- company info, with a ranking of most-flagged companies.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_company_flag_summary AS
SELECT
    c.ticker,
    c.company_name,
    af.fiscal_year,
    af.flag_type,
    af.metric_name,
    af.flag_detail,
    af.severity,
    COUNT(*) OVER (PARTITION BY af.company_id) AS total_flags_for_company,
    RANK() OVER (ORDER BY COUNT(*) OVER (PARTITION BY af.company_id) DESC) AS flag_rank
FROM anomaly_flags af
JOIN companies c ON c.company_id = af.company_id;

SELECT * FROM v_company_flag_summary ORDER BY total_flags_for_company DESC, fiscal_year DESC;
