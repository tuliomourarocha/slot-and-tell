-- Issue #6 · S1 — Schema base multi-tenant do Agenda SaaS (slot-and-tell)
-- Escopo: 10 tabelas núcleo, FKs compostas com tenant_id (isolamento no banco),
-- UUIDs, timestamps de auditoria, trigger updated_at, exclusão GiST para
-- conflitos de reservas ativas via tstzrange '[)', snapshots de serviço e
-- acesso deny-by-default (RLS ligado sem políticas + revoke de anon/authenticated).
-- Fora deste escopo (issues próprias): políticas de RLS (#3), login (#5), portal (#2),
-- CI (#13), RPCs/mutations transacionais e tabelas WhatsApp.

-- ---------------------------------------------------------------------------
-- Extensões
-- ---------------------------------------------------------------------------
-- btree_gist: contrib oficial do PostgreSQL, suportada pelo Supabase (Cloud e
-- stack local), que permite EXCLUDE USING gist combinando igualdade de UUID com
-- sobreposição de intervalo (regra de conflito de agenda). Instalada no schema
-- `extensions` (padrão Supabase); em PostgreSQL puro exige superuser e que o
-- schema exista. Não há dependência de extensões experimentais.
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------------
-- Função utilitária: updated_at
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- tenants — empresa (unidade), fuso, moeda e políticas de agendamento
-- ---------------------------------------------------------------------------
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  timezone text not null default 'America/Sao_Paulo'
    check (timezone ~ '^[A-Za-z0-9_/+-]+$'),
  currency bpchar(3) not null default 'BRL'
    check (currency ~ '^[A-Z]{3}$'),
  -- intervalo entre horários oferecidos (passo de oferta), em minutos
  slot_step_minutes int not null default 30
    check (slot_step_minutes > 0 and slot_step_minutes <= 24 * 60),
  -- antecedência mínima para agendar (minutos)
  min_advance_minutes int not null default 0
    check (min_advance_minutes >= 0),
  -- horizonte máximo de busca de horários (dias)
  max_horizon_days int not null default 30
    check (max_horizon_days > 0),
  -- janela de cancelamento autônomo (minutos de antecedência)
  cancellation_cutoff_minutes int not null default 120
    check (cancellation_cutoff_minutes >= 0),
  -- ciclo de vida do tenant: 'archived' é o caminho de saída — a operação
  -- padrão é arquivar, nunca excluir (histórico em audit_events é restrict).
  -- Exclusão física de tenant é procedimento manual offline fora do MVP.
  status text not null default 'active'
    check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, name)
);

-- ---------------------------------------------------------------------------
-- professionals — equipe da empresa (pode existir antes de ter login)
-- ---------------------------------------------------------------------------
create table public.professionals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- alvo para FKs compostas: garante vínculo dentro do mesmo tenant
  unique (tenant_id, id)
);

create index professionals_tenant_active_idx
  on public.professionals (tenant_id)
  where active;

-- ---------------------------------------------------------------------------
-- services — catálogo: duração em minutos, preço em centavos (BRL)
-- ---------------------------------------------------------------------------
create table public.services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  description text,
  duration_minutes int not null check (duration_minutes > 0),
  price_cents bigint not null check (price_cents >= 0),
  -- arquivamento preserva histórico (sem exclusão física)
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create index services_tenant_active_idx
  on public.services (tenant_id)
  where archived_at is null;

-- ---------------------------------------------------------------------------
-- memberships — vínculo usuário do Auth ↔ empresa, papel e profissional opcional
-- ---------------------------------------------------------------------------
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null
    check (role in ('admin', 'receptionist', 'professional')),
  -- profissional vinculado. Papel 'professional' exige vínculo e nenhum outro
  -- papel pode apontar para um profissional da agenda
  professional_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- isolamento entre tenants: usuário só se vincula a profissional da própria empresa
  foreign key (tenant_id, professional_id)
    references public.professionals (tenant_id, id) on delete restrict,
  unique (tenant_id, user_id),
  constraint memberships_role_professional_pairing
    check ((role = 'professional') = (professional_id is not null))
);

create index memberships_user_idx on public.memberships (user_id);

-- cardinalidade: um profissional da agenda é representado por no máximo um login
create unique index memberships_professional_unique_idx
  on public.memberships (tenant_id, professional_id)
  where professional_id is not null;

