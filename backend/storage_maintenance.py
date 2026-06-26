# --- Módulo: storage_maintenance ---
# Estimativa, limpeza, arquivo frio e leitura de artefactos em sandbox_jobs.

from __future__ import annotations

import shutil
import time
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

import config
import job_store


# --- Data/hora UTC actual ---
def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


# --- Parse de timestamp ISO 8601 ---
def _parse_iso(ts: str) -> Optional[datetime]:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


# --- Tamanho total recursivo de directório ---
def _dir_size_bytes(path: Path) -> int:
    total = 0
    try:
        if not path.exists():
            return 0
        if path.is_file():
            return int(path.stat().st_size)
        for p in path.rglob("*"):
            try:
                if p.is_file():
                    total += int(p.stat().st_size)
            except OSError:
                continue
    except Exception:
        return 0
    return total


@dataclass
# --- Classe Storage Estimate ---
class StorageEstimate:
    sandbox_jobs_bytes: int = 0
    reports_bytes: int = 0
    decompiled_bytes: int = 0

    python_cache_bytes: int = 0
    wpf_build_bytes: int = 0
    frontend_dist_bytes: int = 0

    @property
    # --- Total de bytes ocupados pelo conjunto ---
    def total_bytes(self) -> int:
        return (
            self.sandbox_jobs_bytes
            + self.reports_bytes
            + self.decompiled_bytes
            + self.python_cache_bytes
            + self.wpf_build_bytes
            + self.frontend_dist_bytes
        )


# --- Estima espaço em disco por categoria (build/caches no repo; outputs em DATA_DIR) ---
def estimate_storage(project_root: Path) -> StorageEstimate:
    project_root = Path(project_root).resolve()
    return StorageEstimate(
        sandbox_jobs_bytes=_dir_size_bytes(Path(config.SANDBOX_JOBS_DIR)),
        reports_bytes=_dir_size_bytes(Path(config.REPORTS_DIR)),
        decompiled_bytes=_dir_size_bytes(Path(config.DECOMPILED_DIR)),
        python_cache_bytes=_dir_size_bytes(project_root / "__pycache__")
        + _dir_size_bytes(project_root / "backend" / "__pycache__")
        + _dir_size_bytes(project_root / "backend" / "modules" / "__pycache__"),
        wpf_build_bytes=_dir_size_bytes(project_root / "wpf-gui" / "bin")
        + _dir_size_bytes(project_root / "wpf-gui" / "obj"),
        frontend_dist_bytes=_dir_size_bytes(project_root / "frontend" / "dist"),
    )


# --- Retenção soft: apaga artefatos pesados de jobs antigos finalizados (mantém DB) ---
def cleanup_job_artifacts(retention_days: int, max_count: int) -> dict:
    retention_days = max(0, int(retention_days))
    max_count = max(1, int(max_count))
    now = _utc_now()

    # Obter lista grande e aplicar política
    items = job_store.list_jobs(limit=5000, offset=0)
    kept = 0
    deleted = 0
    freed_bytes = 0

    for idx, it in enumerate(items):
        status = (it.get("status") or "").lower()
        job_id = it.get("id") or ""
        updated_at = _parse_iso(it.get("updatedAt") or "") or _parse_iso(it.get("createdAt") or "")
        if not job_id:
            continue

        # manter os N mais recentes sempre
        if kept < max_count:
            kept += 1
            continue

        # manter os recentes por TTL
        if updated_at is not None and retention_days > 0:
            age_days = (now - updated_at).total_seconds() / 86400.0
            if age_days <= retention_days:
                continue

        # só limpar jobs finalizados
        if status not in ("completed", "failed"):
            continue

        base_dir = Path(config.SANDBOX_JOBS_DIR) / job_id
        out_dir = base_dir / "out"
        if out_dir.exists():
            sz = _dir_size_bytes(out_dir)
            try:
                shutil.rmtree(out_dir)
                freed_bytes += sz
            except Exception:
                continue
        # opcional: remover sample binário (normalmente o maior)
        try:
            # encontrar ficheiro sample (o primeiro não 'out' e não hidden)
            for p in base_dir.iterdir():
                if p.name == "out":
                    continue
                if p.is_file() and not p.name.startswith("."):
                    try:
                        freed_bytes += int(p.stat().st_size)
                        p.unlink()
                    except Exception:
                        pass
        except Exception:
            pass

        try:
            job_store.mark_artifacts_deleted(job_id)
        except Exception:
            pass
        deleted += 1

    return {"deletedJobs": deleted, "freedBytes": freed_bytes, "keptMostRecent": max_count, "retentionDays": retention_days}


