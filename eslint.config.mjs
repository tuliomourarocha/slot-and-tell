import nextVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

// Fronteiras de módulos (ver README, seção Arquitetura).
// Mantenha esta lista sincronizada com as pastas em src/modules/.
const MODULES = [
  "auth",
  "catalog",
  "scheduling",
  "conversations",
  "notifications",
  "integrations",
];

const BOUNDARY_MESSAGE =
  "Internals de outro módulo são privados. Importe somente do contrato público (@/modules/<módulo>, index.ts).";

// Padrões que alcançam o interior de um módulo `owner`, por alias, caminho base ou relativo.
// Importar `@/modules/<owner>` (index.ts) continua permitido.
const internalPatternsOf = (owner) => [
  `@/modules/${owner}/**`,
  `src/modules/${owner}/**`,
  ...[1, 2, 3, 4].flatMap((depth) => [
    `${"../".repeat(depth)}${owner}/**`,
    `${"../".repeat(depth)}modules/${owner}/**`,
  ]),
];

// Cada módulo só pode alcançar o interior dos demais por contrato público.
const moduleBoundaryBlocks = MODULES.map((module) => ({
  files: [`src/modules/${module}/**/*.{ts,tsx,mts,cts}`],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        patterns: [
          {
            group: MODULES.filter((other) => other !== module).flatMap(internalPatternsOf),
            message: BOUNDARY_MESSAGE,
          },
        ],
      },
    ],
  },
}));

// Código fora de src/modules (app, components, tests) também consome apenas o contrato público.
const consumerBoundaryBlock = {
  files: ["src/app/**/*.{ts,tsx,mts,cts}", "src/components/**/*.{ts,tsx,mts,cts}", "tests/**/*.{ts,tsx,mts,cts}"],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        patterns: [
          {
            group: MODULES.flatMap(internalPatternsOf),
            message: BOUNDARY_MESSAGE,
          },
        ],
      },
    ],
  },
};

const config = [
  {
    ignores: [
      ".next/**",
      "node_modules/**",
      "coverage/**",
      "next-env.d.ts",
      ".opencode/**",
      "hooks/**",
      "supabase/.temp/**",
    ],
  },
  ...nextVitals,
  ...nextTypescript,
  ...moduleBoundaryBlocks,
  consumerBoundaryBlock,
];

export default config;
