"""
Testes unitários de sanitização de filenames e validação de job_id
(sem servidor; correção de path traversal e UUID).
"""

import uuid
from pathlib import Path

import pytest

from upload_security import (
    get_max_upload_bytes,
    is_valid_job_id,
    resolve_safe_path,
    sanitize_upload_filename,
)


class TestSanitizeUploadFilename:
    def test_nome_simples_aceite(self):
        assert sanitize_upload_filename("sample.exe") == "sample.exe"
        assert sanitize_upload_filename("relatorio final.dll") == "relatorio final.dll"

    def test_nome_vazio_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("")
        with pytest.raises(ValueError):
            sanitize_upload_filename(None)
        with pytest.raises(ValueError):
            sanitize_upload_filename("   ")

    def test_path_traversal_windows_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("..\\..\\x.exe")

    def test_path_traversal_posix_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("../../etc/passwd")

    def test_separadores_rejeitados(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("a/b.exe")
        with pytest.raises(ValueError):
            sanitize_upload_filename("a\\b.exe")

    def test_path_absoluto_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("C:\\Windows\\System32\\evil.dll")
        with pytest.raises(ValueError):
            sanitize_upload_filename("/etc/passwd")

    def test_drive_letter_sem_separador_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("C:evil.exe")

    def test_dotdot_isolado_rejeitado(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("..")
        with pytest.raises(ValueError):
            sanitize_upload_filename(".")

    def test_caracteres_controlo_rejeitados(self):
        with pytest.raises(ValueError):
            sanitize_upload_filename("evil\x00.exe")


class TestResolveSafePath:
    def test_path_dentro_da_base(self, tmp_path):
        target = resolve_safe_path(tmp_path, "sample.exe")
        assert target == (tmp_path / "sample.exe").resolve()
        assert target.is_relative_to(tmp_path.resolve())


class TestIsValidJobId:
    def test_uuid4_valido(self):
        assert is_valid_job_id(str(uuid.uuid4()))
        assert is_valid_job_id(str(uuid.uuid4()).upper())

    def test_invalidos(self):
        assert not is_valid_job_id("")
        assert not is_valid_job_id(None)
        assert not is_valid_job_id("not-a-uuid")
        assert not is_valid_job_id("../../etc/passwd")
        assert not is_valid_job_id("..%2f..%2fx")
        # UUID v1 não é aceite (exige versão 4)
        assert not is_valid_job_id(str(uuid.uuid1()))


class TestMaxUploadBytes:
    def test_default_100mb(self, monkeypatch):
        monkeypatch.delenv("RATANALYZER_MAX_UPLOAD_MB", raising=False)
        assert get_max_upload_bytes() == 100 * 1024 * 1024

    def test_override_por_env(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_MAX_UPLOAD_MB", "5")
        assert get_max_upload_bytes() == 5 * 1024 * 1024

    def test_valores_invalidos_usam_default(self, monkeypatch):
        monkeypatch.setenv("RATANALYZER_MAX_UPLOAD_MB", "abc")
        assert get_max_upload_bytes() == 100 * 1024 * 1024
        monkeypatch.setenv("RATANALYZER_MAX_UPLOAD_MB", "-1")
        assert get_max_upload_bytes() == 100 * 1024 * 1024
