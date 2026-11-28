import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { ForbiddenState } from "@/components/ui";
import {
  canAccessArea,
  PORTAL_AREAS,
  getActiveMembership,
  getSession,
  listMemberships,
} from "@/modules/auth";

interface PortalPageProps {
  /** id da área em PORTAL_AREAS (ex.: "agenda", "servicos"). */
  area: string;
  children: ReactNode;
}

// Guarda fina de cada página de área: papel validado no servidor contra a
// matriz D3. O banco valida de novo via RPC/RLS nos dados (defesa em camada).
export default async function PortalPage({ area, children }: PortalPageProps) {
  const session = await getSession();
  if (!session) redirect("/login");

  const memberships = await listMemberships();
  const active = await getActiveMembership(memberships);
  if (!active) redirect("/portal/selecionar-empresa");

  if (!canAccessArea(active.role, area)) {
    const areaLabel = PORTAL_AREAS.find((entry) => entry.id === area)?.label;
    return areaLabel ? <ForbiddenState areaLabel={areaLabel} /> : <ForbiddenState />;
  }

  return <>{children}</>;
}
