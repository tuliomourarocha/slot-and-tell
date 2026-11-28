import { redirect } from "next/navigation";

import { firstAreaForRole, getActiveMembership, listMemberships } from "@/modules/auth";

// Início do portal: com empresa ativa, vai direto para a primeira área do
// papel; sem empresa ativa, vai para a seleção (≤ 2 cliques do login).
export default async function PortalIndexPage() {
  const memberships = await listMemberships();
  const active = await getActiveMembership(memberships);
  if (!active) redirect("/portal/selecionar-empresa");

  const firstArea = firstAreaForRole(active.role);
  redirect(firstArea?.href ?? "/portal/selecionar-empresa");
}
