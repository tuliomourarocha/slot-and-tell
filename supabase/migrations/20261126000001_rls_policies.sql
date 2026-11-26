-- Issue #3 · RLS por empresa e papel + grants de objeto + helpers de sessão
-- Fronteira de isolamento: vínculo validado em public.memberships (auth.uid()),
-- nunca claim de "empresa ativa" no JWT. Escolha de empresa na UI é filtro de UX.
-- Matriz de acesso: README, seção "Política de acesso (RLS)".

-- ---------------------------------------------------------------------------
-- Helpers de sessão (SECURITY DEFINER, search_path vazio)
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER evita recursão de RLS: as políticas de memberships consultam
-- memberships através destes helpers, que rodam como dono e não reavaliam RLS.
create function public.has_membership(p_tenant_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.memberships m
     where m.user_id = auth.uid()
       and m.tenant_id = p_tenant_id
       and m.role = any (p_roles)
  );
$$;

-- Profissional da agenda vinculado ao usuário logado na empresa (nulo se não houver).
create function public.own_professional_id(p_tenant_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.professional_id
    from public.memberships m
   where m.user_id = auth.uid()
     and m.tenant_id = p_tenant_id
     and m.role = 'professional';
$$;

-- Ponto único de validação para RPCs privilegiadas futuras (padrão obrigatório):
-- levanta 42501 quando o usuário logado não tem papel permitido na empresa.
create function public.assert_tenant_role(p_tenant_id uuid, p_roles text[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_membership(p_tenant_id, p_roles) then
    raise exception 'acesso negado: papel insuficiente na empresa'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.has_membership(uuid, text[]) from public, anon;
revoke all on function public.own_professional_id(uuid) from public, anon;
revoke all on function public.assert_tenant_role(uuid, text[]) from public, anon;
grant execute on function public.has_membership(uuid, text[]) to authenticated;
grant execute on function public.own_professional_id(uuid) to authenticated;
grant execute on function public.assert_tenant_role(uuid, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Grants de objeto (segunda camada; RLS filtra as linhas)
-- ---------------------------------------------------------------------------
grant select, update                         on public.tenants               to authenticated;
grant select, insert, update, delete         on public.memberships           to authenticated;
grant select, insert, update                 on public.professionals         to authenticated;
grant select, insert, update                 on public.services              to authenticated;
grant select, insert, update, delete         on public.professional_services to authenticated;
grant select, insert, update, delete         on public.weekly_availability   to authenticated;
grant select, insert, update, delete         on public.schedule_exceptions   to authenticated;
grant select, insert, update, delete         on public.customers             to authenticated;
grant select, insert, update                 on public.appointments          to authenticated;
grant select                                 on public.audit_events          to authenticated;

-- ---------------------------------------------------------------------------
-- tenants
-- ---------------------------------------------------------------------------
create policy tenants_select_member on public.tenants
  for select to authenticated
  using (public.has_membership(id, array['admin', 'receptionist', 'professional']));

create policy tenants_update_admin on public.tenants
  for update to authenticated
  using (public.has_membership(id, array['admin']))
  with check (public.has_membership(id, array['admin']));

-- ---------------------------------------------------------------------------
-- memberships — admin gerencia a empresa; profissional lê só a própria linha
-- ---------------------------------------------------------------------------
create policy memberships_select_admin on public.memberships
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin']));

create policy memberships_select_own_professional on public.memberships
  for select to authenticated
  using (user_id = auth.uid() and role = 'professional');

create policy memberships_insert_admin on public.memberships
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin']));

create policy memberships_update_admin on public.memberships
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin']))
  with check (public.has_membership(tenant_id, array['admin']));

create policy memberships_delete_admin on public.memberships
  for delete to authenticated
  using (public.has_membership(tenant_id, array['admin']));

-- ---------------------------------------------------------------------------
-- professionals — admin CRUD; recepção S/I/U; profissional S
-- ---------------------------------------------------------------------------
create policy professionals_select_member on public.professionals
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy professionals_insert_front on public.professionals
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy professionals_update_front on public.professionals
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']))
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy professionals_delete_admin on public.professionals
  for delete to authenticated
  using (public.has_membership(tenant_id, array['admin']));

-- ---------------------------------------------------------------------------
-- services — S/I/U para admin e recepção (arquivar = update); sem DELETE
-- ---------------------------------------------------------------------------
create policy services_select_member on public.services
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy services_insert_front on public.services
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy services_update_front on public.services
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']))
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

-- ---------------------------------------------------------------------------
-- professional_services — admin e recepção CRUD; profissional S
-- ---------------------------------------------------------------------------
create policy professional_services_select_member on public.professional_services
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy professional_services_insert_front on public.professional_services
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy professional_services_update_front on public.professional_services
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']))
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy professional_services_delete_front on public.professional_services
  for delete to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']));

-- ---------------------------------------------------------------------------
-- weekly_availability e schedule_exceptions — admin/recepção CRUD;
-- profissional S da empresa e I/U/D das próprias linhas
-- ---------------------------------------------------------------------------
create policy weekly_availability_select_member on public.weekly_availability
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy weekly_availability_insert_front_or_own on public.weekly_availability
  for insert to authenticated
  with check (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy weekly_availability_update_front_or_own on public.weekly_availability
  for update to authenticated
  using (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  )
  with check (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy weekly_availability_delete_front_or_own on public.weekly_availability
  for delete to authenticated
  using (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy schedule_exceptions_select_member on public.schedule_exceptions
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy schedule_exceptions_insert_front_or_own on public.schedule_exceptions
  for insert to authenticated
  with check (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy schedule_exceptions_update_front_or_own on public.schedule_exceptions
  for update to authenticated
  using (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  )
  with check (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy schedule_exceptions_delete_front_or_own on public.schedule_exceptions
  for delete to authenticated
  using (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

-- ---------------------------------------------------------------------------
-- customers — admin e recepção CRUD; profissional S
-- ---------------------------------------------------------------------------
create policy customers_select_member on public.customers
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist', 'professional']));

create policy customers_insert_front on public.customers
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy customers_update_front on public.customers
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']))
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy customers_delete_front on public.customers
  for delete to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']));

-- ---------------------------------------------------------------------------
-- appointments — admin/recepção S/I/U (sem DELETE: ciclo via status);
-- profissional só lê as reservas do próprio professional_id
-- ---------------------------------------------------------------------------
create policy appointments_select_front_or_own on public.appointments
  for select to authenticated
  using (
    public.has_membership(tenant_id, array['admin', 'receptionist'])
    or professional_id = public.own_professional_id(tenant_id)
  );

create policy appointments_insert_front on public.appointments
  for insert to authenticated
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

create policy appointments_update_front on public.appointments
  for update to authenticated
  using (public.has_membership(tenant_id, array['admin', 'receptionist']))
  with check (public.has_membership(tenant_id, array['admin', 'receptionist']));

-- ---------------------------------------------------------------------------
-- audit_events — leitura só admin; escrita apenas por service_role (RPC futura)
-- ---------------------------------------------------------------------------
create policy audit_events_select_admin on public.audit_events
  for select to authenticated
  using (public.has_membership(tenant_id, array['admin']));

-- ---------------------------------------------------------------------------
-- Comentários
-- ---------------------------------------------------------------------------
comment on function public.has_membership(uuid, text[]) is
  'Helper de RLS/RPC: o usuário logado (auth.uid()) tem vínculo na empresa com um dos papéis. SECURITY DEFINER, search_path vazio, EXECUTE só para authenticated.';
comment on function public.own_professional_id(uuid) is
  'Helper de RLS: profissional da agenda vinculado ao usuário logado na empresa, ou nulo.';
comment on function public.assert_tenant_role(uuid, text[]) is
  'Padrão obrigatório de RPC privilegiada: levanta 42501 se o usuário logado não tem papel permitido na empresa informada.';
