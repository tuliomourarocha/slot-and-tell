// Application — sessão e vínculos (casos de uso do portal).
// Orquestra clients de infrastructure e converte linhas do banco em entidades
// de domínio. Nada de ORM/SDK vaza para fora do módulo.
import type { Membership } from "../domain/membership";
import { parseRole } from "../domain/role";
import { createSupabaseServerClient } from "../infrastructure/supabase-server-client";
import { readActiveTenantCookie, clearActiveTenantCookie } from "../infrastructure/active-tenant-cookie";
import { resolveActiveTenant } from "./tenant-selection";

export interface SessionUser {
  id: string;
  email: string | null;
  name: string | null;
}

export async function getSession(): Promise<SessionUser | null> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  return {
    id: user.id,
    email: user.email ?? null,
    name: (user.user_metadata.name as string | undefined) ?? null,
  };
}

/** Vínculos do usuário logado via RPC SECURITY DEFINER (validação no banco). */
export async function listMemberships(): Promise<Membership[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("list_my_memberships");
  if (error) throw new Error(`Não foi possível carregar os vínculos: ${error.message}`);
  return (data ?? []).map((row) => ({
    tenantId: row.tenant_id,
    tenantName: row.tenant_name,
    role: parseRole(row.role),
    professionalId: row.professional_id,
  }));
}

/** Empresa ativa revalidada contra os vínculos (cookie forjado é rejeitado). */
export async function getActiveMembership(memberships: readonly Membership[]): Promise<Membership | null> {
  const cookieTenantId = await readActiveTenantCookie();
  return resolveActiveTenant(memberships, cookieTenantId);
}

/** Encerra a sessão no Auth e limpa cookie de empresa ativa. */
export async function signOut(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  await clearActiveTenantCookie();
}
