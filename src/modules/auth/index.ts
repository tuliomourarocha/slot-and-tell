// Fronteira pública do módulo "auth". Exporte apenas o contrato estável;
// módulos não importam internals uns dos outros (ver README, seção Arquitetura).
export const MODULE_NAME = "auth" as const;

// Domínio
export { ROLES, ROLE_LABELS, type Role, isRole, parseRole } from "./domain/role";
export type { Membership } from "./domain/membership";
export {
  PORTAL_AREAS,
  areasForRole,
  canAccessArea,
  firstAreaForRole,
  type PortalArea,
} from "./domain/portal-areas";

// Application
export {
  getSession,
  getActiveMembership,
  listMemberships,
  signOut,
  type SessionUser,
} from "./application/session";
export { resolveActiveTenant } from "./application/tenant-selection";
export { decidePortalAccess, type PortalAccessDecision, type PortalAccessInput } from "./application/role-guard";

// Infrastructure exposto por contrato: cookie de empresa ativa (escrito apenas
// em Server Actions) e clientes Supabase para Client Components / route
// handlers fora do módulo.
export {
  ACTIVE_TENANT_COOKIE,
  clearActiveTenantCookie,
  writeActiveTenantCookie,
} from "./infrastructure/active-tenant-cookie";
export { createSupabaseServerClient } from "./infrastructure/supabase-server-client";
