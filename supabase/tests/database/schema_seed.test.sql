-- pgtap
-- Issue #6 · Verificação local reprodutível do DoD das migrations e seed.
-- Execute com: supabase db reset && supabase test db
-- Cobre: 10 tabelas, seed de 2 empresas, rejeição de FK cruzada entre tenants,
-- rejeição de overlap em reservas ativas, aceitação de intervalos adjacentes [),
-- triggers updated_at, unicidade de contato por empresa, acesso deny-by-default,
-- trilha de auditoria imutável e consistência do snapshot de duração.
--
-- Transacional e repetível: o arquivo abre BEGIN e encerra com ROLLBACK depois
-- de finish(), então os inserts/updates dos testes nunca persistem — é possível
-- rodar `supabase test db` quantas vezes seguidas quiser sem `db reset` no meio.
begin;

select plan(28);

-- Auxílio do teste comportamental de grants: roda a sonda como `anon` dentro de
-- uma subtransação (throws_ok usa bloco de exceção), então o `set local role` é
-- desfeito no rollback do savepoint — o restante do teste continua como postgres.
create function pg_temp.probe_as_anon_select_tenants()
returns bigint
language plpgsql
as $$
begin
  set local role anon;
  return (select count(*) from public.tenants);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1 · Estrutura: as 10 tabelas núcleo existem
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from information_schema.tables
    where table_schema = 'public'
      and table_name = any(array[
        'tenants','memberships','professionals','services','professional_services',
        'weekly_availability','schedule_exceptions','customers','appointments','audit_events'])),
  10,
  'as 10 tabelas núcleo do schema base existem'
);

-- ---------------------------------------------------------------------------
-- 2 · Seed: duas empresas com configurações distintas, BRL e America/Sao_Paulo
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.tenants), 2, 'seed: duas empresas de exemplo');

select is(
  (select count(*)::int from public.tenants
    where timezone = 'America/Sao_Paulo' and currency = 'BRL'),
  2,
  'seed: ambas em America/Sao_Paulo e BRL'
);

select isnt(
  (select slot_step_minutes from public.tenants where id = '11111111-1111-4111-8111-111111111111'),
  (select slot_step_minutes from public.tenants where id = '22222222-2222-4222-8222-222222222222'),
  'seed: passo de oferta distinto entre barbearia e clínica'
);

-- ---------------------------------------------------------------------------
-- 3 · Intervalos [): adjacentes no seed existem e a range é gerada correta
-- ---------------------------------------------------------------------------
select ok(
  exists (
    select 1
      from public.appointments a
      join public.appointments b
        on b.professional_id = a.professional_id
       and b.tenant_id = a.tenant_id
       and b.starts_at = a.ends_at
     where a.id = 'eeeeeeee-0000-4000-8000-000000000001'
       and b.id = 'eeeeeeee-0000-4000-8000-000000000002'
  ),
  'seed: reservas adjacentes (fim == início) coexistem para o mesmo profissional'
);

select is(
  (select lower_inc(time_range) and not upper_inc(time_range)
     from public.appointments
    where id = 'eeeeeeee-0000-4000-8000-000000000001'),
  true,
  'appointments.time_range é gerado como tstzrange com limites [)'
);

select ok(
  exists (
    select 1 from pg_constraint
     where conname = 'appointments_no_active_overlap' and contype = 'x'
  ),
  'restrição de exclusão GiST para reservas ativas está aplicada'
);

-- ---------------------------------------------------------------------------
-- 4 · Conflito: overlap com reserva ativa do mesmo profissional é rejeitado
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
  insert into public.appointments
    (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
     status, service_name, service_duration_minutes, price_cents, currency)
  select tenant_id, customer_id, professional_id, service_id,
         starts_at + interval '20 minutes', ends_at + interval '20 minutes',
         'confirmed', service_name, service_duration_minutes, price_cents, currency
    from public.appointments
   where id = 'eeeeeeee-0000-4000-8000-000000000001'
  $$,
  '23P01', null,
  'overlap com reserva ativa do mesmo profissional é rejeitado (exclusão GiST)'
);

-- ---------------------------------------------------------------------------
-- 5 · Adjacência aceita em inserção nova (encostada no fim da última reserva)
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
  insert into public.appointments
    (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
     status, service_name, service_duration_minutes, price_cents, currency)
  select tenant_id, customer_id, professional_id, service_id,
         ends_at, ends_at + interval '30 minutes',
         'confirmed', 'Barba', 30, 3500, 'BRL'
    from public.appointments
   where id = 'eeeeeeee-0000-4000-8000-000000000002'
  $$,
  'inserir reserva iniciando exatamente no fim da anterior é aceito ([))'
);

-- ---------------------------------------------------------------------------
-- 6 · Status inativo (cancelled) não bloqueia horário
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
  insert into public.appointments
    (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
     status, service_name, service_duration_minutes, price_cents, currency)
  select tenant_id, customer_id, professional_id, service_id,
         starts_at, ends_at, 'cancelled', service_name,
         service_duration_minutes, price_cents, currency
    from public.appointments
   where id = 'eeeeeeee-0000-4000-8000-000000000001'
  $$,
  'reserva cancelled sobreposta a ativa é permitida (exclude só para pending/confirmed)'
);

