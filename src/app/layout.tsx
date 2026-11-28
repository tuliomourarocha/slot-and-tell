import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "Agenda SaaS",
  description: "Agendamento multiempresa para barbearias, salões, estúdios e clínicas.",
};

export const viewport: Viewport = {
  // Acessibilidade: nunca bloquear zoom (web-interface-guidelines).
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
