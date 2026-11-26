-- pgtap
-- Issue #3 · Isolamento entre empresas (RLS) — teste ponta a ponta no banco.
-- Execute com: supabase db reset && supabase test db
-- Cobre: catálogo de grants/políticas/helpers, acesso cruzado por ID direto
-- (SELECT/UPDATE/INSERT/mudança de tenant_id) entre a barbearia e a clínica,
-- gates por papel (admin/recepção/profissional) e sessão sem usuário.
--
-- Sessões: pg_temp.as_user(sub, sql) troca para `authenticated` com
-- request.jwt.claims do usuário do seed e executa a consulta/DML como essa
-- sessão. Falhas (42501) são pegas por throws_ok em subtransação, então o
-- `set role` é desfeito no rollback do savepoint e o restante roda como postgres.
--
-- Transacional e repetível: BEGIN ... ROLLBACK após finish().
begin;

select plan(48);

create function pg_temp.as_user(p_sub uuid, p_sql text)
returns int
language plpgsql
as $$
declare
  n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
  set role authenticated;
  execute p_sql into n;
  reset role;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1 · Catálogo: políticas, grants e helpers
-- ---------------------------------------------------------------------------
select is(
  (select count(distinct tablename)::int from pg_policies where schemaname = 'public'),
  10,
  'políticas por empresa cobrem 10 de 10 tabelas'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and not ('authenticated'::name = any (roles))),
  0,
  'toda política é destinada a authenticated (anon não tem política)'
);

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'),
  0,
  'anon mantém 0 grants de tabela'
);

select ok(
  not has_table_privilege('authenticated', 'public.appointments', 'delete')
  and not has_table_privilege('authenticated', 'public.audit_events', 'insert')
  and not has_table_privilege('authenticated', 'public.audit_events', 'update')
  and not has_table_privilege('authenticated', 'public.audit_events', 'delete'),
  'authenticated sem DELETE em appointments e sem escrita em audit_events'
);

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  0,
  'anon sem EXECUTE em nenhuma função do schema public'
);

select ok(
  has_function_privilege('authenticated', 'public.has_membership(uuid, text[])', 'execute')
  and has_function_privilege('authenticated', 'public.own_professional_id(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.assert_tenant_role(uuid, text[])', 'execute'),
  'helpers de sessão executáveis por authenticated'
);

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef),
  3,
  'exatamente os 3 helpers de sessão são SECURITY DEFINER'
);

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'),
  0,
  'funções SECURITY DEFINER fixam search_path (sem resolução por nome não qualificado)'
);

-- ---------------------------------------------------------------------------
-- 2 · Acesso cruzado: admin da barbearia (A) tentando alcançar a clínica (B)
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.tenants$q$),
  1,
  'admin A vê somente a própria empresa em tenants'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.tenants where id = '22222222-2222-4222-8222-222222222222'$q$),
  0,
  'admin A não lê a empresa B por ID direto'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.services where id = 'cccccccc-0000-4000-8000-000000000011'$q$),
  0,
  'admin A: serviço da clínica por ID direto retorna 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.customers where id = 'dddddddd-0000-4000-8000-000000000011'$q$),
  0,
  'admin A: cliente da clínica por ID direto retorna 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.appointments where id = 'eeeeeeee-0000-4000-8000-000000000011'$q$),
  0,
  'admin A: reserva da clínica por ID direto retorna 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.audit_events where id = 'ffffffff-0000-4000-8000-000000000002'$q$),
  0,
  'admin A: evento de auditoria da clínica por ID direto retorna 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$
    select count(*) from (
      select tenant_id from public.memberships
      union all select tenant_id from public.professionals
      union all select tenant_id from public.services
      union all select tenant_id from public.professional_services
      union all select tenant_id from public.weekly_availability
      union all select tenant_id from public.schedule_exceptions
      union all select tenant_id from public.customers
      union all select tenant_id from public.appointments
      union all select tenant_id from public.audit_events
    ) s where s.tenant_id = '22222222-2222-4222-8222-222222222222'$q$),
  0,
  'admin A: nenhuma linha do tenant B nas 9 tabelas de empresa'
);

select ok(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$
    select count(*) from (
      select tenant_id from public.memberships
      union all select tenant_id from public.professionals
      union all select tenant_id from public.services
      union all select tenant_id from public.professional_services
      union all select tenant_id from public.weekly_availability
      union all select tenant_id from public.schedule_exceptions
      union all select tenant_id from public.customers
      union all select tenant_id from public.appointments
      union all select tenant_id from public.audit_events
    ) s where s.tenant_id = '11111111-1111-4111-8111-111111111111'$q$) > 0,
  'controle positivo: admin A enxerga as linhas da própria empresa'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (update public.services set name = name where id = 'cccccccc-0000-4000-8000-000000000011' returning 1) select count(*) from x$q$),
  0,
  'UPDATE por ID de serviço da clínica afeta 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (update public.appointments set status = status where id = 'eeeeeeee-0000-4000-8000-000000000011' returning 1) select count(*) from x$q$),
  0,
  'UPDATE por ID de reserva da clínica afeta 0 linhas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (update public.tenants set name = name where id = '22222222-2222-4222-8222-222222222222' returning 1) select count(*) from x$q$),
  0,
  'UPDATE da empresa B por ID afeta 0 linhas'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (insert into public.services (tenant_id, name, duration_minutes, price_cents) values ('22222222-2222-4222-8222-222222222222', 'Invasão', 30, 100) returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'INSERT de serviço com tenant_id da clínica é negado pela política'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (update public.services set tenant_id = '22222222-2222-4222-8222-222222222222' where id = 'cccccccc-0000-4000-8000-000000000001' returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'mover serviço da própria empresa para o tenant B é negado (WITH CHECK)'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (insert into public.appointments (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at, status, service_name, service_duration_minutes, price_cents, currency) values ('22222222-2222-4222-8222-222222222222', 'dddddddd-0000-4000-8000-000000000011', 'bbbbbbbb-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000011', now() + interval '200 days', now() + interval '200 days 50 minutes', 'confirmed', 'Avaliação inicial', 50, 18000, 'BRL') returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'INSERT de reserva com tenant_id da clínica é negado pela política'
);

-- ---------------------------------------------------------------------------
-- 2b · Simétrico: admin da clínica (B) não alcança a barbearia (A)
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000004', $q$select count(*) from public.appointments where tenant_id = '11111111-1111-4111-8111-111111111111'$q$),
  0,
  'admin B não lê reservas da barbearia (A)'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000004', $q$select count(*) from public.services where tenant_id = '11111111-1111-4111-8111-111111111111'$q$),
  0,
  'admin B não lê serviços da barbearia (A)'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000004', $q$select count(*) from public.appointments$q$),
  (select count(*) from public.appointments where tenant_id = '22222222-2222-4222-8222-222222222222')::int,
  'admin B vê todas e somente as reservas da própria clínica'
);

-- ---------------------------------------------------------------------------
-- 3 · Papéis dentro da mesma empresa (barbearia)
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.appointments$q$),
  (select count(*)::int from public.appointments where tenant_id = '11111111-1111-4111-8111-111111111111'),
  'admin lista as reservas da própria empresa'
);