-- ---------------------------------------------------------------------------
-- 7 · Isolamento entre tenants: FK cruzada rejeitada
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
  insert into public.appointments
    (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
     status, service_name, service_duration_minutes, price_cents, currency)
  values
    ('11111111-1111-4111-8111-111111111111',
     'dddddddd-0000-4000-8000-000000000001',
     'bbbbbbbb-0000-4000-8000-000000000001',
     'cccccccc-0000-4000-8000-000000000011',  -- serviço da CLÍNICA na BARBEARIA
     now() + interval '60 days', now() + interval '60 days 50 minutes',
     'confirmed', 'Avaliação inicial', 50, 18000, 'BRL')
  $$,
  '23503', null,
  'reserva não pode referenciar serviço de outra empresa (FK composta tenant_id)'
);

select throws_ok(
  $$
  insert into public.memberships (tenant_id, user_id, role, professional_id)
  values
    ('11111111-1111-4111-8111-111111111111',
     'aaaaaaaa-0000-4000-8000-000000000004',  -- usuário da clínica
     'professional',
     'bbbbbbbb-0000-4000-8000-000000000004')  -- profissional da clínica
  $$,
  '23503', null,
  'membership não pode vincular profissional de outra empresa (FK composta tenant_id)'
);

-- ---------------------------------------------------------------------------
-- 8 · Cliente: identidade única por empresa e contato
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
  insert into public.customers (tenant_id, name, phone_e164)
  values ('11111111-1111-4111-8111-111111111111', 'Clone', '+5511999000001')
  $$,
  '23505', null,
  'telefone duplicado dentro da mesma empresa é rejeitado'
);

select lives_ok(
  $$
  insert into public.customers (tenant_id, name, phone_e164)
  values ('22222222-2222-4222-8222-222222222222', 'Mesmo telefone, outra empresa', '+5511999000001')
  $$,
  'o mesmo telefone pode existir em empresas diferentes'
);

-- ---------------------------------------------------------------------------
-- 9 · Triggers updated_at
-- ---------------------------------------------------------------------------
with snapshot as (
  select updated_at as before from public.tenants
   where id = '11111111-1111-4111-8111-111111111111'
),
touched as (
  update public.tenants set name = name
   where id = '11111111-1111-4111-8111-111111111111'
   returning updated_at as after
)
select is(t.after > s.before, true, 'trigger updated_at avança em tenants')
  from touched t, snapshot s;

with snapshot as (
  select updated_at as before from public.appointments
   where id = 'eeeeeeee-0000-4000-8000-000000000002'
),
touched as (
  update public.appointments set status = 'confirmed'
   where id = 'eeeeeeee-0000-4000-8000-000000000002'
   returning updated_at as after
)
select is(t.after > s.before, true, 'trigger updated_at avança em appointments')
  from touched t, snapshot s;

-- ---------------------------------------------------------------------------
-- 10 · Snapshot de serviço prescinde do catálogo e fica gravado na reserva
-- ---------------------------------------------------------------------------
select is(
  (select service_name || ':' || price_cents::text || ':' || currency
     from public.appointments
    where id = 'eeeeeeee-0000-4000-8000-000000000001'),
  'Corte:4500:BRL',
  'reserva guarda snapshot de nome, preço (centavos) e moeda'
);

-- ---------------------------------------------------------------------------
-- 11 · Snapshot de duração bate com o intervalo gravado (revisão #6)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
  insert into public.appointments
    (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at,
     status, service_name, service_duration_minutes, price_cents, currency)
  values
    ('11111111-1111-4111-8111-111111111111',
     'dddddddd-0000-4000-8000-000000000001',
     'bbbbbbbb-0000-4000-8000-000000000001',
     'cccccccc-0000-4000-8000-000000000001',
     now() + interval '90 days', now() + interval '90 days 40 minutes',
     'confirmed', 'Corte', 10, 4500, 'BRL')  -- 40 min de intervalo, snapshot 10
  $$,
  '23514', null,
  'snapshot de duração divergente do intervalo da reserva é rejeitado'
);

-- ---------------------------------------------------------------------------
-- 12 · Acesso negado por padrão até a issue #3 (revisão #6)
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and c.relname = any(array[
        'tenants','memberships','professionals','services','professional_services',
        'weekly_availability','schedule_exceptions','customers','appointments','audit_events'])),
  10,
  'RLS habilitado nas 10 tabelas núcleo'
);

select is(
  (select count(*)::int from pg_policies where schemaname = 'public'),
  0,
  'nenhuma política ainda: deny-by-default até a issue #3'
);

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'authenticated')),
  0,
  'anon/authenticated sem nenhuma permissão de tabela no schema public'
);

-- Teste comportamental (não só catálogo): sob `anon`, a SELECT real falha.
select throws_ok(
  'select pg_temp.probe_as_anon_select_tenants()',
  '42501', null,
  'sessão anon não consegue nem contar tenants (deny-by-default efetivo)'
);

-- Mesma asserção via catálogo, cobrindo escrita e o papel authenticated
select is(has_table_privilege('authenticated', 'public.appointments', 'insert'), false,
  'authenticated sem INSERT em appointments');
select is(has_function_privilege('anon', 'public.set_updated_at()', 'execute'), false,
  'anon sem EXECUTE nas funções do schema public');

-- ---------------------------------------------------------------------------
-- 13 · audit_events é append-only (revisão #6)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
  update public.audit_events
     set action = 'delete'
   where id = (select id from public.audit_events limit 1)
  $$,
  '42501', null,
  'UPDATE em audit_events é rejeitado pela trilha append-only'
);

select throws_ok(
  $$
  delete from public.audit_events
   where id = (select id from public.audit_events limit 1)
  $$,
  '42501', null,
  'DELETE em audit_events é rejeitado pela trilha append-only'
);

select * from finish();
rollback;
