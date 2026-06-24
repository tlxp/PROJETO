// --- Módulo: App.tsx ---
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { withRouteBoundary } from "@/components/RouteErrorBoundary";
import { getT } from "@/i18n";
import { ROUTE_PATTERNS } from "@/routes";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import ResultadosRedirect from "./pages/ResultadosPage";
import XrefExplorerPage from "./pages/XrefExplorerPage";
import NotFound from "./pages/NotFound";

// --- Componente raiz com router e providers globais ---
const App = () => (
  <TooltipProvider>
    <Toaster />
    <BrowserRouter
      future={{
        v7_startTransition: true,
        v7_relativeSplatPath: true,
      }}
    >
      <Routes>
        <Route path={ROUTE_PATTERNS.home} element={withRouteBoundary(getT("routeHome"), <Index />)} />
        <Route path={ROUTE_PATTERNS.analysis} element={withRouteBoundary(getT("routeAnalysis"), <Index />)} />
        <Route
          path={ROUTE_PATTERNS.analysisXref}
          element={withRouteBoundary(getT("routeXref"), <XrefExplorerPage />)}
        />
        <Route
          path={ROUTE_PATTERNS.resultadosLegacy}
          element={withRouteBoundary(getT("routeResults"), <ResultadosRedirect />)}
        />
        <Route
          path={ROUTE_PATTERNS.xrefLegacy}
          element={withRouteBoundary(getT("routeXref"), <XrefExplorerPage />)}
        />
        <Route path={ROUTE_PATTERNS.notFound} element={withRouteBoundary(getT("routePage"), <NotFound />)} />
      </Routes>
    </BrowserRouter>
  </TooltipProvider>
);

export default App;
