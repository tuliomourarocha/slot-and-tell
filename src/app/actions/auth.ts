"use server";

// Actions do portal: login, troca de empresa ativa e logout. Único lugar fora
// do módulo auth autorizado a escrever o cookie `active-tenant` — e sempre
// depois de validar o vínculo no banco (cookie forjado é rejeitado).
import { redirect } from "next/navigation";

import {
  createSupabaseServerClient,
  getSession,
  listMemberships,
  signOut,
  writeActiveTenantCookie,
} from "@/modules/auth";

export interface SignInState {
  error: string | null;
}

// Mensagem única, sem expor a causa (conta inexistente vs senha errada).
const GENERIC_ERROR = "E-mail ou senha inválidos. Confira os dados e tente de novo.";

/** Login e-mail/senha. Sucesso → redirect; falha → erro inline genérico. */
export async function signInAction(_prev: SignInState, formData: FormData): Promise<SignInState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const nextRaw = String(formData.get("next") ?? "/portal");
  // `next` só aceita caminho interno (evita open redirect).
  const next = nextRaw.startsWith("/") && !nextRaw.startsWith("//") ? nextRaw : "/portal";

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return { error: GENERIC_ERROR };
  }

  redirect(next);
}

export async function selectActiveTenantAction(formData: FormData): Promise<void> {
  const session = await getSession();
  if (!session) redirect("/login");

  const tenantId = String(formData.get("tenantId") ?? "");
  const memberships = await listMemberships();
  const match = memberships.find((membership) => membership.tenantId === tenantId);
  if (!match) {
    // Empresa sem vínculo: devolve à seleção com aviso (critério de aceite 3).
    redirect("/portal/selecionar-empresa?aviso=vinculo-invalido");
  }

  await writeActiveTenantCookie(match.tenantId);
  redirect("/portal");
}

export async function signOutAction(): Promise<void> {
  await signOut();
  redirect("/login");
}
