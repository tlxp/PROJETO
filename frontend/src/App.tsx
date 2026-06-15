import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { withRouteBoundary } from "@/components/RouteErrorBoundary";
import { ROUTE_PATTERNS } from "@/routes";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import Index from "./pages/Index";
import ResultadosRedirect from "./pages/ResultadosPage";
import XrefExplorerPage from "./pages/XrefExplorerPage";
import NotFound from "./pages/NotFound";

const App = () => (
  <TooltipProvider>
    <Toaster />
    <BrowserRouter>
      <Routes>
        <Route path={ROUTE_PATTERNS.home} element={withRouteBoundary("Início", <Index />)} />
        <Route path={ROUTE_PATTERNS.analysis} element={withRouteBoundary("Análise", <Index />)} />
        <Route
          path={ROUTE_PATTERNS.analysisXref}
          element={withRouteBoundary("Explorador Xref", <XrefExplorerPage />)}
        />
        <Route
          path={ROUTE_PATTERNS.resultadosLegacy}
          element={withRouteBoundary("Resultados", <ResultadosRedirect />)}
        />
        <Route
          path={ROUTE_PATTERNS.xrefLegacy}
          element={withRouteBoundary("Explorador Xref", <XrefExplorerPage />)}
        />
        <Route path={ROUTE_PATTERNS.notFound} element={withRouteBoundary("Página", <NotFound />)} />
      </Routes>
    </BrowserRouter>
  </TooltipProvider>
);

export default App;