-- ---------------------------------------------------------------------------
-- professional_services — profissionais habilitados por serviço
-- ---------------------------------------------------------------------------
create table public.professional_services (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  professional_id uuid not null,
  service_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (tenant_id, professional_id)
    references public.professionals (tenant_id, id) on delete cascade,
  foreign key (tenant_id, service_id)
    references public.services (tenant_id, id) on delete cascade,
  unique (tenant_id, professional_id, service_id)
);

create index professional_services_service_idx
  on public.professional_services (tenant_id, service_id);

-- ---------------------------------------------------------------------------
-- weekly_availability — turnos recorrentes e pausas em hora local da empresa
-- ---------------------------------------------------------------------------
create table public.weekly_availability (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  professional_id uuid not null,
  -- dia da semana ISO: 1 = segunda ... 7 = domingo
  weekday smallint not null check (weekday between 1 and 7),
  kind text not null check (kind in ('work', 'break')),
  local_start time not null,
  local_end time not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, professional_id)
    references public.professionals (tenant_id, id) on delete cascade,
  check (local_end > local_start)
);

create index weekly_availability_pro_day_idx
  on public.weekly_availability (tenant_id, professional_id, weekday);

-- ---------------------------------------------------------------------------
-- schedule_exceptions — folgas, bloqueios e turnos extras em datas pontuais
-- ---------------------------------------------------------------------------
create table public.schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  professional_id uuid not null,
  kind text not null check (kind in ('day_off', 'blocked', 'extra')),
  exception_date date not null,
  -- day_off cobre o dia inteiro (sem horários); blocked/extra exigem janela local
  local_start time,
  local_end time,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, professional_id)
    references public.professionals (tenant_id, id) on delete cascade,
  check (
    case kind
      when 'day_off' then local_start is null and local_end is null
      else local_start is not null and local_end is not null and local_end > local_start
    end
  )
);

create index schedule_exceptions_pro_date_idx
  on public.schedule_exceptions (tenant_id, professional_id, exception_date);

-- ---------------------------------------------------------------------------
-- customers — identidade única por empresa e contato; nome opcional
-- ---------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text check (name is null or length(trim(name)) > 0),
  -- telefone normalizado em E.164 (canal do MVP é WhatsApp)
  phone_e164 text not null check (phone_e164 ~ '^\+[1-9]\d{7,14}$'),
  email text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, phone_e164)
);

-- ---------------------------------------------------------------------------
-- appointments — reservas com snapshots de serviço e exclusão por conflito
-- ---------------------------------------------------------------------------
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  customer_id uuid not null,
  professional_id uuid not null,
  service_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- limite inferior incluído, superior excluído: intervalos adjacentes não colidem
  time_range tstzrange
    generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  status text not null
    check (status in ('pending', 'confirmed', 'cancelled', 'completed', 'no_show')),
  source text not null default 'portal'
    check (source in ('portal', 'whatsapp')),
  -- snapshots acordados no momento da reserva (histórico sobrevive a mudanças do catálogo)
  service_name text not null,
  service_duration_minutes int not null check (service_duration_minutes > 0),
  price_cents bigint not null check (price_cents >= 0),
  currency bpchar(3) not null check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  -- o snapshot de duração deve bater com o intervalo gravado na reserva
  constraint appointments_duration_matches_range
    check ((ends_at - starts_at) = make_interval(mins => service_duration_minutes)),
  -- isolamento entre tenants em todas as referências da reserva
  foreign key (tenant_id, customer_id)
    references public.customers (tenant_id, id) on delete restrict,
  foreign key (tenant_id, professional_id)
    references public.professionals (tenant_id, id) on delete restrict,
  foreign key (tenant_id, service_id)
    references public.services (tenant_id, id) on delete restrict,
  -- um profissional não pode ter duas reservas ativas sobrepostas na mesma empresa.
  -- 'pending' e 'confirmed' contam como ativas; canceladas/concluídas não bloqueiam.
  constraint appointments_no_active_overlap
    exclude using gist (
      tenant_id with =,
      professional_id with =,
      time_range with &&
    ) where (status in ('pending', 'confirmed'))
);

