import os
from dotenv import load_dotenv
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_groq import ChatGroq

load_dotenv()

PROMPT_TEMPLATE = """You are a financial analyst assistant. Below are anomaly flags that were
already detected by SQL analysis of {company_name}'s ({ticker}) financial
filings. Explain what these flags mean in plain English for someone without
a finance background. For each flag, briefly explain (1) what pattern was
detected, (2) why that pattern is typically a signal worth investigating, and
(3) that this is a data flag, not a definitive conclusion -- it is a
starting point for diligence, not an accusation of wrongdoing or a certainty
that something is wrong. Do not invent numbers or explanations beyond what
the flags below actually state.

FLAGS DETECTED:
{flags_block}

EXPLANATION:"""

_chain = None


def _get_chain():
    """Lazily construct the LangChain pipeline so importing this module
    doesn't require GROQ_API_KEY unless a call is actually made."""
    global _chain
    if _chain is None:
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise RuntimeError("GROQ_API_KEY is not set in the environment.")
        llm = ChatGroq(model="openai/gpt-oss-120b", temperature=0, api_key=api_key)
        prompt = ChatPromptTemplate.from_template(PROMPT_TEMPLATE)
        _chain = prompt | llm | StrOutputParser()
    return _chain


def format_flags_block(flags: list[dict]) -> str:
    lines = [
        f"- [{f['fiscal_year']}] {f['flag_type']} ({f['severity']}): {f['flag_detail']}"
        for f in flags
    ]
    return "\n".join(lines)


def explain_anomalies(company_name: str, ticker: str, flags: list[dict]) -> str:
    chain = _get_chain()
    flags_block = format_flags_block(flags)
    return chain.invoke(
        {
            "company_name": company_name,
            "ticker": ticker,
            "flags_block": flags_block,
        }
    )
