import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Agenda · Agenda SaaS" };

export default function AgendaPage() {
  return (
    <PortalPage area="agenda">
      <h1>Agenda</h1>
      <EmptyState
        title="Nenhuma reserva por aqui"
        description="Quando houver reservas na empresa ativa, elas aparecem nesta tela."
      >
        <ul>
          <li>Cadastre os serviços no catálogo (área Serviços).</li>
          <li>Defina o expediente dos profissionais (área Expediente).</li>
          <li>As reservas criadas pela recepção ou pelo WhatsApp entram aqui.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
