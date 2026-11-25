-- Issue #6 · S2 — Seed de desenvolvimento: duas empresas de exemplo
-- Barbearia (passo 15 min, cancelamento 120 min) e Clínica (passo 30 min,
-- cancelamento 1440 min). Moeda BRL, fuso America/Sao_Paulo, dados fictícios.
--
-- ⚠ LOCAL/DEV ONLY: os usuários inseridos em auth.users usam senha de
-- desenvolvimento fixa ('slot-and-tell-dev'). Nunca usar estas contas ou
-- senha em piloto ou produção. Nenhum segredo real existe neste arquivo.
--
-- Idempotente: pode ser reaplicado sobre banco já semeado — on conflict com
-- UUIDs/combinações determinísticas e NOT EXISTS onde não há chave natural —
-- sem duplicar nem erro. Datas relativas a "hoje" (exceções e reservas) não
-- são re-ancoradas em reaplicação (as linhas antigas ficam): para re-gerar o
-- seed com a data atual, use `supabase db reset`.

-- ---------------------------------------------------------------------------
-- Guarda de ambiente: este seed grava credenciais de desenvolvimento e só deve
-- rodar na stack local. Critério explícito: conexões ao PostgreSQL da Supabase
-- Cloud (direta ou pelo pooler) SEMPRE usam TLS; o seed automático do CLI local
-- (`supabase db reset`/`start`) conecta sem TLS na porta do contêiner (54322), e
-- `psql` via socket local também não usa TLS. Portanto: se a sessão atual está
-- sob TLS, isto é um projeto remoto — aborta antes de tocar auth.users.
-- (inet_server_addr não serve de critério: dentro do contêiner a interface do
-- servidor é o IP da rede Docker, não loopback, e o guard quebraria o reset.)
-- Limite honesto: um `psql` sem TLS contra um servidor próprio espelhando
-- produção não é pego — a responsabilidade de mirar o banco certo é de quem
-- executa; por isso o seed também é idempotente e usa apenas dados fictícios.
-- ---------------------------------------------------------------------------
do $$
declare
  uses_ssl boolean;
begin
  select ssl into uses_ssl from pg_stat_ssl where pid = pg_backend_pid();
  if coalesce(uses_ssl, false) then
    raise exception
      'seed.sql é local/DEV only: esta sessão usa TLS (projeto remoto?). Rode apenas via "supabase db reset" na stack local.'
      using errcode = '42501';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Usuários de desenvolvimento (Supabase Auth)
