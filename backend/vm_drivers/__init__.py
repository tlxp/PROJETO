# --- Módulo: __init__ ---
# Drivers de VM para análise dinâmica em sandbox.

from __future__ import annotations

import warnings

from .base import VMDriver
from .stub import StubVMDriver

__all__ = ["VMDriver", "StubVMDriver", "EXPERIMENTAL_DRIVERS"]

# *Drivers não validados para produção — ver docs/README.md*
EXPERIMENTAL_DRIVERS = frozenset({"proxmox"})


# --- Aviso quando driver experimental está activo ---
def warn_if_experimental(driver_name: str) -> None:
    if driver_name in EXPERIMENTAL_DRIVERS:
        warnings.warn(
            f"SANDBOX_VM_DRIVER={driver_name} é EXPERIMENTAL — sem guia nem testes de integração no CI. "
            "Use hyperv (Caminho A) ou PowerShell Hyper-V (Caminho B) em produção.",
            stacklevel=3,
        )
