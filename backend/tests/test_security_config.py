# --- Módulo: test_security_config ---
# Testes de validação de segredos no arranque.

import pytest

from security_config import (
    api_token_configured,
    is_production_mode,
    require_api_token_enforced,
    validate_startup_secrets,
)


@pytest.fixture(autouse=True)
# --- Limpa variáveis de ambiente sensíveis ---
def _clear_secret_env(monkeypatch):
    for name in (
        "RATANALYZER_ENV",
        "RATANALYZER_REQUIRE_SECRETS",
        "RATANALYZER_REQUIRE_API_TOKEN",
        "RATANALYZER_API_TOKEN",
        "VM_AGENT_TOKEN",
    ):
        monkeypatch.delenv(name, raising=False)


# --- Testes de SecurityConfig ---
class TestSecurityConfig:
    def test_dev_sem_flags_nao_exige_token(self):
        assert not require_api_token_enforced()
        assert not is_production_mode()
        validate_startup_secrets()

    def test_require_api_token_sem_valor_aborta(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_REQUIRE_API_TOKEN", "1")
        with pytest.raises(SystemExit) as exc:
            validate_startup_secrets()
        assert exc.value.code == 1

    def test_production_sem_token_aborta(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_ENV", "production")
        with pytest.raises(SystemExit):
            validate_startup_secrets()

    def test_production_com_token_ok(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_ENV", "production")
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "segredo-forte")
        validate_startup_secrets()
        assert api_token_configured()

    def test_token_configurado_sem_modo_estrito(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_API_TOKEN", "x")
        assert api_token_configured()
        assert not require_api_token_enforced()
