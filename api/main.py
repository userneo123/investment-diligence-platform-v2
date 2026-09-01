from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
import mysql.connector

from api.db import fetch_all
from api.llm import explain_anomalies

app = FastAPI(title="Investment Diligence API")


@app.exception_handler(mysql.connector.Error)
def handle_db_error(request: Request, exc: mysql.connector.Error):
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


def _validate_ticker(ticker: str) -> str:
    ticker = ticker.strip()
    if not ticker:
        raise HTTPException(status_code=400, detail="Ticker must not be empty")
    return ticker.upper()


def _company_exists(ticker: str) -> bool:
    rows = fetch_all("SELECT company_id FROM companies WHERE ticker = %s", (ticker,))
    return len(rows) > 0


def _get_company_name(ticker: str) -> str:
    rows = fetch_all("SELECT company_name FROM companies WHERE ticker = %s", (ticker,))
    return rows[0]["company_name"]


def _get_flags(ticker: str):
    return fetch_all(
        """
        SELECT fiscal_year, flag_type, metric_name, flag_detail, severity
        FROM v_company_flag_summary
        WHERE ticker = %s
        ORDER BY fiscal_year DESC
        """,
        (ticker,),
    )


@app.get("/company/{ticker}/anomalies")
def get_anomalies(ticker: str):
    ticker = _validate_ticker(ticker)
    if not _company_exists(ticker):
        raise HTTPException(status_code=404, detail=f"Unknown ticker: {ticker}")
    rows = fetch_all(
        """
        SELECT fiscal_year, flag_type, metric_name, flag_detail, severity
        FROM v_company_flag_summary
        WHERE ticker = %s
        ORDER BY fiscal_year DESC
        """,
        (ticker,),
    )
    return rows


@app.get("/company/{ticker}/metrics")
def get_metrics(ticker: str):
    ticker = _validate_ticker(ticker)
    if not _company_exists(ticker):
        raise HTTPException(status_code=404, detail=f"Unknown ticker: {ticker}")
    rows = fetch_all(
        """
        SELECT
            fs.fiscal_year,
            fs.revenue,
            fs.net_income,
            fs.total_assets,
            fs.total_liabilities,
            fs.total_equity,
            fs.operating_cash_flow,
            fs.eps_diluted
        FROM financial_statements fs
        JOIN companies c ON c.company_id = fs.company_id
        WHERE c.ticker = %s
        ORDER BY fs.fiscal_year
        """,
        (ticker,),
    )
    return rows


@app.post("/company/{ticker}/explain-anomalies")
def post_explain_anomalies(ticker: str):
    ticker = _validate_ticker(ticker)
    if not _company_exists(ticker):
        raise HTTPException(status_code=404, detail=f"Unknown ticker: {ticker}")
    flags = _get_flags(ticker)
    if not flags:
        return {
            "ticker": ticker,
            "explanation": "No anomaly flags were detected for this company. There is nothing to explain.",
            "flags_considered": [],
        }
    company_name = _get_company_name(ticker)
    explanation = explain_anomalies(company_name, ticker, flags)
    return {
        "ticker": ticker,
        "explanation": explanation,
        "flags_considered": flags,
    }