# --- Compacta directório em ficheiro ZIP ---
def _zip_dir(src_dir: Path, zip_path: Path, *, exclude_globs: Iterable[str] = ()) -> None:
    src_dir = Path(src_dir)
    zip_path = Path(zip_path)
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    ex = list(exclude_globs or [])
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for p in src_dir.rglob("*"):
            if not p.is_file():
                continue
            rel = p.relative_to(src_dir)
            rel_str = str(rel).replace("\\", "/")
            if any(p.match(g) or rel.match(g) for g in ex):
                continue
            zf.write(p, arcname=rel_str)


# --- Arquivo frio: zip de out/ para out.zip e remove pasta (mantém DB) ---
def archive_cold_jobs(older_than_days: int) -> dict:
    older_than_days = max(1, int(older_than_days))
    now = _utc_now()
    items = job_store.list_jobs(limit=5000, offset=0)

    archived = 0
    freed_bytes = 0
    for it in items:
        status = (it.get("status") or "").lower()
        if status not in ("completed", "failed"):
            continue
        job_id = it.get("id") or ""
        updated_at = _parse_iso(it.get("updatedAt") or "") or _parse_iso(it.get("createdAt") or "")
        if not job_id or updated_at is None:
            continue
        age_days = (now - updated_at).total_seconds() / 86400.0
        if age_days < older_than_days:
            continue

        base_dir = Path(config.SANDBOX_JOBS_DIR) / job_id
        out_dir = base_dir / "out"
        if not out_dir.exists():
            continue

        zip_path = base_dir / "out.zip"
        # já arquivado
        if zip_path.exists():
            continue

        sz = _dir_size_bytes(out_dir)
        try:
            _zip_dir(out_dir, zip_path)
            shutil.rmtree(out_dir)
            freed_bytes += sz
            archived += 1
            try:
                job_store.set_archive_paths(job_id, str(zip_path), None)
            except Exception:
                pass
        except Exception:
            # se falhou, tentar não deixar zip parcial
            try:
                if zip_path.exists():
                    zip_path.unlink()
            except Exception:
                pass

    return {"archivedJobs": archived, "freedBytes": freed_bytes, "olderThanDays": older_than_days}


# --- Purga completa de sandbox_jobs, reports e decompiled; recria DB vazia ---
def purge_all_storage() -> dict:
    targets = [
        Path(config.SANDBOX_JOBS_DIR),
        Path(config.REPORTS_DIR),
        Path(config.DECOMPILED_DIR),
    ]

    removed_paths: list[str] = []
    freed_bytes = 0
    for target in targets:
        if target.exists():
            freed_bytes += _dir_size_bytes(target)
            try:
                shutil.rmtree(target)
                removed_paths.append(str(target))
            except Exception:
                continue
        try:
            target.mkdir(parents=True, exist_ok=True)
        except Exception:
            pass

    try:
        job_store.init_db()
    except Exception:
        pass

    return {
        "removedPaths": removed_paths,
        "freedBytes": freed_bytes,
        "dataDir": str(config.DATA_DIR),
    }


# --- Leitura de artefacto texto: out/ normal ou out.zip (caminho relativo a out/) ---
def read_text_artifact_from_job(job_id: str, relative_path: str) -> Optional[str]:
    base_dir = Path(config.SANDBOX_JOBS_DIR) / job_id
    out_dir = base_dir / "out"
    target = out_dir / relative_path
    try:
        if target.exists() and target.is_file():
            return target.read_text(encoding="utf-8", errors="replace")
    except Exception:
        pass

    zip_path = base_dir / "out.zip"
    if not zip_path.exists():
        return None
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            name = relative_path.replace("\\", "/")
            with zf.open(name, "r") as fh:
                raw = fh.read()
                try:
                    return raw.decode("utf-8", "replace")
                except Exception:
                    return raw.decode("latin-1", "replace")
    except Exception:
        return None


__all__ = [
    "estimate_storage",
    "cleanup_job_artifacts",
    "archive_cold_jobs",
    "purge_all_storage",
    "StorageEstimate",
]

