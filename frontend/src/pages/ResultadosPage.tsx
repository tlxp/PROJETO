/**
 * Rota legada /resultados?jobId=... mantida por compatibilidade.
 * Redireciona para a rota canónica /analysis/:jobId (ou para a landing page sem jobId).
 */
import { Navigate, useLocation } from "react-router-dom";

const ResultadosRedirect = () => {
  const location = useLocation();
  const jobId = new URLSearchParams(location.search ?? "").get("jobId");

  if (jobId) {
    return <Navigate to={`/analysis/${encodeURIComponent(jobId)}`} replace />;
  }
  return <Navigate to="/" replace />;
};

export default ResultadosRedirect;
