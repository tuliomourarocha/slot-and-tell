import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Serviços · Agenda SaaS" };

export default function ServicosPage() {
  return (
    <PortalPage area="servicos">
      <h1>Serviços</h1>
      <EmptyState
        title="Catálogo vazio"
        description="Nenhum serviço cadastrado ainda. O cadastro de serviços será aberto na próxima fase do portal."
      >
        <ul>
          <li>Defina nome, duração e preço de cada serviço.</li>
          <li>Depois, habilite quais profissionais executam cada serviço.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
