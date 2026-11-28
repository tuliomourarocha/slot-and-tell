// Domínio — papel de vínculo. Sem framework: tipos e constantes puras.
export const ROLES = ["admin", "receptionist", "professional"] as const;

export type Role = (typeof ROLES)[number];

export function isRole(value: string): value is Role {
  return (ROLES as readonly string[]).includes(value);
}

/** Converte valor do banco em Role; falha ruidosa em papel desconhecido. */
export function parseRole(value: string): Role {
  if (!isRole(value)) throw new Error(`Papel desconhecido: ${value}`);
  return value;
}

/** Rótulos pt-BR usados em UI (seleção de empresa, header, estados). */
export const ROLE_LABELS: Record<Role, string> = {
  admin: "Administrador",
  receptionist: "Recepção",
  professional: "Profissional",
};
