# Agenda SaaS

Agendamento multiempresa para barbearias, salões, estúdios e clínicas, com portal web e atendimento por WhatsApp. Especificação completa em [`spec.md`](./spec.md).

Este estado do repositório corresponde à **Fase 1 · Fundação (issue #1)**: projeto Next.js + TypeScript com estrutura de módulos. Ainda não há funcionalidade de produto.

## Requisitos

- Node.js 20.9+ (recomendado: LTS atual)
- npm

## Instalação local

```bash
npm install
cp .env.example .env.local   # preencha apenas quando as integrações forem ativadas
npm run dev                  # http://localhost:3000
```

## Scripts

| Comando | Função |
|---|---|
| `npm run dev` | Servidor de desenvolvimento do Next.js |
| `npm run build` | Build de produção |
| `npm run start` | Servidor após o build |
| `npm run lint` | ESLint (`next/core-web-vitals` + `next/typescript`) + fronteiras entre módulos |
| `npm run typecheck` | `tsc --noEmit` com TypeScript strict |
| `npm test` | Testes unitários com Vitest (`vitest run`) |

## Estrutura

```text
src/
├── app/                  # Páginas e Route Handlers (App Router)
├── components/           # Interface compartilhada
└── modules/
    ├── auth/             # Sessão e escopo da empresa
    ├── catalog/          # Serviços, preços e profissionais
    ├── scheduling/       # Disponibilidade e operações da agenda
    ├── conversations/    # Estado, ferramentas e transferência humana
    ├── notifications/    # Fila de saída, lembretes e status
    └── integrations/     # Adaptadores WhatsApp, IA e Supabase
tests/                    # Testes de estrutura e, futuramente, fluxos críticos
```

Alias: `@/*` aponta para `src/*` (configurado em `tsconfig.json` e `vitest.config.mts`).

### Arquitetura

- Fronteiras por capacidade: cada módulo expõe apenas o contrato público pelo seu `index.ts`.
- Um módulo não importa internals de outro. A comunicação entre capacidades passa por contratos explícitos (interfaces/DTOs) ou pelo banco, nunca por imports diretos de arquivos internos.
- Dependency Rule: regras de domínio não dependem de framework, banco ou HTTP.

#### Enforcement das fronteiras

A regra é imposta pelo ESLint (`npm run lint`) em `eslint.config.mjs`, com `no-restricted-imports`:

- Em `src/modules/<módulo>/**`, imports de `@/modules/<outro>/**`, `src/modules/<outro>/**` ou caminhos relativos que alcancem `<outro>/` são erro. `@/modules/<outro>` (index.ts) continua permitido.
- Em `src/app`, `src/components` e `tests/`, qualquer interior de módulo é erro; o consumo é sempre pelo contrato público.
- Dentro do próprio módulo, imports internos (relativos ou `@/modules/<próprio>/...`) são permitidos.
- Ao criar um módulo novo, adicione-o à lista `MODULES` em `eslint.config.mjs`.

### Decisões do scaffold

- **Nome do pacote:** `slot-and-tell` (campo `name` do `package.json`). A especificação cita o repositório como `agenda-saas`, mas o repositório Git e a pasta são `slot-and-tell`. Mantemos o nome real do repositório para evitar divergência entre pacote e remote; o nome de produto "Agenda SaaS" continua no título, `metadata` e textos da interface.
- **Lockfile:** `package-lock.json` é versionado (não está no `.gitignore`) e fica sincronizado com o `package.json`. Use `npm ci` em ambientes reproduzíveis.
- **Typecheck:** `tsconfig.json` inclui `**/*.ts`, `**/*.tsx` e `**/*.mts`, para que `vitest.config.mts` também seja verificado por `npm run typecheck`.

## Variáveis de ambiente

Veja `.env.example`. Nenhum valor real é versionado. Somente `NEXT_PUBLIC_*` vai ao navegador; chaves privilegiadas e segredos ficam restritos ao servidor. Arquivos `.env*` (exceto `.env.example`) são ignorados pelo Git.

## Banco de dados (Supabase)

Migrations versionadas em `supabase/migrations/` e seed de desenvolvimento em `supabase/seed.sql` (issue #6). Schema base multi-tenant com 10 tabelas:

| Tabela | Papel |
|---|---|
| `tenants` | Empresa: fuso IANA, moeda, passo de oferta, política de cancelamento |
| `memberships` | Vínculo usuário Auth ↔ empresa (`admin`, `receptionist`, `professional`), profissional opcional |
| `professionals` / `services` / `professional_services` | Equipe, catálogo (duração em minutos, preço em centavos, arquivamento sem apagar) e habilitações |
| `weekly_availability` / `schedule_exceptions` | Expediente e pausas em hora local; folgas, bloqueios e turnos extras por data |
| `customers` | Nome opcional, contato E.164 único por empresa |
| `appointments` | Reservas em `timestamptz` com `tstzrange '[)'`, snapshots de serviço e exclusão GiST contra overlap de reservas ativas (`pending`/`confirmed`) |
| `audit_events` | Trilha append-only de mutações |

Isolamento entre tenants é garantido no banco por FKs compostas `(tenant_id, id)`: uma reserva ou vínculo jamais referencia cliente, profissional ou serviço de outra empresa. RLS será adicionado na issue #3 — até lá, o schema atende apenas desenvolvimento local.

### subir e resetar o banco local

```bash
docker start docker >/dev/null 2>&1 || true   # Docker Desktop/daemon ativo
supabase start          # primeira execução baixa imagens do Supabase
supabase db reset       # aplica migrations + seed (duas empresas de exemplo)
```

A saída de `supabase start` lista as credenciais locais (Studio, URL do Postgres, chaves `anon`/`service_role` de desenvolvimento) — nada disso é versionado.

### Seed: duas empresas de exemplo

- **Barbearia Vila Nova** — passo 15 min, cancelamento 120 min; 3 profissionais (Marina não tem login), 4 serviços (1 arquivado), expediente seg–sáb com pausa, exceções de folga/bloqueio/extra, 3 clientes e 5 reservas (inclui par adjacente 10:00–10:40 e 10:40–11:10).
- **Clínica Bem Estar** — passo 30 min, cancelamento 1440 min; 2 profissionais, 3 serviços, expediente seg–sex, 2 clientes e 2 reservas.

Usuários de desenvolvimento (senha fixa `slot-and-tell-dev`, **somente stack local**):

| E-mail | Papel |
|---|---|
| `dev.admin@barbearia.example` | admin da barbearia |
| `dev.recepcao@barbearia.example` | recepção da barbearia |
| `dev.profissional@barbearia.example` | profissional (Rafa) |
| `dev.admin@clinica.example` | admin da clínica |

### verificação local reproduzível

```bash
supabase test db        # pgTAP: supabase/tests/database/schema_seed.test.sql
```

Os testes cobrem o DoD da issue #6: aplicação das migrations, seed com 2 empresas em BRL/`America/Sao_Paulo`, rejeição de FK cruzada entre tenants, rejeição de overlap em reservas ativas, aceitação de intervalos adjacentes `[)`, `trigger updated_at` e unicidade de contato por empresa.

## Validação do webhook da Meta e Supabase

Ainda não aplicável nesta fase. Os procedimentos (número de teste da Meta, Supabase CLI, migrations, cron com `pg_net`) serão documentados nas fases de Agenda, WhatsApp e Piloto.
