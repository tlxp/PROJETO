// --- Módulo: ResultadosPage.tsx ---
// Redireciona rota legada /resultados?jobId= para /analysis/:jobId.

import { Navigate, useLocation } from "react-router-dom";
import { ROUTES } from "@/routes";

// --- Componente ---
const ResultadosRedirect = () => {
  const location = useLocation();
  const jobId = new URLSearchParams(location.search ?? "").get("jobId");

  if (jobId) {
    return <Navigate to={ROUTES.analysis(jobId)} replace />;
  }
  return <Navigate to={ROUTES.home} replace />;
};

export default ResultadosRedirect;
