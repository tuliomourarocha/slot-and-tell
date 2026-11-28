import type { ReactNode } from "react";

import styles from "./states.module.css";

interface ConflictStateProps {
  title?: string;
  description: string;
  /** Ação sugerida para resolver o conflito (409). */
  children?: ReactNode;
}

/** Estado de conflito (409): explica o que colidiu e como resolver. */
export function ConflictState({
  title = "Conflito de dados",
  description,
  children,
}: ConflictStateProps) {
  return (
    <div className={`${styles.state} ${styles.conflict}`} role="alert">
      <span className={styles.icon} aria-hidden="true">
        🔁
      </span>
      <h2>{title}</h2>
      <p>{description}</p>
      {children ? <div className={styles.actions}>{children}</div> : null}
    </div>
  );
}
