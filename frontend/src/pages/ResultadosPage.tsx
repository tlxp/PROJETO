/**
 * Rota legada /resultados?jobId=... mantida por compatibilidade.
 * Redireciona para a rota canónica /analysis/:jobId (ou para a landing page sem jobId).
 */
import { Navigate, useLocation } from "react-router-dom";
import { ROUTES } from "@/routes";

const ResultadosRedirect = () => {
  const location = useLocation();
  const jobId = new URLSearchParams(location.search ?? "").get("jobId");

  if (jobId) {
    return <Navigate to={ROUTES.analysis(jobId)} replace />;
  }
  return <Navigate to={ROUTES.home} replace />;
};

export default ResultadosRedirect;
