// Testes do portal (issue #2): matriz papel → área, decisão de acesso e
// revalidação da empresa ativa. Consomem SOMENTE o contrato público do módulo
// auth (fronteira ESLint) e não precisam de Supabase: a decisão é pura.
import { describe, expect, it } from "vitest";

import {
  ACTIVE_TENANT_COOKIE,
  areasForRole,
  canAccessArea,
  decidePortalAccess,
  PORTAL_AREAS,
  resolveActiveTenant,
  type Membership,
} from "@/modules/auth";

const membership = (tenantId: string, tenantName: string, role: Membership["role"]): Membership => ({
  tenantId,
  tenantName,
  role,
  professionalId: role === "professional" ? "bbbbbbbb-0000-4000-8000-000000000001" : null,
});

const barbearia = membership("11111111-1111-4111-8111-111111111111", "Barbearia Vila Nova", "professional");
const clinica = membership("22222222-2222-4222-8222-222222222222", "Clínica Bem Estar", "admin");

describe("matriz papel → áreas (PLAN D3)", () => {
  it("admin vê todas as áreas", () => {
    expect(areasForRole("admin").map((area) => area.id)).toEqual([
      "agenda",
      "servicos",
      "equipe",
      "expediente",
      "atendimento",
      "configuracoes",
    ]);
  });

  it("recepção vê Agenda, Serviços, Equipe, Expediente e Atendimento — sem Configurações", () => {
    expect(areasForRole("receptionist").map((area) => area.id)).toEqual([
      "agenda",
      "servicos",
      "equipe",
      "expediente",
      "atendimento",
    ]);
  });

  it("profissional vê só Agenda e Expediente", () => {
    expect(areasForRole("professional").map((area) => area.id)).toEqual(["agenda", "expediente"]);
  });

  it("profissional é bloqueado em /portal/configuracoes", () => {
    expect(canAccessArea("professional", "/portal/configuracoes")).toBe(false);
    expect(canAccessArea("professional", "configuracoes")).toBe(false);
  });

  it("toda área da matriz tem href e rótulo", () => {
    for (const area of PORTAL_AREAS) {
      expect(area.href).toMatch(/^\/portal\//);
      expect(area.label.length).toBeGreaterThan(0);
    }
  });
});

describe("empresa ativa (cookie revalidado)", () => {
  it("cookie válido resolve para o vínculo correspondente", () => {
    expect(resolveActiveTenant([barbearia, clinica], clinica.tenantId)).toEqual(clinica);
  });

  it("cookie forjado (empresa sem vínculo) é rejeitado — devolve à seleção", () => {
    expect(resolveActiveTenant([barbearia, clinica], "99999999-9999-4999-8999-999999999999")).toBeNull();
  });

  it("sem cookie e vínculo único → acesso direto (login em 1 clique)", () => {
    expect(resolveActiveTenant([clinica], null)).toEqual(clinica);
  });

  it("sem cookie e vários vínculos → nulo (usuário escolhe)", () => {
    expect(resolveActiveTenant([barbearia, clinica], null)).toBeNull();
  });

  it("sem vínculos, não há empresa ativa", () => {
    expect(resolveActiveTenant([], clinica.tenantId)).toBeNull();
  });

  it("nome do cookie estável para contrato entre páginas e actions", () => {
    expect(ACTIVE_TENANT_COOKIE).toBe("active-tenant");
  });
});

describe("decisão de acesso ao portal (guarda servidor)", () => {
  const input = {
    session: { userId: "u" },
    memberships: [barbearia, clinica],
    cookieTenantId: clinica.tenantId,
    areaId: "configuracoes",
    requiredRoles: ["admin"] as const,
  };

  it("sem sessão → login", () => {
    expect(decidePortalAccess({ ...input, session: null }).status).toBe("login");
  });

  it("sessão sem vínculo → estado de sem vínculo", () => {
    const decision = decidePortalAccess({ ...input, memberships: [] });
    expect(decision.status).toBe("no-membership");
  });

  it("sessão com vários vínculos e sem empresa ativa → seleção de empresa", () => {
    const decision = decidePortalAccess({ ...input, cookieTenantId: null });
    expect(decision.status).toBe("select-tenant");
  });

  it("papel sem permissão para a área → sem permissão (nunca conteúdo)", () => {
    const decision = decidePortalAccess({ ...input, cookieTenantId: barbearia.tenantId });
    expect(decision.status).toBe("forbidden");
  });

  it("papel com permissão → ok com vínculo e papel", () => {
    const decision = decidePortalAccess({ ...input, areaId: "agenda" });
    expect(decision).toEqual({ status: "ok", membership: clinica, role: "admin" });
  });
});
