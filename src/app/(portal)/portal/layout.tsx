import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { ErrorState } from "@/components/ui";
import { signOutAction } from "@/app/actions/auth";
import { getSession, listMemberships } from "@/modules/auth";

// Guarda base de todo /portal/**: sessão e ao menos um vínculo. O papel e a
// empresa ativa são validados mais adiante (shell e páginas) — e sempre de
// novo no banco via RPC/RLS.
export const dynamic = "force-dynamic";

export default async function PortalBaseLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (!session) redirect("/login");

  const memberships = await listMemberships();
  if (memberships.length === 0) {
    return (
      <main>
        <ErrorState
          title="Nenhum vínculo de equipe"
          description={`A conta ${session.email ?? ""} existe, mas não está vinculada a nenhuma empresa. Peça a um administrador para cadastrar o vínculo.`}
        >
          <form action={signOutAction}>
            <button type="submit">Sair</button>
          </form>
        </ErrorState>
      </main>
    );
  }

  return <>{children}</>;
}
