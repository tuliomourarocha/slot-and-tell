import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Configurações · Agenda SaaS" };

export default function ConfiguracoesPage() {
  return (
    <PortalPage area="configuracoes">
      <h1>Configurações</h1>
      <EmptyState
        title="Nada para configurar ainda"
        description="Os parâmetros da empresa (horários, políticas e equipe) serão editáveis na próxima fase."
      >
        <ul>
          <li>Fuso horário, moeda e janela de agendamento da empresa.</li>
          <li>Vínculos da equipe: quem entra, com qual papel.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
