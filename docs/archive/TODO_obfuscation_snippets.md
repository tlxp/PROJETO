# TODO: Trechos obfuscados — estado e pendentes

> ⚠ **Documento arquivado** — tarefas concluídas. Consulte [`docs/README.md`](../README.md) e `backend/modules/obfuscation_snippet_extractor.py` · API `GET /api/analysis/{job_id}/artifacts/obfuscated_snippets`.

Objetivo original: guardar trechos onde foi detetada obfuscação em ficheiro separado e deobfuscar esses trechos; integrar na pipeline, relatório e API.

---

## Implementado (resumo)

- **Módulo** `backend/modules/obfuscation_snippet_extractor.py`: deteção com posição, escrita de `{stem}.obfuscated_snippets.txt` e `{stem}.obfuscated_snippets_deobfuscated.txt`, limites (MAX_SNIPPETS, CONTEXT_LINES), reutilização de `Deobfuscator.deobfuscate_content`.
- **Pipeline** `rat_analyzer.py`: extração a partir do C# consolidado e do pseudo-C (Ghidra); campos em `last_analysis.json` e `analysis_results`.
- **Relatório** `report_generator.py`: secção “Trechos obfuscados extraídos” com caminhos e resumo por tipo.
- **API**: payload estático com `obfuscatedSnippetsFile` / `obfuscatedSnippetsDeobfuscatedFile`; endpoint `GET /api/analysis/{job_id}/artifacts/obfuscated_snippets?variant=obfuscated|deobfuscated`.
- **Frontend**: botões “Ver trechos obfuscados” / “Ver trechos deobfuscados” na página de resultados quando existem.
- **Testes** `backend/tests/test_obfuscation_snippet_extractor.py`: deteção com posição, escrita dos dois ficheiros.
- **Config** `backend/config.py`: `OBFUSCATION_SNIPPETS_MAX`, `OBFUSCATION_SNIPPET_MAX_LINES`, `OBFUSCATION_CONTEXT_LINES`.

---

## Pendente (opcional)

### Binário: gravar regiões XOR em ficheiro (Fase 5.2)

Em `deobfuscator.py`, dentro de `_try_xor_patch_sections` (ou função chamada por ela):

- Para cada região que for patched, gravar num ficheiro (ex. `{stem}.obfuscated_binary_regions.txt` ou `.bin`) a lista de (offset, tamanho, bytes_originais, bytes_deobfuscados), ou bytes_originais numa secção e bytes_deobfuscados noutra, com cabeçalhos claros.
- Assim “guardar trecho obfuscado” fica satisfeito também a nível binário (além do código fonte C#/pseudo-C já coberto).

Prioridade: baixa; o fluxo atual cobre trechos em código fonte.
