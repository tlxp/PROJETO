import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { withRouteBoundary } from "@/components/RouteErrorBoundary";
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
        <Route path="/" element={withRouteBoundary("Início", <Index />)} />
        {/* Rota canónica com jobId (permalinks) */}
        <Route path="/analysis/:jobId" element={withRouteBoundary("Análise", <Index />)} />
        <Route
          path="/analysis/:jobId/xref"
          element={withRouteBoundary("Explorador Xref", <XrefExplorerPage />)}
        />

        {/* Back-compat: /resultados?jobId=... redireciona para /analysis/:jobId */}
        <Route
          path="/resultados"
          element={withRouteBoundary("Resultados", <ResultadosRedirect />)}
        />
        <Route path="/xref" element={withRouteBoundary("Explorador Xref", <XrefExplorerPage />)} />
        {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
        <Route path="*" element={withRouteBoundary("Página", <NotFound />)} />
      </Routes>
    </BrowserRouter>
  </TooltipProvider>
);

export default App;
