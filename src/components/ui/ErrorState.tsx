import type { ReactNode } from "react";

import styles from "./states.module.css";

interface ErrorStateProps {
  title?: string;
  description?: string;
  /** Ações acionáveis opcionais (ex.: botão “tentar de novo”). */
  children?: ReactNode;
}

/** Estado de erro inesperado, acionável e anunciado por role="alert". */
export function ErrorState({
  title = "Algo deu errado",
  description = "Não foi possível concluir a operação. Tente novamente em instantes.",
  children,
}: ErrorStateProps) {
  return (
    <div className={`${styles.state} ${styles.error}`} role="alert">
      <span className={styles.icon} aria-hidden="true">
        ⚠️
      </span>
      <h2>{title}</h2>
      <p>{description}</p>
      {children ? <div className={styles.actions}>{children}</div> : null}
    </div>
  );
}
