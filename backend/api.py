"""
API REST para o RAT Analyzer.
Ponto de entrada: uvicorn api:app

Routers em `routers/` · factory em `app_factory.py`.
"""

from app_factory import create_app
from rat_analyzer import RATAnalyzer

app = create_app()

__all__ = ["app", "RATAnalyzer"]
