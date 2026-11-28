import type { Metadata } from "next";

import { EmptyState } from "@/components/ui";

import PortalPage from "../portal-page";

export const metadata: Metadata = { title: "Expediente · Agenda SaaS" };

export default function ExpedientePage() {
  return (
    <PortalPage area="expediente">
      <h1>Expediente</h1>
      <EmptyState
        title="Nenhuma jornada definida"
        description="O expediente semanal e as ausências serão editáveis na próxima fase."
      >
        <ul>
          <li>Profissionais editam as próprias jornadas e ausências.</li>
          <li>Administração e recepção editam as de toda a empresa.</li>
        </ul>
      </EmptyState>
    </PortalPage>
  );
}
