import { describe, expect, it } from "vitest";
import { MODULE_NAME as auth } from "@/modules/auth";
import { MODULE_NAME as catalog } from "@/modules/catalog";
import { MODULE_NAME as scheduling } from "@/modules/scheduling";
import { MODULE_NAME as conversations } from "@/modules/conversations";
import { MODULE_NAME as notifications } from "@/modules/notifications";
import { MODULE_NAME as integrations } from "@/modules/integrations";

describe("estrutura de módulos", () => {
  it("expõe a fronteira pública de cada capacidade via alias @/*", () => {
    expect([auth, catalog, scheduling, conversations, notifications, integrations]).toEqual([
      "auth",
      "catalog",
      "scheduling",
      "conversations",
      "notifications",
      "integrations",
    ]);
  });
});
