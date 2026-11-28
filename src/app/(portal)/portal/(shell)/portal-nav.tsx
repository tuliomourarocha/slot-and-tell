"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import styles from "./shell.module.css";

export interface NavArea {
  href: string;
  label: string;
}

/** Navegação do shell: marca a área atual com aria-current (usa pathname). */
export function PortalNav({ areas }: { areas: readonly NavArea[] }) {
  const pathname = usePathname();

  return (
    <nav aria-label="Áreas do portal">
      <ul className={styles.navList}>
        {areas.map((area) => (
          <li key={area.href}>
            <Link
              href={area.href}
              className={styles.navLink}
              aria-current={pathname === area.href ? "page" : undefined}
            >
              {area.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
