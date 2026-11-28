// Domínio — vínculo usuário ↔ empresa. Entidade pura, sem ORM.
import type { Role } from "./role";

export interface Membership {
  tenantId: string;
  tenantName: string;
  role: Role;
  /** Preenchido somente quando role === "professional". */
  professionalId: string | null;
}
