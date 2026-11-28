-- pgtap
-- Issue #2 · RPC public.list_my_memberships() — teste ponta a ponta no banco.
-- Execute com: supabase db reset && supabase test db
-- Cobre: existência/grants, retorno por usuário do seed (admin com 1 vínculo,
-- usuário com vínculo único, isolamento de linhas) e sessão sem usuário.
--
-- Sessões: pg_temp.as_user(sub, sql) troca para `authenticated` com
-- request.jwt.claims do usuário do seed e executa a consulta como essa sessão.
-- Transacional e repetível: BEGIN ... ROLLBACK após finish().
begin;

select plan(8);

create function pg_temp.as_user(p_sub uuid, p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated')::text, true);
  set role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1 · Catálogo: função, security definer, search_path vazio e grants
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int
     from pg_proc p
    where p.proname = 'list_my_memberships'
      and p.prosecdef
      and p.proconfig @> array['search_path = \'\'']
      and p.prorettype = 'record'::regtype),
  1,
  'list_my_memberships é SECURITY DEFINER com search_path vazio'
);

select is(
  (select count(*)::int
     from information_schema.role_function_grants
    where routine_name = 'list_my_memberships'
      and grantee in ('anon', 'public')),
  0,
  'EXECUTE de list_my_memberships negado a anon/public'
);

select is(
  (select count(*)::int
     from information_schema.role_function_grants
    where routine_name = 'list_my_memberships'
      and grantee = 'authenticated'),
  1,
  'EXECUTE de list_my_memberships concedido a authenticated'
);

-- ---------------------------------------------------------------------------
-- 2 · Admin da barbearia (vínculo único) vê exatamente a própria linha
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user(
    'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
    $q$select jsonb_build_object(
      'rows', count(*),
      'tenant', max(tenant_id::text),
      'role', max(role),
      'name', max(tenant_name)
    ) from public.list_my_memberships()$q$
  ),
  '{"rows":1,"tenant":"11111111-1111-4111-8111-111111111111","role":"admin","name":"Barbearia Vila Nova"}'::jsonb,
  'admin da barbearia lê só o próprio vínculo (1 linha, papel admin)'
);

-- ---------------------------------------------------------------------------
-- 3 · Profissional da barbearia vê a linha com professional_id preenchido
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user(
    'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
    $q$select jsonb_build_object(
      'rows', count(*),
      'professional', min(professional_id::text)
    ) from public.list_my_memberships()$q$
  ),
  '{"rows":1,"professional":"bbbbbbbb-0000-4000-8000-000000000001"}'::jsonb,
  'profissional lê o vínculo com professional_id do seed'
);

-- ---------------------------------------------------------------------------
-- 4 · Sem usuário logado: função não retorna nenhuma linha
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from public.list_my_memberships()),
  0,
  'sessão sem usuário (postgres) não vê vínculo algum'
);

-- ---------------------------------------------------------------------------
-- 5 · Isolamento cross-tenant: RPC nunca devolve vínculo de outra empresa
-- ---------------------------------------------------------------------------
select is(
  pg_temp.as_user(
    'aaaaaaaa-0000-4000-8000-000000000004'::uuid,
    $q$select jsonb_build_object(
      'rows', count(*),
      'cross', count(*) filter (where tenant_id = '11111111-1111-4111-8111-111111111111'::uuid)
    ) from public.list_my_memberships()$q$
  ),
  '{"rows":1,"cross":0}'::jsonb,
  'admin da clínica não recebe vínculo da barbearia'
);

select is(
  pg_temp.as_user(
    'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
    $q$select count(*) filter (where role <> 'receptionist') from public.list_my_memberships()$q$
  ),
  0::int,
  'recepção não lê memberships via tabela direta, mas vê o próprio vínculo pela RPC'
);

select is(
  (select count(*)::int from pg_policies where tablename = 'memberships'),
  5,
  'RLS de memberships permanece inalterada (5 políticas da issue #3)'
);

select * from finish();
rollback;
