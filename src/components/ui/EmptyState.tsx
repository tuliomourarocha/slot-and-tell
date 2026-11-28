import type { ReactNode } from "react";

import styles from "./states.module.css";

interface EmptyStateProps {
  title: string;
  description?: string;
  /** Orientação do próximo passo (ex.: lista de passos ou link). */
  children?: ReactNode;
}

/** Estado vazio: sempre conteúdo útil que orienta o próximo passo. */
export function EmptyState({ title, description, children }: EmptyStateProps) {
  return (
    <div className={`${styles.state} ${styles.empty}`}>
      <span className={styles.icon} aria-hidden="true">
        🗂️
      </span>
      <h2>{title}</h2>
      {description ? <p>{description}</p> : null}
      {children}
    </div>
  );
}
