// --- Módulo: GeminiIcon.tsx ---
// Símbolo estilizado do Gemini (estrela de quatro pontas).

import React from "react";

type GeminiIconProps = {
  className?: string;
};

// --- Componente ---
const GeminiIcon: React.FC<GeminiIconProps> = ({ className }) => (
  <svg
    className={className}
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true"
  >
    <path
      d="M12 2.5L14.2 9.1L20.8 11.3L14.2 13.5L12 20.1L9.8 13.5L3.2 11.3L9.8 9.1L12 2.5Z"
      fill="url(#gemini-gradient)"
    />
    <defs>
      <linearGradient id="gemini-gradient" x1="3" y1="2" x2="21" y2="20" gradientUnits="userSpaceOnUse">
        <stop stopColor="#4285F4" />
        <stop offset="0.5" stopColor="#9B72F2" />
        <stop offset="1" stopColor="#D96570" />
      </linearGradient>
    </defs>
  </svg>
);

export default GeminiIcon;
