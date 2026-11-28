import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { ConflictState, EmptyState } from "@/components/ui";
import { signOutAction, selectActiveTenantAction } from "@/app/actions/auth";
import {
  getActiveMembership,
  getSession,
  listMemberships,
  ROLE_LABELS,
} from "@/modules/auth";

import styles from "./selecionar-empresa.module.css";

export const metadata: Metadata = {
  title: "Selecionar empresa · Agenda SaaS",
};

export default async function SelecionarEmpresaPage({
  searchParams,
}: {
  searchParams: Promise<{ aviso?: string }>;
}) {
  const [{ aviso }, session] = await Promise.all([searchParams, getSession()]);
  if (!session) redirect("/login");

  const memberships = await listMemberships();
  if (memberships.length === 0) {
    return (
      <main className={styles.main}>
        <div className={styles.card}>
          <h1 className={styles.title}>Selecionar empresa</h1>
          <EmptyState
            title="Nenhuma empresa vinculada"
            description="Sua conta não está vinculada a nenhuma empresa ainda. Peça a um administrador para cadastrar o vínculo."
          >
            <form action={signOutAction}>
              <button type="submit" className={styles.logout}>
                Sair
              </button>
            </form>
          </EmptyState>
        </div>
      </main>
    );
  }

  const active = await getActiveMembership(memberships);

  return (
    <main className={styles.main}>
      <div className={styles.card}>
        <h1 className={styles.title}>Selecionar empresa</h1>
        <p className={styles.hint}>
          Você tem vínculo em{" "}
          {memberships.length === 1 ? "uma empresa" : `${memberships.length} empresas`}. Escolha com
          qual quer trabalhar.
        </p>
        {aviso === "vinculo-invalido" ? (
          <ConflictState description="A empresa selecionada não corresponde a nenhum dos seus vínculos. Escolha novamente abaixo." />
        ) : null}
        <ul className={styles.list}>
          {memberships.map((membership) => (
            <li key={membership.tenantId}>
              <form action={selectActiveTenantAction}>
                <input type="hidden" name="tenantId" value={membership.tenantId} />
                <button
                  type="submit"
                  className={`${styles.itemButton} ${
                    active?.tenantId === membership.tenantId ? styles.active : ""
                  }`}
                  aria-current={active?.tenantId === membership.tenantId ? "true" : undefined}
                >
                  <span className={styles.tenantName}>{membership.tenantName}</span>
                  <span className={styles.roleTag}>{ROLE_LABELS[membership.role]}</span>
                </button>
              </form>
            </li>
          ))}
        </ul>
        <div className={styles.footer}>
          <form action={signOutAction}>
            <button type="submit" className={styles.logout}>
              Sair da conta
            </button>
          </form>
        </div>
      </div>
    </main>
  );
}
