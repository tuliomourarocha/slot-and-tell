-- Issue #2 · RPC de leitura dos próprios vínculos (empresa + papel)
-- O shell do portal precisa listar empresas e papéis do usuário logado sem
-- abrir a tabela memberships: RLS atual não deixa recepção ler vínculos alheios
-- e a leitura direta exigiria políticas extras. SECURITY DEFINER com
-- search_path vazio segue o padrão dos helpers da issue #3.
-- RLS de memberships permanece inalterada (critério de aceite 6).

create function public.list_my_memberships()
returns table (
  tenant_id uuid,
  tenant_name text,
  role text,
  professional_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.name, m.role, m.professional_id
    from public.memberships m
    join public.tenants t on t.id = m.tenant_id
   where m.user_id = auth.uid()
     and t.status = 'active'
   order by t.name, m.role;
$$;

revoke all on function public.list_my_memberships() from public, anon;
grant execute on function public.list_my_memberships() to authenticated;

comment on function public.list_my_memberships() is
  'Portal: vínculos (empresa, papel, profissional) do usuário logado, lidos via SECURITY DEFINER porque a recepção não lê memberships diretamente por RLS.';
