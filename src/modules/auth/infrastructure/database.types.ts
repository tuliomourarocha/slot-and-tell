// Infrastructure — tipos do banco usados pelo módulo auth (subconjunto mínimo).
// Gerado à mão a partir de supabase/migrations; amplie conforme novas tabelas.
import type { Role } from "../domain/role";

export interface MembershipRow {
  tenant_id: string;
  tenant_name: string;
  role: string;
  professional_id: string | null;
}

export interface Database {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: {
      list_my_memberships: {
        Args: Record<PropertyKey, never>;
        Returns: MembershipRow[];
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}

export type { Role };
