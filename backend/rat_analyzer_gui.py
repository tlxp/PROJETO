#!/usr/bin/env python3
# --- Módulo: rat_analyzer_gui ---
# DEPRECATED (legacy): wrapper fino — delega em gui.tkinter_app.main().
#
# Este ficheiro existe apenas para manter o comando habitual:
#   python rat_analyzer_gui.py
# A implementação está em gui/tkinter_app.py. Ver gui/README.md para substitutos
# (frontend web e WPF).

from gui.tkinter_app import main

if __name__ == "__main__":
    main()
