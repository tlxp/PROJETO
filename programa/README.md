# Pasta `programa/` - projetos .NET de exemplo (opcional)

Área **opcional** do repositório para pequenos projetos C# usados em testes manuais ou na [GUI Tkinter](../backend/gui/README.md) (*arrastar `.cs` → compilar → analisar*).

## Projeto incluído

| Projeto | Descrição |
|---------|-----------|
| [`MeuExemplo/`](MeuExemplo/) | Console .NET 8 com `HttpClient` - ideal para testar compilação e análise estática |

```powershell
cd programa/MeuExemplo
dotnet build -c Release
python ../../backend/rat_analyzer.py bin/Release/net8.0/MeuExemplo.dll -o reports/ -v
```

Ou arraste `MeuExemplo/Program.cs` para a GUI Tkinter e use **Compilar (dotnet publish)**.

## O que colocar aqui

- Projetos `.csproj` adicionais para experimentar o pipeline de análise estática.
- Não versionar `bin/`, `obj/` nem executáveis gerados — são ignorados pelo Git e removidos por `python backend/clean.py`.

## Solução .NET

`MeuExemplo` está incluído em `RatAnalyzer.sln` (pasta de solução `programa/`):

```powershell
dotnet build programa/MeuExemplo/MeuExemplo.csproj -c Release
# ou, na raiz:
dotnet build RatAnalyzer.sln -c Release
```

## Estrutura

```
programa/
├── README.md          # este ficheiro
└── MeuExemplo/
    ├── MeuExemplo.csproj
    └── Program.cs
```

## Configuração

O caminho é referenciado em `backend/config.py` como `SAMPLE_PROJECT_DIR`. Se a pasta não existir, o analisador funciona normalmente - apenas a limpeza de `programa/bin` e `programa/obj` fica inativa.