create index appointments_tenant_starts_idx
  on public.appointments (tenant_id, starts_at);

create index appointments_customer_idx
  on public.appointments (tenant_id, customer_id, starts_at desc);

-- ---------------------------------------------------------------------------
-- audit_events — trilha append-only (autor, empresa, entidade, operação, mudanças)
-- ---------------------------------------------------------------------------
-- Gate de imutabilidade: UPDATE/DELETE rejeitados por trigger de linha e
-- TRUNCATE rejeitado por trigger de statement. A trilha só cresce; correções
-- entram como novo evento. (Dono/migração pode remover os triggers — mudança de
-- schema é ato deliberado e auditável, não caminho de app.)
--
-- Política de PII em `changes` (revisão #6, decisão documentada):
-- (1) conteúdo mínimo — registrar apenas o delta necessário para reconstruir a
-- mutação (ex.: {"archived_at": ...}), nunca payloads livres de conversa,
-- documentos ou cópias inteiras de linha;
-- (2) referenciar por id — contatos de cliente (telefone/e-mail) entram como
-- customer_id, nunca inline;
-- (3) retenção e acesso — leitura da trilha é papel de admin e será definida
-- pelas políticas de RLS da issue #3; expurgo por LGPD é operação offline de
-- dono (remove o gate primeiro), fora do MVP. A RPC de escrita da issue da
-- agenda deve impor (1)/(2) na fonte.
create or replace function public.audit_events_reject_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_events é append-only: % não é permitido', TG_OP
    using errcode = '42501';
end;
$$;

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  -- restrict: excluir um tenant com histórico registrado exige arquivamento
  -- deliberado da empresa, nunca cascade silencioso que apagaria a trilha
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  -- autor da ação: usuário do Auth (equipe), agente do sistema, ou nulo quando automático.
  -- restrict (e não set null): UPDATE set null em audit_events é rejeitado pelo
  -- gate append-only, então a FK antiga (on delete set null) faria a exclusão do
  -- usuário falhar de qualquer jeito — com erro confuso de trigger no lugar de
  -- erro claro de FK. Excluir usuário com trilha exige procedimento manual
  -- deliberado (a trilha é o motivo de existir); `actor_kind = 'system'` cobre
  -- ações sem autor humano.
  actor_user_id uuid references auth.users (id) on delete restrict,
  actor_kind text not null default 'system'
    check (actor_kind in ('team', 'agent', 'system')),
  entity_type text not null
    check (length(trim(entity_type)) > 0),
  entity_id uuid,
  action text not null
    check (action in ('create', 'update', 'delete', 'reschedule', 'cancel', 'archive', 'restore')),
  changes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_events_tenant_time_idx
  on public.audit_events (tenant_id, created_at desc);

create index audit_events_entity_idx
  on public.audit_events (tenant_id, entity_type, entity_id);

create trigger audit_events_append_only
  before update or delete on public.audit_events
  for each row execute function public.audit_events_reject_mutation();

-- TRUNCATE não dispara triggers de linha: gate separado a nível de statement.
-- Sem isto, `truncate audit_events` limparia a trilha sem passar pelo gate.
create trigger audit_events_reject_truncate
  before truncate on public.audit_events
  for each statement execute function public.audit_events_reject_mutation();

-- ---------------------------------------------------------------------------
-- Triggers updated_at
-- ---------------------------------------------------------------------------
create trigger tenants_set_updated_at
  before update on public.tenants
  for each row execute function public.set_updated_at();

create trigger professionals_set_updated_at
  before update on public.professionals
  for each row execute function public.set_updated_at();

create trigger services_set_updated_at
  before update on public.services
  for each row execute function public.set_updated_at();

create trigger memberships_set_updated_at
  before update on public.memberships
  for each row execute function public.set_updated_at();

create trigger weekly_availability_set_updated_at
  before update on public.weekly_availability
  for each row execute function public.set_updated_at();

create trigger schedule_exceptions_set_updated_at
  before update on public.schedule_exceptions
  for each row execute function public.set_updated_at();

create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

create trigger appointments_set_updated_at
  before update on public.appointments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Acesso negado por padrão (até a issue #3 definir políticas por papel)
-- ---------------------------------------------------------------------------
-- RLS habilitado em todas as 10 tabelas SEM nenhuma política: qualquer papel
-- sem BYPASSRLS (anon, authenticated) não lê nem escreve nada — inclusive se
-- chaves vazarem para um projeto remoto antes de #3. O revoke abaixo é a
-- segunda camada (defesa em profundidade: sem GRANT nem precisaria de política).
-- service_role/dono continuam com acesso para o servidor e migrações.
alter table public.tenants              enable row level security;
alter table public.professionals        enable row level security;
alter table public.services             enable row level security;
alter table public.memberships          enable row level security;
alter table public.professional_services enable row level security;
alter table public.weekly_availability  enable row level security;
alter table public.schedule_exceptions  enable row level security;
alter table public.customers            enable row level security;
alter table public.appointments         enable row level security;
alter table public.audit_events         enable row level security;

-- sem permissões de objeto para os papéis expostos pela API pública.
-- PUBLIC é o pseudo-role: EXECUTE em funções é concedido a PUBLIC por padrão, e
-- anon/authenticated herdam dele. Revogar só de anon/authenticated NÃO basta.
revoke all on all tables in schema public from public, anon, authenticated;

-- funções do schema public (set_updated_at, gates de auditoria) também nascem
-- sem EXECUTE para PUBLIC e para os papéis da API pública — RPCs futuras da
-- agenda serão concedidas explicitamente junto das políticas na issue #3
revoke all on all functions in schema public from public, anon, authenticated;

-- futuras tabelas do schema public (portal, agenda, WhatsApp) nascem negadas
-- para PUBLIC, anon e authenticated até #3 e afins concederem GRANTs explícitos
-- junto das políticas. Para funções, o PostgreSQL concede EXECUTE globalmente
-- a PUBLIC por padrão; revogar por schema não remove esse default, então a
-- revogação precisa ser global para o papel que executa as migrations.
alter default privileges in schema public revoke all on tables from public, anon, authenticated;
alter default privileges revoke all on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Comentários (documentação embutida no schema)
-- ---------------------------------------------------------------------------
comment on table public.tenants is
  'Empresa/unidade atendida. MVP: uma unidade por tenant. Fuso IANA, moeda e políticas de agendamento. Ciclo de vida: status active → archived (path oficial de saída; exclusão física não é fluxo de produto — FKs de histórico são restrict).';
comment on table public.memberships is
  'Vínculo entre usuário do Supabase Auth, empresa, papel e profissional opcional. FK composta impede vínculo entre tenants.';
comment on table public.professional_services is
  'Habilitações serviço ↔ profissional, isoladas por tenant via FK composta.';
comment on constraint appointments_no_active_overlap on public.appointments is
  'Regra de conflito: nenhum par de reservas pending/confirmed do mesmo profissional pode sobrepor. Adjacência [) é permitida.';
comment on constraint appointments_duration_matches_range on public.appointments is
  'Consistência do snapshot: duração gravada na reserva é exatamente ends_at - starts_at.';
-- Decisão (revisão #6): NÃO há FK de appointments para professional_services.
-- Motivos: (1) habilitações são mutáveis ao longo do tempo e a reserva guarda
-- snapshot do catálogo — uma FK impediria remover habilitação de um serviço já
-- reservado; (2) o snapshot de nome/duração/preço já torna a reserva independente
-- do catálogo; (3) a validação "profissional pode fazer este serviço" é regra de
-- negócio do agendamento e será imposta na RPC transacional da issue da agenda.
-- O vínculo estrutural existente (tenant_id, service_id) → services e
-- (tenant_id, professional_id) → professionals garante isolamento entre empresas.
comment on table public.appointments is
  'Reservas com snapshots de catálogo. Conflito de agenda por EXCLUDE GiST em (tenant, profissional, tstzrange "[)")) nas reservas ativas. RPCs transacionais virão na issue da agenda.';
comment on column services.price_cents is
  'Preço em unidades monetárias mínimas (centavos de BRL no seed).';
comment on table public.audit_events is
  'Trilha append-only de mutações: UPDATE/DELETE rejeitados por trigger de linha e TRUNCATE por trigger de statement; tenant e autor com histórico têm FK restrict (nada de cascade/anulação silenciosa). `changes` segue política de PII mínima (delta só, contatos por id). Escrita junto da mutação na mesma transação (RPCs futuras).';
