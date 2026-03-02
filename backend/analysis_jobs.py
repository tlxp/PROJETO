from __future__ import annotations

import enum
import threading
import uuid
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Dict, Optional

import config
from rat_analyzer import RATAnalyzer
from vm_orchestrator import run_dynamic_analysis
import job_store
from task_queue import is_queue_enabled, get_queue


class AnalysisType(str, enum.Enum):
    STATIC = "static"
    DYNAMIC = "dynamic"
    BOTH = "both"


class JobStatus(str, enum.Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class AnalysisResult:
    # Campos comuns ao que o frontend já espera
    report: str = ""
    cCode: str = ""
    ilCode: str = ""
    fileName: str = ""
    riskScore: int = 0
    riskLevel: str = ""
    flaggedIndicators: list[str] = field(default_factory=list)

    # Campos extra para futura extensão
    dynamicReport: Optional[dict] = None
    dynamicSummary: Optional[str] = None


@dataclass
class AnalysisJob:
    id: str
    analysis_type: AnalysisType
    status: JobStatus = JobStatus.QUEUED
    error: Optional[str] = None

    # Caminhos base deste job
    base_dir: Path = field(default_factory=Path)
    sample_path: Path = field(default_factory=Path)
    output_dir: Path = field(default_factory=Path)

    # Resultados
    static_result: Optional[AnalysisResult] = None
    dynamic_result: Optional[AnalysisResult] = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "analysisType": self.analysis_type.value,
            "status": self.status.value,
            "error": self.error,
            "staticResult": asdict(self.static_result) if self.static_result else None,
            "dynamicResult": asdict(self.dynamic_result) if self.dynamic_result else None,
        }


_JOBS: Dict[str, AnalysisJob] = {}
_JOBS_LOCK = threading.Lock()


def _ensure_jobs_dir() -> Path:
    base = config.SANDBOX_JOBS_DIR
    base.mkdir(parents=True, exist_ok=True)
    return base


def create_job(file_name: str, contents: bytes, analysis_type: AnalysisType) -> AnalysisJob:
    jobs_root = _ensure_jobs_dir()
    job_id = str(uuid.uuid4())
    base_dir = jobs_root / job_id
    base_dir.mkdir(parents=True, exist_ok=True)

    sample_path = base_dir / file_name
    sample_path.write_bytes(contents)

    # Persistência/auditoria básica
    try:
        sha = job_store.sha256_bytes(contents)
        job_store.insert_job(
            job_id=job_id,
            analysis_type=analysis_type.value,
            file_name=file_name,
            sha256=sha,
            status=JobStatus.QUEUED.value,
        )
    except Exception:
        # Não falhar o pipeline por problemas de DB
        pass

    output_dir = base_dir / "out"
    output_dir.mkdir(exist_ok=True)

    job = AnalysisJob(
        id=job_id,
        analysis_type=analysis_type,
        status=JobStatus.QUEUED,
        base_dir=base_dir,
        sample_path=sample_path,
        output_dir=output_dir,
    )

    with _JOBS_LOCK:
        _JOBS[job_id] = job

    # Se houver Redis configurado, enfileirar para worker RQ;
    # caso contrário, correr em thread local (modo dev).
    if is_queue_enabled():
        q = get_queue("analysis")
        q.enqueue(_run_job, job_id)
    else:
        t = threading.Thread(target=_run_job, args=(job_id,), daemon=True)
        t.start()

    return job


def get_job(job_id: str) -> Optional[AnalysisJob]:
    with _JOBS_LOCK:
        return _JOBS.get(job_id)


def _run_job(job_id: str) -> None:
    job = get_job(job_id)
    if not job:
        return

    job.status = JobStatus.RUNNING
    try:
        job_store.update_status(job.id, JobStatus.RUNNING.value)
    except Exception:
        pass

    try:
        if job.analysis_type in (AnalysisType.STATIC, AnalysisType.BOTH):
            job.static_result = _run_static(job)

        if job.analysis_type in (AnalysisType.DYNAMIC, AnalysisType.BOTH):
            job.dynamic_result = _run_dynamic(job)

        job.status = JobStatus.COMPLETED
        try:
            job_store.update_results(
                job.id,
                asdict(job.static_result) if job.static_result else None,
                asdict(job.dynamic_result) if job.dynamic_result else None,
            )
            job_store.update_status(job.id, JobStatus.COMPLETED.value, error=None)
        except Exception:
            pass
    except Exception as exc:  # noqa: BLE001
        job.status = JobStatus.FAILED
        job.error = str(exc)
        try:
            job_store.update_status(job.id, JobStatus.FAILED.value, error=job.error)
            job_store.update_results(
                job.id,
                asdict(job.static_result) if job.static_result else None,
                asdict(job.dynamic_result) if job.dynamic_result else None,
            )
        except Exception:
            pass


