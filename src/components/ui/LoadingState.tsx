import styles from "./states.module.css";

/** Estado de carregamento: esqueleto + aria-busy + rótulo terminando em “…” */
export function LoadingState({ label = "Carregando…" }: { label?: string }) {
  return (
    <div className={styles.skeleton} aria-busy="true" role="status">
      <span className={styles.skeletonLine} aria-hidden="true" />
      <span className={styles.skeletonLine} aria-hidden="true" />
      <span className={styles.skeletonLine} aria-hidden="true" />
      <p className={styles.loadingLabel}>{label}</p>
    </div>
  );
}
