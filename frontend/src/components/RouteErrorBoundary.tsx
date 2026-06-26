// --- Módulo: RouteErrorBoundary.tsx ---
// Error boundary por rota para isolar falhas de uma página.

import React, { Component, type ErrorInfo, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { AlertTriangle } from "lucide-react";

type RouteErrorBoundaryProps = {
  children: ReactNode;
  // *Nome da rota para contexto no fallback*
  routeName?: string;
};

type RouteErrorBoundaryState = {
  error: Error | null;
};

// --- Componente ---
export class RouteErrorBoundary extends Component<
  RouteErrorBoundaryProps,
  RouteErrorBoundaryState
> {
  state: RouteErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): RouteErrorBoundaryState {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error(
      `[RouteErrorBoundary${this.props.routeName ? `: ${this.props.routeName}` : ""}]`,
      error,
      info.componentStack
    );
  }

  private handleRetry = (): void => {
    this.setState({ error: null });
  };

  render(): ReactNode {
    const { error } = this.state;
    if (!error) {
      return this.props.children;
    }

    const label = this.props.routeName ?? "esta página";

    return (
      <div className="flex min-h-screen items-center justify-center bg-background p-6">
        <div className="w-full max-w-lg rounded-lg border border-destructive/40 bg-destructive/5 p-6 shadow-sm">
          <div className="mb-4 flex items-center gap-3">
            <AlertTriangle className="h-6 w-6 shrink-0 text-destructive" aria-hidden />
            <h1 className="text-lg font-semibold text-foreground">
              Erro ao carregar {label}
            </h1>
          </div>
          <p className="mb-3 text-sm text-muted-foreground">
            Ocorreu um erro inesperado nesta vista. Pode tentar novamente ou voltar ao início.
          </p>
          {error.message ? (
            <pre className="mb-4 max-h-32 overflow-auto rounded border border-border/60 bg-muted/40 p-3 text-[11px] font-mono text-foreground whitespace-pre-wrap break-words">
              {error.message}
            </pre>
          ) : null}
          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={this.handleRetry}
              className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
            >
              Tentar novamente
            </button>
            <Link
              to="/"
              className="inline-flex items-center rounded-md border border-border px-4 py-2 text-sm font-medium text-foreground hover:bg-muted"
            >
              Voltar ao início
            </Link>
          </div>
        </div>
      </div>
    );
  }
}

// --- Helper de rota ---
export function withRouteBoundary(
  routeName: string,
  element: ReactNode
): ReactNode {
  return <RouteErrorBoundary routeName={routeName}>{element}</RouteErrorBoundary>;
}
