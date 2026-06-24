# --- Módulo: api ---
# --- Ponto de entrada da API REST do RAT Analyzer ---
# *Expõe a app FastAPI criada em app_factory; arrancar com: uvicorn api:app*
# *Routers em routers/ · factory em app_factory.py*

from app_factory import create_app
from rat_analyzer import RATAnalyzer

app = create_app()

__all__ = ["app", "RATAnalyzer"]
