-- ============================================================================
-- OPTIONAL scripted alternative to the MySQL Workbench Table Data Import
-- Wizard described in the main README. Use whichever you prefer.
--
-- LOAD DATA INFILE requires local_infile to be enabled on both the client
-- and server, which is why the README recommends the GUI wizard as the
-- no-config default. If you'd rather script it, enable local_infile first:
--
--   In Workbench: Edit > Preferences > SQL Editor > check "Enable Local Infile"
--   restart Workbench, then run the SET below at the start of your session.
-- ============================================================================

USE investment_diligence;

SET GLOBAL local_infile = 1;

-- Update these paths to wherever you saved the CSVs from the notebook.
-- Import order matters: companies first (everything else has a FK to it).

LOAD DATA LOCAL INFILE '/path/to/finance-diligence-platform/data/companies.csv'
INTO TABLE companies
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(company_id, ticker, company_name, cik);

LOAD DATA LOCAL INFILE '/path/to/finance-diligence-platform/data/financial_statements.csv'
INTO TABLE financial_statements
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(company_id, @ticker, fiscal_year, revenue, net_income, total_assets,
 total_liabilities, total_equity, operating_cash_flow, eps_diluted);

LOAD DATA LOCAL INFILE '/path/to/finance-diligence-platform/data/stock_prices.csv'
INTO TABLE stock_prices
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@ticker, price_date, open, high, low, close, volume, source, company_id);

LOAD DATA LOCAL INFILE '/path/to/finance-diligence-platform/data/reconciliation_log.csv'
INTO TABLE data_reconciliation_log
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@ticker, fiscal_year, metric_name, source_a, value_a, source_b, value_b,
 discrepancy_pct, company_id);

SELECT 'Row counts after load:' AS status;
SELECT 'companies' AS table_name, COUNT(*) AS row_count FROM companies
UNION ALL
SELECT 'financial_statements', COUNT(*) FROM financial_statements
UNION ALL
SELECT 'stock_prices', COUNT(*) FROM stock_prices
UNION ALL
SELECT 'data_reconciliation_log', COUNT(*) FROM data_reconciliation_log;
