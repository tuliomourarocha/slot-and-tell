import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Equipe · Agenda SaaS" };

export default function EquipePage() {
  return (
    <PortalPage area="equipe">
      <h1>Equipe</h1>
      <EmptyState
        title="Nenhum profissional cadastrado"
        description="O cadastro de profissionais será aberto na próxima fase do portal."
      >
        <ul>
          <li>Cadastre cada profissional da agenda com nome e status ativo.</li>
          <li>Vínculos de equipe (login) são gerenciados nas Configurações.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
