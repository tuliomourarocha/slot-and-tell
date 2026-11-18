import { fileURLToPath } from "node:url";
import { Linter } from "eslint";
import { describe, expect, it } from "vitest";
// eslint.config.mjs é JS sem declaração de tipos; é exatamente a config usada pelo `npm run lint`.
// @ts-expect-error -- módulo JS sem tipos (TS7016)
import config from "../eslint.config.mjs";

// Teste permanente das fronteiras de módulos definidas em eslint.config.mjs.
// Usa o Linter do ESLint sobre código em memória: nenhum arquivo temporário é criado.
const cwd = fileURLToPath(new URL("..", import.meta.url));
const linter = new Linter({ configType: "flat", cwd });

const boundaryErrors = (filename: string, code: string): string[] =>
  linter
    .verify(code, config, { filename })
    .filter((message) => message.ruleId === "no-restricted-imports")
    .map((message) => message.message);

const BLOCKED = [expect.stringContaining("Internals de outro módulo")];

describe("fronteiras de módulos (ESLint no-restricted-imports)", () => {
  describe("entre módulos", () => {
    const filename = "src/modules/catalog/application/use-case.ts";

    it("bloqueia alias para internals de outro módulo", () => {
      expect(boundaryErrors(filename, `import { x } from "@/modules/scheduling/domain/slot";\nexport { x };`)).toEqual(BLOCKED);
    });

    it("bloqueia caminho relativo para internals de outro módulo", () => {
      expect(boundaryErrors(filename, `import { x } from "../../scheduling/domain/slot";\nexport { x };`)).toEqual(BLOCKED);
    });

    it("bloqueia caminho base src/modules para internals de outro módulo", () => {
      expect(boundaryErrors(filename, `import { x } from "src/modules/auth/infrastructure/repo";\nexport { x };`)).toEqual(BLOCKED);
    });

    it("permite import pelo index público de outro módulo", () => {
      expect(boundaryErrors(filename, `import { MODULE_NAME } from "@/modules/scheduling";\nexport { MODULE_NAME };`)).toHaveLength(0);
    });

    it("permite import de internals do próprio módulo", () => {
      expect(boundaryErrors(filename, `import { x } from "@/modules/catalog/domain/service";\nexport { x };`)).toHaveLength(0);
    });
  });

  describe("consumidores fora de src/modules", () => {
    it("bloqueia internals de módulo em src/app", () => {
      expect(
        boundaryErrors("src/app/page.tsx", `import { x } from "@/modules/auth/infrastructure/repo";\nexport { x };`),
      ).toEqual(BLOCKED);
    });

    it("bloqueia internals de módulo em tests", () => {
      expect(
        boundaryErrors("tests/example.test.ts", `import { x } from "@/modules/auth/infrastructure/repo";\nexport { x };`),
      ).toEqual(BLOCKED);
    });

    it("permite import pelo index público em src/app", () => {
      expect(boundaryErrors("src/app/page.tsx", `import { MODULE_NAME } from "@/modules/auth";\nexport { MODULE_NAME };`)).toHaveLength(0);
    });
  });
});
