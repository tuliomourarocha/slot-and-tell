import type { ReactNode } from "react";
import { redirect } from "next/navigation";

import { signOutAction } from "@/app/actions/auth";
import {
  areasForRole,
  getActiveMembership,
  getSession,
  listMemberships,
  ROLE_LABELS,
} from "@/modules/auth";

import { PortalNav } from "./portal-nav";
import styles from "./shell.module.css";

// Shell do portal (T7): sidebar por papel + header com empresa ativa.
// Empresa ativa revalidada a cada request (cookie forjado → seleção).
export default async function PortalShellLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (!session) redirect("/login");

  const memberships = await listMemberships();
  if (memberships.length === 0) redirect("/login");

  const active = await getActiveMembership(memberships);
  if (!active) redirect("/portal/selecionar-empresa");

  const areas = areasForRole(active.role);
  const userName = session.name ?? session.email ?? "";

  return (
    <div className={styles.shell}>
      <a href="#conteudo" className={styles.skipLink}>
        Pular para o conteúdo
      </a>
      <aside className={styles.sidebar}>
        <a href="/portal" className={styles.brand}>
          Agenda SaaS
        </a>
        <PortalNav areas={areas} />
      </aside>
      <div className={styles.main}>
        <header className={styles.header}>
          <span className={styles.tenantPill}>
            <span className={styles.tenantName}>{active.tenantName}</span>
            <span className={styles.tenantRole}>· {ROLE_LABELS[active.role]}</span>
          </span>
          <span className={styles.headerRight}>
            {userName ? (
              <span className={styles.tenantRole}>{userName}</span>
            ) : null}
            <form action={signOutAction}>
              <button type="submit" className={styles.logoutButton}>
                Sair
              </button>
            </form>
          </span>
        </header>
        <main id="conteudo" className={styles.content}>
          {children}
        </main>
      </div>
    </div>
  );
}
