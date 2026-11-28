// Application — decisão de acesso ao portal (guarda servidor).
// Pura: quem orquestra (Server Components/Actions) traduz a decisão em
// redirect ou render de estado. Testável sem framework.
import type { Membership } from "../domain/membership";
import { canAccessArea } from "../domain/portal-areas";
import type { Role } from "../domain/role";
import { resolveActiveTenant } from "./tenant-selection";

export interface PortalAccessInput {
  session: { userId: string } | null;
  memberships: readonly Membership[];
  cookieTenantId: string | null;
  requiredRoles: readonly Role[];
  areaId: string;
}

export type PortalAccessDecision =
  | { status: "ok"; membership: Membership; role: Role }
  | { status: "login" }
  | { status: "no-membership" }
  | { status: "select-tenant" }
  | { status: "forbidden" };

export function decidePortalAccess(input: PortalAccessInput): PortalAccessDecision {
  if (!input.session) return { status: "login" };
  if (input.memberships.length === 0) return { status: "no-membership" };

  const membership = resolveActiveTenant(input.memberships, input.cookieTenantId);
  if (!membership) return { status: "select-tenant" };

  if (!canAccessArea(membership.role, input.areaId)) return { status: "forbidden" };
  if (!input.requiredRoles.includes(membership.role)) return { status: "forbidden" };

  return { status: "ok", membership, role: membership.role };
}
