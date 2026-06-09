from __future__ import annotations

import hashlib
import json
import sqlite3
import threading
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import config


_LOCK = threading.Lock()


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _db_path() -> Path:
    config.SANDBOX_JOBS_DIR.mkdir(parents=True, exist_ok=True)
    return Path(config.ANALYSIS_DB_PATH)


def _table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    try:
        rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
        return {str(r[1]) for r in rows}  # (cid, name, type, notnull, dflt, pk)
    except Exception:
        return set()


def init_db() -> None:
    with _LOCK:
        p = _db_path()
        conn = sqlite3.connect(str(p))
        try:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS analyses (
                  job_id TEXT PRIMARY KEY,
                  analysis_type TEXT NOT NULL,
                  status TEXT NOT NULL,
                  file_name TEXT NOT NULL,
                  sha256 TEXT NOT NULL,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL,
                  error TEXT NULL,
                  static_json TEXT NULL,
                  dynamic_json TEXT NULL
                )
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_analyses_updated_at ON analyses(updated_at)")
            # Migrações "soft" (ALTER TABLE) para manter compatibilidade com DBs antigas
            cols = _table_columns(conn, "analyses")
            migrations: list[tuple[str, str]] = [
                ("pipeline_version", "TEXT NULL"),
                ("reused_from_job_id", "TEXT NULL"),
                ("out_zip_path", "TEXT NULL"),
                ("decompiled_zip_path", "TEXT NULL"),
                ("archived_at", "TEXT NULL"),
                ("artifacts_deleted_at", "TEXT NULL"),
            ]
            for name, ddl in migrations:
                if name not in cols:
                    conn.execute(f"ALTER TABLE analyses ADD COLUMN {name} {ddl}")
            conn.commit()
        finally:
            conn.close()


def sha256_bytes(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return h.hexdigest()


def insert_job(job_id: str, analysis_type: str, file_name: str, sha256: str, status: str) -> None:
    init_db()
    with _LOCK:
        now = _utc_now_iso()
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                INSERT INTO analyses (job_id, analysis_type, status, file_name, sha256, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (job_id, analysis_type, status, file_name, sha256, now, now),
            )
            conn.commit()
        finally:
            conn.close()


def update_pipeline_version(job_id: str, pipeline_version: str) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                UPDATE analyses
                   SET pipeline_version = ?,
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (pipeline_version, _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def mark_reused(job_id: str, reused_from_job_id: str) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                UPDATE analyses
                   SET reused_from_job_id = ?,
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (reused_from_job_id, _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def set_archive_paths(job_id: str, out_zip_path: str | None, decompiled_zip_path: str | None) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                UPDATE analyses
                   SET out_zip_path = COALESCE(?, out_zip_path),
                       decompiled_zip_path = COALESCE(?, decompiled_zip_path),
                       archived_at = ?,
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (out_zip_path, decompiled_zip_path, _utc_now_iso(), _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def mark_artifacts_deleted(job_id: str) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                UPDATE analyses
                   SET artifacts_deleted_at = ?,
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (_utc_now_iso(), _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def find_completed_by_sha256(sha256: str, analysis_type: str | None = None, pipeline_version: str | None = None) -> Optional[dict]:
    """
    Procura um job COMPLETED por sha256, opcionalmente filtrando por analysis_type e pipeline_version.
    Devolve o row "normalizado" (mesmo formato de get_job_row).
    """
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        conn.row_factory = sqlite3.Row
        try:
            where = ["status = 'completed'", "sha256 = ?"]
            args: list[Any] = [sha256]
            if analysis_type:
                where.append("analysis_type = ?")
                args.append(analysis_type)
            if pipeline_version:
                where.append("pipeline_version = ?")
                args.append(pipeline_version)
            sql = f"SELECT * FROM analyses WHERE {' AND '.join(where)} ORDER BY updated_at DESC LIMIT 1"
            row = conn.execute(sql, tuple(args)).fetchone()
            if not row:
                return None
            d = dict(row)
        finally:
            conn.close()

    def _loads(s: Optional[str]) -> Any | None:
        if not s:
            return None
        try:
            return json.loads(s)
        except Exception:
            return None

    return {
        "id": d["job_id"],
        "analysisType": d["analysis_type"],
        "status": d["status"],
        "error": d.get("error"),
        "fileName": d["file_name"],
        "sha256": d["sha256"],
        "createdAt": d["created_at"],
        "updatedAt": d["updated_at"],
        "staticResult": _loads(d.get("static_json")),
        "dynamicResult": _loads(d.get("dynamic_json")),
        "pipelineVersion": d.get("pipeline_version"),
        "reusedFromJobId": d.get("reused_from_job_id"),
        "outZipPath": d.get("out_zip_path"),
        "decompiledZipPath": d.get("decompiled_zip_path"),
        "archivedAt": d.get("archived_at"),
        "artifactsDeletedAt": d.get("artifacts_deleted_at"),
    }

def update_status(job_id: str, status: str, error: Optional[str] = None) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            conn.execute(
                """
                UPDATE analyses
                   SET status = ?,
                       error = ?,
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (status, error, _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def update_results(job_id: str, static_obj: Any | None, dynamic_obj: Any | None) -> None:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        try:
            static_json = json.dumps(static_obj, ensure_ascii=False) if static_obj is not None else None
            dynamic_json = json.dumps(dynamic_obj, ensure_ascii=False) if dynamic_obj is not None else None
            conn.execute(
                """
                UPDATE analyses
                   SET static_json = COALESCE(?, static_json),
                       dynamic_json = COALESCE(?, dynamic_json),
                       updated_at = ?
                 WHERE job_id = ?
                """,
                (static_json, dynamic_json, _utc_now_iso(), job_id),
            )
            conn.commit()
        finally:
            conn.close()


def get_job_row(job_id: str) -> Optional[dict]:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        conn.row_factory = sqlite3.Row
        try:
            row = conn.execute("SELECT * FROM analyses WHERE job_id = ?", (job_id,)).fetchone()
            if not row:
                return None
            d = dict(row)
        finally:
            conn.close()

    def _loads(s: Optional[str]) -> Any | None:
        if not s:
            return None
        try:
            return json.loads(s)
        except Exception:
            return None

    return {
        "id": d["job_id"],
        "analysisType": d["analysis_type"],
        "status": d["status"],
        "error": d.get("error"),
        "fileName": d["file_name"],
        "sha256": d["sha256"],
        "createdAt": d["created_at"],
        "updatedAt": d["updated_at"],
        "staticResult": _loads(d.get("static_json")),
        "dynamicResult": _loads(d.get("dynamic_json")),
    }


def list_jobs(limit: int = 50, offset: int = 0) -> list[dict]:
    init_db()
    with _LOCK:
        conn = sqlite3.connect(str(_db_path()))
        conn.row_factory = sqlite3.Row
        try:
            rows = conn.execute(
                """
                SELECT job_id, analysis_type, status, file_name, sha256, created_at, updated_at, error
                  FROM analyses
                 ORDER BY updated_at DESC
                 LIMIT ? OFFSET ?
                """,
                (int(limit), int(offset)),
            ).fetchall()
            return [
                {
                    "id": r["job_id"],
                    "analysisType": r["analysis_type"],
                    "status": r["status"],
                    "fileName": r["file_name"],
                    "sha256": r["sha256"],
                    "createdAt": r["created_at"],
                    "updatedAt": r["updated_at"],
                    "error": r["error"],
                }
                for r in rows
            ]
        finally:
            conn.close()

