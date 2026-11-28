import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Atendimento · Agenda SaaS" };

export default function AtendimentoPage() {
  return (
    <PortalPage area="atendimento">
      <h1>Atendimento</h1>
      <EmptyState
        title="Nenhum cliente registrado"
        description="Clientes e histórico de atendimento aparecerão aqui quando houver registros."
      >
        <ul>
          <li>O cadastro de clientes será aberto na próxima fase do portal.</li>
          <li>O WhatsApp registra clientes automaticamente ao receber mensagens.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
