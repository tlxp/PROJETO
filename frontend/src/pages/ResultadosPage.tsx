/**
 * Página dedicada a /resultados.
 * Reutiliza o Index para mostrar as 3 colunas (C, IL, Relatório) quando há jobId na query string.
 * O fallback SPA no Vite (spaHistoryFallback) garante que este path seja servido com index.html.
 */
import Index from "./Index";

const ResultadosPage = () => <Index />;

export default ResultadosPage;
