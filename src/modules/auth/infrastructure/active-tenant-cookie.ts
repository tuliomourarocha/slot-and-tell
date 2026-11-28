// Infrastructure — cookie de empresa ativa (decisão D2 do PLAN).
// Valor nunca é confiado: toda leitura é revalidada contra os vínculos do
// usuário (application/tenant-selection.ts). Escrita só via Server Action.
import { cookies } from "next/headers";

export const ACTIVE_TENANT_COOKIE = "active-tenant";

export async function readActiveTenantCookie(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get(ACTIVE_TENANT_COOKIE)?.value ?? null;
}

export async function writeActiveTenantCookie(tenantId: string): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.set(ACTIVE_TENANT_COOKIE, tenantId, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 30,
  });
}

export async function clearActiveTenantCookie(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(ACTIVE_TENANT_COOKIE);
}
