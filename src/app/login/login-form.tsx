"use client";

import { useActionState, useEffect, useRef } from "react";

import { signInAction, type SignInState } from "@/app/actions/auth";

import styles from "./login.module.css";

const initialState: SignInState = { error: null };

export function LoginForm({ next }: { next: string | null }) {
  const [state, formAction, isPending] = useActionState(signInAction, initialState);
  const emailRef = useRef<HTMLInputElement>(null);

  // Erro inline: foco volta ao primeiro campo (checklist de acessibilidade).
  useEffect(() => {
    if (state.error) emailRef.current?.focus();
  }, [state.error]);

  return (
    <form action={formAction} noValidate>
      <input type="hidden" name="next" value={next ?? ""} />
      <div className={styles.field}>
        <label className={styles.label} htmlFor="email">
          E-mail
        </label>
        <input
          ref={emailRef}
          className={styles.input}
          id="email"
          name="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          spellCheck={false}
          placeholder="voce@empresa.com.br"
          required
          aria-describedby={state.error ? "login-error" : undefined}
          aria-invalid={state.error ? true : undefined}
        />
      </div>
      <div className={styles.field}>
        <label className={styles.label} htmlFor="password">
          Senha
        </label>
        <input
          className={styles.input}
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
        />
      </div>
      {state.error ? (
        <p className={styles.error} id="login-error" role="alert">
          {state.error}
        </p>
      ) : null}
      <button className={styles.submit} type="submit" disabled={isPending}>
        {isPending ? (
          <>
            <span className={styles.spinner} aria-hidden="true" />
            Entrando…
          </>
        ) : (
          "Entrar"
        )}
      </button>
    </form>
  );
}
