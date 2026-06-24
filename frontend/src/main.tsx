// --- Módulo: main.tsx ---
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import { I18nProvider } from "./i18n";
import "./index.css";

// --- Ponto de entrada da SPA ---
createRoot(document.getElementById("root")!).render(
  <I18nProvider>
    <App />
  </I18nProvider>
);