def get_job_payload(job_id: str) -> Optional[dict]:
    """
    Devolve payload do job. Primeiro tenta memória (jobs em execução),
    depois cai para a DB (histórico).
    """
    j = get_job(job_id)
    if j:
        return j.to_dict()
    try:
        row = job_store.get_job_row(job_id)
        if not row:
            return None
        # Compatibilizar com o formato do frontend (staticResult/dynamicResult já vêm)
        return {
            "id": row["id"],
            "analysisType": row["analysisType"],
            "status": row["status"],
            "error": row.get("error"),
            "staticResult": row.get("staticResult"),
            "dynamicResult": row.get("dynamicResult"),
            "fileName": row.get("fileName"),
            "sha256": row.get("sha256"),
            "createdAt": row.get("createdAt"),
            "updatedAt": row.get("updatedAt"),
        }
    except Exception:
        return None


def _run_static(job: AnalysisJob) -> AnalysisResult:
    """Executa a análise estática reutilizando o RATAnalyzer existente."""
    ext = job.sample_path.suffix.lower()
    analyzer = RATAnalyzer(
        str(job.sample_path),
        output_dir=str(job.output_dir),
        use_dotnet_decompiler=(ext in (".exe", ".dll")),
    )
    results = analyzer.analyze()

    last_path = job.output_dir / "last_analysis.json"
    report_content = ""
    c_code = ""
    il_code = ""
    flagged_indicators: list[str] = []

    if last_path.exists():
        import json

        with open(last_path, encoding="utf-8") as f:
            last = json.load(f)

        report_path = last.get("report_path")
        report_content = _read_file_safe(report_path)
        flagged_indicators = last.get("flagged_indicators") or []

        deobf = last.get("deobfuscated_file")
        consolidated = last.get("consolidated_file")
        decompiled_c = last.get("decompiled_c_file")
        if deobf:
            c_code = _read_file_safe(deobf)
        if not c_code and consolidated:
            c_code = _read_file_safe(consolidated)
        if not c_code and decompiled_c:
            c_code = _read_file_safe(decompiled_c)
        if not c_code and last.get("decompilation_error_summary"):
            c_code = f"# Descompilação não disponível\n{last.get('decompilation_error_summary')}"

        disasm = last.get("disassembly_file")
        if disasm:
            il_code = _read_file_safe(disasm, errors="replace")
        if not il_code:
            il_code = "# Nenhum bytecode/assembly disponível para este ficheiro."
    else:
        report_content = "# Relatório não gerado."
        c_code = "# Código não disponível."
        il_code = "# Bytecode não disponível."

    return AnalysisResult(
        report=report_content,
        cCode=c_code,
        ilCode=il_code,
        fileName=job.sample_path.name,
        riskScore=int(results.get("risk_score", 0)),
        riskLevel=str(results.get("risk_level", "")),
        flaggedIndicators=flagged_indicators,
    )


def _run_dynamic(job: AnalysisJob) -> AnalysisResult:
    """
    Executa a análise dinâmica via orquestrador de VMs.

    A lógica concreta de sandboxing está em vm_orchestrator.run_dynamic_analysis,
    que atualmente devolve um relatório sintético (stub seguro). Quando a
    sandbox real estiver ligada, essa função passará a falar com o hypervisor.
    """
    result = run_dynamic_analysis(job)
    summary = str(result.get("summary", ""))
    dynamic_report = result.get("behavior") or {}
    # Guardar também o driver para auditoria/depuração simples.
    if "driver" in result and isinstance(dynamic_report, dict):
        dynamic_report.setdefault("driver", result.get("driver"))
    return AnalysisResult(
        fileName=job.sample_path.name,
        dynamicReport=dynamic_report,
        dynamicSummary=summary,
    )


def _read_file_safe(path: Optional[str | Path], encoding: str = "utf-8", errors: str = "replace") -> str:
    if not path:
        return ""
    p = Path(path)
    if not p.exists():
        return ""
    try:
        with open(p, encoding=encoding, errors=errors) as f:
            return f.read()
    except Exception:  # noqa: BLE001
        return ""

