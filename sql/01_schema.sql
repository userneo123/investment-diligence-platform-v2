-- ============================================================================
-- Investment Diligence & Financial Data Intelligence Platform
-- Schema: normalized tables with validation constraints
-- Run this first, in MySQL Workbench, against your local instance.
-- ============================================================================

DROP DATABASE IF EXISTS investment_diligence;
CREATE DATABASE investment_diligence CHARACTER SET utf8mb4;
USE investment_diligence;

-- ----------------------------------------------------------------------------
-- companies: one row per ticker (3NF -- company attributes live only here)
-- ----------------------------------------------------------------------------
CREATE TABLE companies (
    company_id      INT AUTO_INCREMENT PRIMARY KEY,
    ticker          VARCHAR(10)  NOT NULL,
    company_name    VARCHAR(255) NOT NULL,
    cik             VARCHAR(10),
    sector          VARCHAR(100),
    industry        VARCHAR(100),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_companies_ticker UNIQUE (ticker),
    CONSTRAINT chk_ticker_format CHECK (ticker = UPPER(ticker) AND LENGTH(ticker) BETWEEN 1 AND 10)
);

-- ----------------------------------------------------------------------------
-- financial_statements: one row per company per fiscal year (reconciled values)
-- ----------------------------------------------------------------------------
CREATE TABLE financial_statements (
    statement_id         INT AUTO_INCREMENT PRIMARY KEY,
    company_id           INT NOT NULL,
    fiscal_year          SMALLINT NOT NULL,
    revenue              DECIMAL(20,2),
    net_income           DECIMAL(20,2),
    total_assets         DECIMAL(20,2),
    total_liabilities    DECIMAL(20,2),
    total_equity          DECIMAL(20,2),
    operating_cash_flow  DECIMAL(20,2),
    eps_diluted          DECIMAL(10,4),
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_statements_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_statements_company_year UNIQUE (company_id, fiscal_year),

    CONSTRAINT chk_fiscal_year_range CHECK (fiscal_year BETWEEN 1990 AND 2100),
    CONSTRAINT chk_revenue_nonneg CHECK (revenue IS NULL OR revenue >= 0),
    CONSTRAINT chk_assets_nonneg CHECK (total_assets IS NULL OR total_assets >= 0)
);

-- ----------------------------------------------------------------------------
-- stock_prices: daily OHLCV per company
-- ----------------------------------------------------------------------------
CREATE TABLE stock_prices (
    price_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    company_id   INT NOT NULL,
    price_date   DATE NOT NULL,
    open         DECIMAL(14,4),
    high         DECIMAL(14,4),
    low          DECIMAL(14,4),
    close        DECIMAL(14,4),
    volume       BIGINT,
    source       VARCHAR(50) DEFAULT 'ALPHA_VANTAGE',

    CONSTRAINT fk_prices_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_prices_company_date UNIQUE (company_id, price_date),

    CONSTRAINT chk_price_high_low CHECK (high IS NULL OR low IS NULL OR high >= low),
    CONSTRAINT chk_volume_nonneg CHECK (volume IS NULL OR volume >= 0)
);

-- ----------------------------------------------------------------------------
-- data_reconciliation_log: discrepancies found between SEC EDGAR and
-- Alpha Vantage for the same (company, year, metric) during ETL
-- ----------------------------------------------------------------------------
CREATE TABLE data_reconciliation_log (
    log_id           INT AUTO_INCREMENT PRIMARY KEY,
    company_id       INT NOT NULL,
    fiscal_year      SMALLINT NOT NULL,
    metric_name      VARCHAR(50) NOT NULL,
    source_a         VARCHAR(50) NOT NULL,
    value_a          DECIMAL(20,2),
    source_b         VARCHAR(50) NOT NULL,
    value_b          DECIMAL(20,2),
    discrepancy_pct  DECIMAL(6,2),
    flagged_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_reconlog_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_discrepancy_nonneg CHECK (discrepancy_pct IS NULL OR discrepancy_pct >= 0)
);

-- ----------------------------------------------------------------------------
-- anomaly_flags: output of 03_anomaly_detection.sql, kept as a persisted
-- table so Power BI can query flags directly instead of re-running SQL logic
-- ----------------------------------------------------------------------------
CREATE TABLE anomaly_flags (
    flag_id       INT AUTO_INCREMENT PRIMARY KEY,
    company_id    INT NOT NULL,
    fiscal_year   SMALLINT NOT NULL,
    flag_type     VARCHAR(100) NOT NULL,
    metric_name   VARCHAR(50),
    flag_detail   VARCHAR(255),
    severity      ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'MEDIUM',
    flagged_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_flags_company
        FOREIGN KEY (company_id) REFERENCES companies(company_id)
        ON DELETE CASCADE
);

-- Helpful indexes for the analytical queries in 03_anomaly_detection.sql
CREATE INDEX idx_statements_year ON financial_statements(fiscal_year);
CREATE INDEX idx_prices_date ON stock_prices(price_date);
CREATE INDEX idx_flags_severity ON anomaly_flags(severity);

SELECT 'Schema created successfully.' AS status;
