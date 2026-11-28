import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { getSession } from "@/modules/auth";

import { LoginForm } from "./login-form";
import styles from "./login.module.css";

export const metadata: Metadata = {
  title: "Entrar · Agenda SaaS",
};

export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const [{ next }, session] = await Promise.all([searchParams, getSession()]);
  if (session) redirect("/portal");

  return (
    <main className={styles.main}>
      <div className={styles.card}>
        <h1 className={styles.title}>Entrar no portal</h1>
        <p className={styles.hint}>Use o e-mail e a senha da sua equipe.</p>
        <LoginForm next={next ?? null} />
      </div>
    </main>
  );
}
