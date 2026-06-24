# --- Módulo: security_config ---
# Validação de segredos no arranque do backend (token API em produção).

from __future__ import annotations

import logging
import os
import sys

logger = logging.getLogger("rat_analyzer_api")

_TRUE = frozenset({"1", "true", "yes", "on"})


# --- Interpretação de variável de ambiente como booleano ---
def _env_bool(name: str) -> bool:
    return (os.environ.get(name) or "").strip().lower() in _TRUE


# --- Detecção de modo produção ---
def is_production_mode() -> bool:
    env = (os.environ.get("RATANALYZER_ENV") or "").strip().lower()
    return env == "production" or _env_bool("RATANALYZER_REQUIRE_SECRETS")


# --- Verificação se token API é obrigatório ---
def require_api_token_enforced() -> bool:
    return _env_bool("RATANALYZER_REQUIRE_API_TOKEN") or is_production_mode()


# --- Verificação se token API está configurado ---
def api_token_configured() -> bool:
    return bool((os.environ.get("RATANALYZER_API_TOKEN") or "").strip())


# --- Validação de segredos no arranque (aborta se em falta em produção) ---
def validate_startup_secrets() -> None:
    if not require_api_token_enforced():
        if not api_token_configured():
            logger.warning(
                "RATANALYZER_API_TOKEN não definido — uploads e storage sem autenticação. "
                "Para produção defina o token ou RATANALYZER_REQUIRE_API_TOKEN=1."
            )
        return

    if not api_token_configured():
        logger.critical(
            "Arranque abortado: RATANALYZER_API_TOKEN é obrigatório "
            "(RATANALYZER_ENV=production, RATANALYZER_REQUIRE_SECRETS=1 ou "
            "RATANALYZER_REQUIRE_API_TOKEN=1). "
            "Gere segredos com scripts/generate-production-secrets.ps1."
        )
        raise SystemExit(1)

    if is_production_mode() and not (os.environ.get("VM_AGENT_TOKEN") or "").strip():
        logger.warning(
            "Produção: VM_AGENT_TOKEN não definido — análise dinâmica via vm-agent falhará."
        )