select ok(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$select count(*) from public.audit_events$q$) > 0,
  'admin lê a trilha de auditoria da própria empresa'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000002', $q$select count(*) from public.audit_events$q$),
  0,
  'recepção não lê audit_events'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000002', $q$select count(*) from public.memberships$q$),
  0,
  'recepção não lê memberships'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.audit_events$q$),
  0,
  'profissional não lê audit_events'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.memberships$q$),
  1,
  'profissional lê somente a própria linha de memberships'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.appointments$q$),
  3,
  'profissional Rafa vê as 3 reservas do próprio professional_id (e não as 5 da empresa)'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.appointments where professional_id <> 'bbbbbbbb-0000-4000-8000-000000000001'$q$),
  0,
  'profissional não vê reservas de colegas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.appointments where tenant_id = '22222222-2222-4222-8222-222222222222'$q$),
  0,
  'profissional da barbearia não vê reservas da clínica'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.professionals$q$),
  3,
  'profissional lê a equipe da própria empresa'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (update public.appointments set status = status where id = 'eeeeeeee-0000-4000-8000-000000000001' returning 1) select count(*) from x$q$),
  0,
  'profissional não altera nem a própria reserva (agenda é somente leitura até a RPC)'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (insert into public.appointments (tenant_id, customer_id, professional_id, service_id, starts_at, ends_at, status, service_name, service_duration_minutes, price_cents, currency) values ('11111111-1111-4111-8111-111111111111', 'dddddddd-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', now() + interval '400 days', now() + interval '400 days 40 minutes', 'confirmed', 'Corte', 40, 4500, 'BRL') returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'profissional não cria reservas'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (update public.weekly_availability set kind = kind where professional_id = 'bbbbbbbb-0000-4000-8000-000000000002' returning 1) select count(*) from x$q$),
  0,
  'profissional não altera expediente de colega'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (update public.weekly_availability set kind = kind where professional_id = 'bbbbbbbb-0000-4000-8000-000000000001' returning 1) select count(*) from x$q$),
  (select count(*)::int from public.weekly_availability where professional_id = 'bbbbbbbb-0000-4000-8000-000000000001'),
  'profissional altera o próprio expediente'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (update public.services set name = name where tenant_id = '11111111-1111-4111-8111-111111111111' returning 1) select count(*) from x$q$),
  0,
  'profissional não altera o catálogo de serviços'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$with x as (update public.tenants set name = name where id = '11111111-1111-4111-8111-111111111111' returning 1) select count(*) from x$q$),
  0,
  'profissional não altera a empresa'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000003', $q$select count(*) from public.appointments where tenant_id = '22222222-2222-4222-8222-222222222222'$q$),
  0,
  'profissional da barbearia não lê reservas da clínica por tenant_id'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000002', $q$with x as (insert into public.customers (tenant_id, name, phone_e164) values ('11111111-1111-4111-8111-111111111111', 'Novo cliente', '+5511977000001') returning 1) select count(*) from x$q$),
  1,
  'recepção cria cliente na própria empresa'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000002', $q$with x as (delete from public.appointments where id = 'eeeeeeee-0000-4000-8000-000000000001' returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'recepção não exclui reservas (sem DELETE: ciclo via status)'
);

select throws_ok(
  $$select pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (delete from public.appointments where id = 'eeeeeeee-0000-4000-8000-000000000001' returning 1) select count(*) from x$q$)$$,
  '42501', null,
  'admin não exclui reservas (sem DELETE: ciclo via status)'
);

select is(
  pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001', $q$with x as (update public.memberships set role = role where tenant_id = '22222222-2222-4222-8222-222222222222' returning 1) select count(*) from x$q$),
  0,
  'admin da barbearia não altera vínculos da clínica'
);

-- ---------------------------------------------------------------------------
-- 4 · Sessão sem usuário vinculado
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user(null, $q$select count(*) from public.tenants$q$),
  0,
  'sessão authenticated sem auth.uid() não vê empresas'
);

select is(
  pg_temp.as_user(null, $q$select count(*) from public.appointments$q$),
  0,
  'sessão authenticated sem auth.uid() não vê reservas'
);

select * from finish();
rollback;