-- ---------------------------------------------------------------------------
-- Senha de todos os usuários: slot-and-tell-dev (somente para o stack local)
-- `on conflict do nothing` (sem alvo): além do PK `id`, cobre violação do
-- unique de `email` do GoTrue — se alguém já criou conta com um destes e-mails
-- pelo Studio/Auth, o seed pula a linha em vez de abortar.
-- Obs. (fora do escopo de #6): aqui não há `auth.identities`; para login por
-- senha via GoTrue no portal (issue #5), cada usuário precisará de uma
-- identity 'email' — o seed injeta a linha de credencial mínima para os testes
-- de schema, não um fluxo de login completo.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  is_sso_user, is_anonymous
) values
  (
    (select id from auth.instances limit 1),
    'aaaaaaaa-0000-4000-8000-000000000001',
    'authenticated', 'authenticated', 'dev.admin@barbearia.example',
    crypt('slot-and-tell-dev', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"name":"Ana Administradora"}',
    now(), now(), false, false
  ),
  (
    (select id from auth.instances limit 1),
    'aaaaaaaa-0000-4000-8000-000000000002',
    'authenticated', 'authenticated', 'dev.recepcao@barbearia.example',
    crypt('slot-and-tell-dev', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"name":"Rui Recepção"}',
    now(), now(), false, false
  ),
  (
    (select id from auth.instances limit 1),
    'aaaaaaaa-0000-4000-8000-000000000003',
    'authenticated', 'authenticated', 'dev.profissional@barbearia.example',
    crypt('slot-and-tell-dev', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"name":"Rafa Almeida"}',
    now(), now(), false, false
  ),
  (
    (select id from auth.instances limit 1),
    'aaaaaaaa-0000-4000-8000-000000000004',
    'authenticated', 'authenticated', 'dev.admin@clinica.example',
    crypt('slot-and-tell-dev', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{"name":"Beth Beneficiária"}',
    now(), now(), false, false
  )
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Empresas (tenants) — dois segmentos com configurações distintas
-- ---------------------------------------------------------------------------
insert into public.tenants
  (id, name, timezone, currency, slot_step_minutes, min_advance_minutes,
   max_horizon_days, cancellation_cutoff_minutes)
values
  ('11111111-1111-4111-8111-111111111111', 'Barbearia Vila Nova',
   'America/Sao_Paulo', 'BRL', 15, 30, 21, 120),
  ('22222222-2222-4222-8222-222222222222', 'Clínica Bem Estar',
   'America/Sao_Paulo', 'BRL', 30, 60, 30, 1440)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Profissionais
-- ---------------------------------------------------------------------------
insert into public.professionals (id, tenant_id, name, active) values
  ('bbbbbbbb-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Rafa Almeida',   true),
  ('bbbbbbbb-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Diego Souza',    true),
  -- Marina existe na agenda antes de ter login (requisito do portal/equipe)
  ('bbbbbbbb-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'Marina Luz',     true),
  ('bbbbbbbb-0000-4000-8000-000000000004', '22222222-2222-4222-8222-222222222222', 'Paula Reis',     true),
  ('bbbbbbbb-0000-4000-8000-000000000005', '22222222-2222-4222-8222-222222222222', 'Bruno Cardoso',  true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Serviços (preços em centavos de BRL). archived_at entra junto do insert
-- (sem UPDATE separado) para que a reaplicação não reancore a data.
-- ---------------------------------------------------------------------------
insert into public.services
  (id, tenant_id, name, description, duration_minutes, price_cents, archived_at) values
  ('cccccccc-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Corte',
   'Corte na tesoura ou máquina com acabamento', 40, 4500, null),
  ('cccccccc-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Barba',
   'Barba modelada com toalha quente', 30, 3500, null),
  ('cccccccc-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'Corte + Barba',
   'Combo completo', 70, 7000, null),
  -- serviço arquivado demonstra "arquivar sem apagar histórico"
  ('cccccccc-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', 'Pezinho',
   'Retirado do catálogo', 20, 2500, now() - interval '10 days'),
  ('cccccccc-0000-4000-8000-000000000011', '22222222-2222-4222-8222-222222222222', 'Avaliação inicial',
   'Avaliação administrativa de entrada', 50, 18000, null),
  ('cccccccc-0000-4000-8000-000000000012', '22222222-2222-4222-8222-222222222222', 'Sessão de fisioterapia',
   'Sessão individual', 45, 14000, null),
  ('cccccccc-0000-4000-8000-000000000013', '22222222-2222-4222-8222-222222222222', 'Retorno',
   'Consulta de retorno', 30, 9000, null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Habilitações de profissionais por serviço
-- ---------------------------------------------------------------------------
insert into public.professional_services (tenant_id, professional_id, service_id) values
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000002'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000003'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000002'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001'),
  ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000002'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000011'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000013'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000012'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000013')
on conflict (tenant_id, professional_id, service_id) do nothing;

-- ---------------------------------------------------------------------------
-- Memberships (equipe com login). Marina não tem login — profissional sem conta.
-- ---------------------------------------------------------------------------
insert into public.memberships (tenant_id, user_id, role, professional_id) values
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-0000-4000-8000-000000000001', 'admin', null),
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-0000-4000-8000-000000000002', 'receptionist', null),
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-0000-4000-8000-000000000003', 'professional', 'bbbbbbbb-0000-4000-8000-000000000001'),
  ('22222222-2222-4222-8222-222222222222', 'aaaaaaaa-0000-4000-8000-000000000004', 'admin', null)
on conflict (tenant_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Expediente semanal (hora local; weekday ISO: 1=segunda ... 7=domingo).
-- Sem chave natural única na tabela: reaplicação é protegida por NOT EXISTS
-- sobre (tenant, profissional, dia, tipo, janela).
-- ---------------------------------------------------------------------------
-- Barbearia — Rafa e Diego: segunda a sábado, 09:00–18:00 com pausa 12:00–13:00
insert into public.weekly_availability
  (tenant_id, professional_id, weekday, kind, local_start, local_end)
select w.tenant_id, w.professional_id, w.weekday, w.kind, w.local_start, w.local_end
  from (
    select '11111111-1111-4111-8111-111111111111'::uuid as tenant_id,
           p.pid as professional_id, d as weekday, 'work'::text as kind,
           time '09:00' as local_start, time '18:00' as local_end
      from (values ('bbbbbbbb-0000-4000-8000-000000000001'::uuid),
                   ('bbbbbbbb-0000-4000-8000-000000000002'::uuid)) as p(pid),
           generate_series(1, 6) as d
    union all
    select '11111111-1111-4111-8111-111111111111'::uuid,
           p.pid, d, 'break', time '12:00', time '13:00'
      from (values ('bbbbbbbb-0000-4000-8000-000000000001'::uuid),
                   ('bbbbbbbb-0000-4000-8000-000000000002'::uuid)) as p(pid),
           generate_series(1, 6) as d
  ) w
 where not exists (
    select 1 from public.weekly_availability e
     where e.tenant_id = w.tenant_id and e.professional_id = w.professional_id
       and e.weekday = w.weekday and e.kind = w.kind
       and e.local_start = w.local_start and e.local_end = w.local_end
  );

-- Barbearia — Marina: quarta a sábado, 10:00–19:00 com pausa 13:00–14:00
insert into public.weekly_availability
  (tenant_id, professional_id, weekday, kind, local_start, local_end)
select w.tenant_id, w.professional_id, w.weekday, w.kind, w.local_start, w.local_end
  from (
    select '11111111-1111-4111-8111-111111111111'::uuid as tenant_id,
           'bbbbbbbb-0000-4000-8000-000000000003'::uuid as professional_id,
           d as weekday, 'work'::text as kind,
           time '10:00' as local_start, time '19:00' as local_end
      from generate_series(3, 6) as d
    union all
    select '11111111-1111-4111-8111-111111111111'::uuid,
           'bbbbbbbb-0000-4000-8000-000000000003'::uuid,
           d, 'break', time '13:00', time '14:00'
      from generate_series(3, 6) as d
  ) w
 where not exists (
    select 1 from public.weekly_availability e
     where e.tenant_id = w.tenant_id and e.professional_id = w.professional_id
       and e.weekday = w.weekday and e.kind = w.kind
       and e.local_start = w.local_start and e.local_end = w.local_end
  );

-- Clínica — Paula: segunda a sexta, 08:00–17:00 com pausa 12:00–13:00
insert into public.weekly_availability
  (tenant_id, professional_id, weekday, kind, local_start, local_end)
select w.tenant_id, w.professional_id, w.weekday, w.kind, w.local_start, w.local_end
  from (
    select '22222222-2222-4222-8222-222222222222'::uuid as tenant_id,
           'bbbbbbbb-0000-4000-8000-000000000004'::uuid as professional_id,
           d as weekday, 'work'::text as kind,
           time '08:00' as local_start, time '17:00' as local_end
      from generate_series(1, 5) as d
    union all
    select '22222222-2222-4222-8222-222222222222'::uuid,
           'bbbbbbbb-0000-4000-8000-000000000004'::uuid,
           d, 'break', time '12:00', time '13:00'
      from generate_series(1, 5) as d
  ) w
 where not exists (
    select 1 from public.weekly_availability e
     where e.tenant_id = w.tenant_id and e.professional_id = w.professional_id
       and e.weekday = w.weekday and e.kind = w.kind
       and e.local_start = w.local_start and e.local_end = w.local_end
  );

-- Clínica — Bruno: terça a sábado, 09:00–18:00 com pausa 12:00–13:00
insert into public.weekly_availability
  (tenant_id, professional_id, weekday, kind, local_start, local_end)
select w.tenant_id, w.professional_id, w.weekday, w.kind, w.local_start, w.local_end
  from (
    select '22222222-2222-4222-8222-222222222222'::uuid as tenant_id,
           'bbbbbbbb-0000-4000-8000-000000000005'::uuid as professional_id,
           d as weekday, 'work'::text as kind,
           time '09:00' as local_start, time '18:00' as local_end
      from generate_series(2, 6) as d
    union all
    select '22222222-2222-4222-8222-222222222222'::uuid,
           'bbbbbbbb-0000-4000-8000-000000000005'::uuid,
           d, 'break', time '12:00', time '13:00'
      from generate_series(2, 6) as d
  ) w
 where not exists (
    select 1 from public.weekly_availability e
     where e.tenant_id = w.tenant_id and e.professional_id = w.professional_id
       and e.weekday = w.weekday and e.kind = w.kind
       and e.local_start = w.local_start and e.local_end = w.local_end
  );

-- ---------------------------------------------------------------------------
-- Exceções pontuais de agenda (datas relativas a hoje, no fuso da empresa).
-- Idempotência por UUID determinístico da exceção (não pela data): reaplicar
-- em outro dia NÃO reancora nem duplica — a linha antiga permanece e a
-- tentativa com o mesmo id vira no-op. Para re-gerar com a data atual, use
-- `supabase db reset` (comportamento documentado do seed relativo a "hoje").
-- ---------------------------------------------------------------------------
with base as (
  select (date_trunc('day', now() at time zone 'America/Sao_Paulo'))::date as today
), wanted (id, tenant_id, professional_id, kind, exception_date, local_start, local_end, reason) as (
  select '1f000000-0000-4000-8000-000000000001'::uuid,
         '11111111-1111-4111-8111-111111111111'::uuid, 'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
         'day_off', today + 7, null::time, null::time, 'Curso de barbearia'
    from base
  union all
  select '1f000000-0000-4000-8000-000000000002'::uuid,
         '11111111-1111-4111-8111-111111111111'::uuid, 'bbbbbbbb-0000-4000-8000-000000000002'::uuid,
         'blocked', today + 3, time '14:00', time '16:00', 'Manutenção da cadeira'
    from base
  union all
  select '1f000000-0000-4000-8000-000000000003'::uuid,
         '11111111-1111-4111-8111-111111111111'::uuid, 'bbbbbbbb-0000-4000-8000-000000000003'::uuid,
         'extra', today + 6, time '09:00', time '12:00', 'Plantão de sábado extra'
    from base
  union all
  select '1f000000-0000-4000-8000-000000000004'::uuid,
         '22222222-2222-4222-8222-222222222222'::uuid, 'bbbbbbbb-0000-4000-8000-000000000004'::uuid,
         'day_off', today + 5, null::time, null::time, 'Férias'
    from base
)
insert into public.schedule_exceptions
  (id, tenant_id, professional_id, kind, exception_date, local_start, local_end, reason)
select w.id, w.tenant_id, w.professional_id, w.kind, w.exception_date,
       w.local_start, w.local_end, w.reason
  from wanted w
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Clientes (fictícios, telefone E.164). `on conflict do nothing` sem alvo:
-- cobre tanto reaplicação (PK id) quanto choque do unique natural
-- (tenant_id, phone_e164) — se um telefone de exemplo já existir com outro
-- id (cliente criado manualmente no mesmo tenant), o seed pula em vez de erro.
-- ---------------------------------------------------------------------------
insert into public.customers (id, tenant_id, name, phone_e164, email) values
  ('dddddddd-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Carlos Pinto',  '+5511999000001', 'carlos@example.com'),
  ('dddddddd-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Joana Prado',   '+5511999000002', null),
  -- cliente sem nome (nome opcional exigido pela especificação)
  ('dddddddd-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', null,            '+5511999000003', null),
  ('dddddddd-0000-4000-8000-000000000011', '22222222-2222-4222-8222-222222222222', 'Marcos Lima',   '+5511998000001', 'marcos@example.com'),
  ('dddddddd-0000-4000-8000-000000000012', '22222222-2222-4222-8222-222222222222', 'Sofia Nogueira','+5511998000002', null)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Reservas de exemplo (instantes gravados em timestamptz; exibição no fuso)
-- ---------------------------------------------------------------------------
-- Datas locais determinísticas relativas a hoje no fuso da empresa
with base as (
  select
    (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '2 days')::timestamp as d2,
    (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '1 day')::timestamp  as d1,
    (date_trunc('day', now() at time zone 'America/Sao_Paulo') - interval '5 days')::timestamp as p5,
    (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '3 days')::timestamp  as d3
)
insert into public.appointments
  (id, tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
   status, source, service_name, service_duration_minutes, price_cents, currency)
select
  x.id, x.tenant_id, x.customer_id, x.professional_id, x.service_id,
  ((case x.day_key when 'd2' then b.d2 when 'd1' then b.d1
                   when 'p5' then b.p5 when 'd3' then b.d3 end) + x.start_offset)
    at time zone 'America/Sao_Paulo',
  ((case x.day_key when 'd2' then b.d2 when 'd1' then b.d1
                   when 'p5' then b.p5 when 'd3' then b.d3 end) + x.end_offset)
    at time zone 'America/Sao_Paulo',
  x.status, x.source, x.service_name, x.service_duration_minutes, x.price_cents, 'BRL'
from base b
cross join (values
  -- Barbearia: corte 10:00–10:40 confirmado + barba 10:40–11:10 pendente.
  -- Intervalos ADJACENTES [) são aceitos pelo exclude de conflito.
  ('eeeeeeee-0000-4000-8000-000000000001'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'dddddddd-0000-4000-8000-000000000001'::uuid, 'bbbbbbbb-0000-4000-8000-000000000001'::uuid, 'cccccccc-0000-4000-8000-000000000001'::uuid, 'd2', interval '10 hours',              interval '10 hours 40 minutes', 'confirmed', 'portal',   'Corte',        40, 4500::bigint),
  ('eeeeeeee-0000-4000-8000-000000000002'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'dddddddd-0000-4000-8000-000000000001'::uuid, 'bbbbbbbb-0000-4000-8000-000000000001'::uuid, 'cccccccc-0000-4000-8000-000000000002'::uuid, 'd2', interval '10 hours 40 minutes', interval '11 hours 10 minutes', 'pending',   'whatsapp', 'Barba',        30, 3500),
  ('eeeeeeee-0000-4000-8000-000000000003'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'dddddddd-0000-4000-8000-000000000002'::uuid, 'bbbbbbbb-0000-4000-8000-000000000002'::uuid, 'cccccccc-0000-4000-8000-000000000003'::uuid, 'd2', interval '14 hours',              interval '15 hours 10 minutes', 'confirmed', 'whatsapp', 'Corte + Barba', 70, 7000),
  -- histórico concluído e cancelada (status inativos não bloqueiam o horário)
  ('eeeeeeee-0000-4000-8000-000000000004'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'dddddddd-0000-4000-8000-000000000003'::uuid, 'bbbbbbbb-0000-4000-8000-000000000001'::uuid, 'cccccccc-0000-4000-8000-000000000001'::uuid, 'p5', interval '9 hours',               interval '9 hours 40 minutes',  'completed', 'portal',   'Corte',        40, 4500),
  ('eeeeeeee-0000-4000-8000-000000000005'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'dddddddd-0000-4000-8000-000000000002'::uuid, 'bbbbbbbb-0000-4000-8000-000000000002'::uuid, 'cccccccc-0000-4000-8000-000000000002'::uuid, 'd3', interval '9 hours',               interval '9 hours 30 minutes',  'cancelled', 'whatsapp', 'Barba',        30, 3500),
  -- Clínica: avaliação amanhã 08:00 e sessão na quinta passada concluída
  ('eeeeeeee-0000-4000-8000-000000000011'::uuid, '22222222-2222-4222-8222-222222222222'::uuid, 'dddddddd-0000-4000-8000-000000000011'::uuid, 'bbbbbbbb-0000-4000-8000-000000000004'::uuid, 'cccccccc-0000-4000-8000-000000000011'::uuid, 'd1', interval '8 hours',               interval '8 hours 50 minutes',  'confirmed', 'portal',   'Avaliação inicial', 50, 18000),
  ('eeeeeeee-0000-4000-8000-000000000012'::uuid, '22222222-2222-4222-8222-222222222222'::uuid, 'dddddddd-0000-4000-8000-000000000012'::uuid, 'bbbbbbbb-0000-4000-8000-000000000005'::uuid, 'cccccccc-0000-4000-8000-000000000012'::uuid, 'p5', interval '15 hours',              interval '15 hours 45 minutes', 'completed', 'whatsapp', 'Sessão de fisioterapia', 45, 14000)
) as x(id, tenant_id, customer_id, professional_id, service_id, day_key, start_offset, end_offset, status, source, service_name, service_duration_minutes, price_cents)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Eventos de auditoria de exemplo (trilha inicial). UUIDs determinísticos:
-- a trilha é append-only, então a reaplicação apenas não insere de novo.
-- ---------------------------------------------------------------------------
insert into public.audit_events
  (id, tenant_id, actor_user_id, actor_kind, entity_type, entity_id, action, changes) values
  ('ffffffff-0000-4000-8000-000000000001',
   '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-0000-4000-8000-000000000001', 'team', 'services', 'cccccccc-0000-4000-8000-000000000004', 'archive',
   '{"archived_at":"seed","reason":"fora do catálogo"}'),
  ('ffffffff-0000-4000-8000-000000000002',
   '22222222-2222-4222-8222-222222222222', 'aaaaaaaa-0000-4000-8000-000000000004', 'team', 'appointments', 'eeeeeeee-0000-4000-8000-000000000011', 'create',
   '{"source":"portal"}'),
  ('ffffffff-0000-4000-8000-000000000003',
   '11111111-1111-4111-8111-111111111111', null, 'system', 'appointments', 'eeeeeeee-0000-4000-8000-000000000005', 'cancel',
   '{"source":"whatsapp","by":"cliente"}')
on conflict (id) do nothing;
