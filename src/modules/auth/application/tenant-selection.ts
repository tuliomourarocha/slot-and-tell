// Application — resolução de empresa ativa (decisão D2 do PLAN).
// Funções puras: o valor do cookie nunca é confiado, é revalidado contra os
// vínculos vindos do banco (RPC/RLS). Testável sem framework.
import type { Membership } from "../domain/membership";

/**
 * Vínculo da empresa ativa, ou nulo quando é preciso escolher:
 * - cookie com empresa sem vínculo (forjado/expirado) → nulo (devolve à seleção);
 * - sem cookie e vínculo único → o próprio vínculo (login → 1 clique);
 * - sem cookie e vários vínculos → nulo (usuário escolhe).
 */
export function resolveActiveTenant(
  memberships: readonly Membership[],
  cookieTenantId: string | null,
): Membership | null {
  if (memberships.length === 0) return null;
  if (cookieTenantId) {
    return memberships.find((membership) => membership.tenantId === cookieTenantId) ?? null;
  }
  return memberships.length === 1 ? (memberships[0] ?? null) : null;
}
