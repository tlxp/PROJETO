// --- Módulo: route-error-boundary.test.tsx ---
// Testes do error boundary por rota.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { RouteErrorBoundary } from "@/components/RouteErrorBoundary";

function ThrowOnce({ shouldThrow }: { shouldThrow: boolean }) {
  if (shouldThrow) {
    throw new Error("falha de teste");
  }
  return <span>conteúdo ok</span>;
}

describe("RouteErrorBoundary", () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

  beforeEach(() => {
    consoleError.mockClear();
  });

  afterEach(() => {
    consoleError.mockClear();
  });

  it("renderiza filhos quando não há erro", () => {
    render(
      <MemoryRouter>
        <RouteErrorBoundary routeName="Teste">
          <ThrowOnce shouldThrow={false} />
        </RouteErrorBoundary>
      </MemoryRouter>
    );
    expect(screen.getByText("conteúdo ok")).toBeInTheDocument();
  });

  it("mostra fallback quando um filho lança erro", () => {
    render(
      <MemoryRouter>
        <RouteErrorBoundary routeName="Teste">
          <ThrowOnce shouldThrow />
        </RouteErrorBoundary>
      </MemoryRouter>
    );
    expect(screen.getByText(/Erro ao carregar Teste/i)).toBeInTheDocument();
    expect(screen.getByText("falha de teste")).toBeInTheDocument();
  });

  it("permite tentar novamente após erro", async () => {
    let throwNext = true;
    function MaybeThrow() {
      if (throwNext) {
        throw new Error("boom");
      }
      return <span>recuperado</span>;
    }

    render(
      <MemoryRouter>
        <RouteErrorBoundary routeName="Retry">
          <MaybeThrow />
        </RouteErrorBoundary>
      </MemoryRouter>
    );

    expect(screen.getByText(/Erro ao carregar Retry/i)).toBeInTheDocument();
    throwNext = false;
    fireEvent.click(screen.getByRole("button", { name: /Tentar novamente/i }));
    await waitFor(() => {
      expect(screen.getByText("recuperado")).toBeInTheDocument();
    });
  });
});
