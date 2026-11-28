// Domínio — matriz papel → áreas do portal (decisão D3 do PLAN).
// Fonte única de verdade para menu do shell e guarda das páginas.
import type { Role } from "./role";

export interface PortalArea {
  id: string;
  href: string;
  label: string;
  description: string;
  roles: readonly Role[];
}

export const PORTAL_AREAS: readonly PortalArea[] = [
  {
    id: "agenda",
    href: "/portal/agenda",
    label: "Agenda",
    description: "Reservas e horários da empresa ativa.",
    roles: ["admin", "receptionist", "professional"],
  },
  {
    id: "servicos",
    href: "/portal/servicos",
    label: "Serviços",
    description: "Catálogo de serviços e durações.",
    roles: ["admin", "receptionist"],
  },
  {
    id: "equipe",
    href: "/portal/equipe",
    label: "Equipe",
    description: "Profissionais da empresa.",
    roles: ["admin", "receptionist"],
  },
  {
    id: "expediente",
    href: "/portal/expediente",
    label: "Expediente",
    description: "Jornadas e ausências (profissional edita as próprias).",
    roles: ["admin", "receptionist", "professional"],
  },
  {
    id: "atendimento",
    href: "/portal/atendimento",
    label: "Atendimento",
    description: "Clientes e histórico de atendimento.",
    roles: ["admin", "receptionist"],
  },
  {
    id: "configuracoes",
    href: "/portal/configuracoes",
    label: "Configurações",
    description: "Parâmetros da empresa e gestão da equipe.",
    roles: ["admin"],
  },
];

/** Áreas visíveis para o papel, na ordem do menu. */
export function areasForRole(role: Role): PortalArea[] {
  return PORTAL_AREAS.filter((area) => area.roles.includes(role));
}

/** O papel pode acessar a área (por id ou href)? */
export function canAccessArea(role: Role, areaId: string): boolean {
  const area = PORTAL_AREAS.find((entry) => entry.id === areaId || entry.href === areaId);
  return area ? area.roles.includes(role) : false;
}

/** Primeira área do papel — destino do “início do portal”. */
export function firstAreaForRole(role: Role): PortalArea | undefined {
  return areasForRole(role)[0];
}
