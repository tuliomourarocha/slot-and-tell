# Agenda SaaS

Agendamento multiempresa para barbearias, salões, estúdios e clínicas, com portal web e atendimento por WhatsApp. Especificação completa em [`spec.md`](./spec.md).

Este estado do repositório corresponde à **Fase 1 · Fundação**: scaffold Next.js + TypeScript (issue #1) e schema base do banco com seed multi-tenant (issue #6). Ainda não há funcionalidade de produto.

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

Isolamento entre tenants é garantido no banco por FKs compostas `(tenant_id, id)`: uma reserva ou vínculo jamais referencia cliente, profissional ou serviço de outra empresa.

### Política de acesso (RLS)

Deny-by-default em duas camadas: RLS habilitado nas 10 tabelas e `revoke` de `PUBLIC`/`anon`/`authenticated` em tabelas e funções do schema (inclusive defaults para objetos futuros). `anon` não tem grant nem política. `service_role` (servidor) mantém acesso legítimo.

A **fronteira de isolamento** é o vínculo validado em `memberships` (`auth.uid()` → linha de membership da empresa), nunca um claim de "empresa ativa" no JWT. Um usuário com vínculos em várias empresas acessa cada uma onde tem membership; a escolha de empresa na UI é filtro de UX, não fronteira de segurança.

Helpers de sessão (`SECURITY DEFINER`, `search_path = ''`, `EXECUTE` só para `authenticated`):

- `public.has_membership(tenant_id, roles[])` — usada nas políticas; roda como dono, evitando recursão de RLS em `memberships`.
- `public.own_professional_id(tenant_id)` — profissional da agenda vinculado ao usuário logado na empresa.
- `public.assert_tenant_role(tenant_id, roles[])` — **padrão obrigatório de RPC privilegiada**: valida empresa e papel e levanta `42501` se negar.

Matriz (tenant = linha da própria empresa; `S` select, `I` insert, `U` update, `D` delete):

| Tabela | admin | receptionist | professional |
|---|---|---|---|
| `tenants` | S+U | S | S |
| `memberships` | S/I/U/D | — | S (só a própria linha) |
| `professionals` | S/I/U/D | S/I/U | S |
| `services` | S/I/U (arquivar = U) | S/I/U | S |
| `professional_services` | S/I/U/D | S/I/U/D | S |
| `weekly_availability` / `schedule_exceptions` | S/I/U/D | S/I/U/D | S + I/U/D das **próprias** linhas |
| `customers` | S/I/U/D | S/I/U/D | S |
| `appointments` | S/I/U (sem D: ciclo via `status`) | S/I/U | S (só o próprio `professional_id`) |
| `audit_events` | S | — | — (escrita só por `service_role`/RPC futura) |

A agenda do profissional é somente leitura até a RPC transacional da agenda (decisão D3 da issue #3).

**Convenção para RPCs privilegiadas (futuras):** `security invoker` por padrão, chamar `public.assert_tenant_role(...)` no início com os papéis permitidos, e conceder `EXECUTE` individualmente a `authenticated`. Nenhuma função é executável por `anon` ou `PUBLIC`.

Verificação: `supabase/tests/database/rls_isolation.test.sql` cobre acesso cruzado por ID direto (SELECT/UPDATE/INSERT e mudança de `tenant_id`) entre a barbearia e a clínica nos dois sentidos, gates por papel e sessão sem usuário. Teste de API/rota Next.js com sessão real fica para o portal/login (#2/#5).

Regras estruturais já fixadas nesta migration: `audit_events` é append-only (trigger rejeita UPDATE/DELETE e `tenant_id` tem `on delete restrict`, sem cascade silencioso do histórico); `memberships` pareia papel e profissional em ambos os sentidos com no máximo um login por profissional; o snapshot de duração em `appointments` é checado contra `ends_at - starts_at`; e `btree_gist` (extensão oficial usada pelo `EXCLUDE` de conflito) é suportada pelo Supabase, instalada no schema `extensions`.

### subir e resetar o banco local

```bash
docker start docker >/dev/null 2>&1 || true   # Docker Desktop/daemon ativo
supabase start          # primeira execução baixa imagens do Supabase
supabase db reset       # aplica migrations + seed (duas empresas de exemplo)
```

A saída de `supabase start` lista as credenciais locais (Studio, URL do Postgres, chaves `anon`/`service_role` de desenvolvimento) — nada disso é versionado.

### Seed: duas empresas de exemplo

Política do seed: é **local/DEV only** e **idempotente**. (a) Guarda no topo do arquivo aborta a execução quando a sessão usa TLS (`pg_stat_ssl.ssl = true`), critério de "projeto remoto": conexões à Supabase Cloud (direta ou pooler) sempre usam TLS. O seed automático do CLI local (`supabase db reset`/`start`) e `psql` via socket local não usam TLS e passam. Não se usa loopback/IP como critério (dentro do contêiner o servidor vê o IP da rede Docker). Limite honesto: um `psql` sem TLS apontando para um banco próprio que espelhe produção não é bloqueado — mirar o banco certo é responsabilidade de quem executa. (b) Reaplicar sobre banco já semeado não duplica nem erra: `on conflict do nothing` com UUIDs/chaves naturais determinísticas em todas as tabelas e `NOT EXISTS` onde não há chave natural (expediente, exceções). Como as datas de exceções/reservas são relativas a "hoje" e não são re-ancoradas em reaplicação, use `supabase db reset` para re-gerar o seed com a data atual.

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
supabase test db        # pgTAP: supabase/tests/database/*.test.sql
```

- `schema_seed.test.sql` (30 asserts, `plan(30)`) — DoD da issue #6: estrutura das 10 tabelas, seed com 2 empresas em BRL/`America/Sao_Paulo`, rejeição de FK cruzada entre tenants, overlap em reservas ativas, adjacência `[)`, `trigger updated_at`, unicidade de contato por empresa, snapshot de duração, trilha `audit_events` imutável (UPDATE, DELETE e TRUNCATE rejeitados), RLS habilitado nas 10 tabelas, sonda real como `anon` e `EXECUTE` negado a `PUBLIC`. Idempotência do seed não é coberta pelo pgTAP (ver verificação manual abaixo).
- `rls_isolation.test.sql` (48 asserts, `plan(48)`) — issue #3: catálogo de políticas/grants/helpers, acesso cruzado por ID entre barbearia e clínica nos dois sentidos, gates por papel e sessão sem `auth.uid()`.

Os testes são **transacionais e repetíveis**: cada arquivo abre `BEGIN` e encerra com `ROLLBACK` após `finish()`, então nenhum insert/update dos testes persiste — `supabase test db` pode rodar em sequência sem `db reset` no meio.

## Validação do webhook da Meta e Supabase

Ainda não aplicável nesta fase. Os procedimentos (número de teste da Meta, Supabase CLI, migrations, cron com `pg_net`) serão documentados nas fases de Agenda, WhatsApp e Piloto.
