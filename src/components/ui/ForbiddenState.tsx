import Link from "next/link";

import styles from "./states.module.css";

interface ForbiddenStateProps {
  areaLabel?: string;
}

/** Estado “sem permissão”: explica e oferece volta para a área inicial. */
export function ForbiddenState({ areaLabel }: ForbiddenStateProps) {
  return (
    <div className={`${styles.state} ${styles.forbidden}`} role="alert">
      <span className={styles.icon} aria-hidden="true">
        🔒
      </span>
      <h2>Sem permissão</h2>
      <p>
        {areaLabel
          ? `Seu papel na empresa ativa não dá acesso a “${areaLabel}”.`
          : "Seu papel na empresa ativa não dá acesso a esta área."}{" "}
        Fale com um administrador da empresa, se precisar.
      </p>
      <div className={styles.actions}>
        <Link className={styles.actionLink} href="/portal">
          Ir para o início
        </Link>
      </div>
    </div>
  );
}
