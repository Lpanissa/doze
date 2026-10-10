-- Os Doze — 10/10/2026 — Grupo livre ou fechado: se livre, o testador entra sem o dono aceitar.
alter table public.doze_apps add column if not exists group_open boolean not null default false;

create or replace function public.doze_set_join_v2(p_app uuid, p_method text, p_group_url text, p_open boolean)
 returns void language plpgsql security definer set search_path to 'public' as
$$
begin
  perform public.doze_set_join(p_app, p_method, p_group_url);
  update public.doze_apps set group_open = (p_method='grupo' and coalesce(p_open,false)) where id=p_app and owner_id=auth.uid();
end $$;

create or replace function public.doze_my_apps_v7()
 returns table(id uuid, name text, description text, package_name text, opt_in_url text, icon_url text, status text, testers_needed integer, active_testers bigint, pending_testers bigint, created_at timestamptz, liberado boolean, test_started_at timestamptz, accepted bigint, start_mode text, screenshots text[], category text, join_method text, group_url text, group_open boolean)
 language sql stable security definer set search_path to 'public' as
$$ select m.*, a.group_open from public.doze_my_apps_v6() m join public.doze_apps a on a.id=m.id $$;

create or replace function public.doze_list_apps_v6()
 returns table(id uuid, owner_id uuid, owner_name text, name text, description text, package_name text, icon_url text, testers_needed integer, active_testers bigint, created_at timestamptz, liberado boolean, screenshots text[], category text, start_mode text, group_open boolean)
 language sql stable security definer set search_path to 'public' as
$$ select l.*, (a.join_method='grupo' and a.group_open) from public.doze_list_apps_v5() l join public.doze_apps a on a.id=l.id $$;

-- entrar no teste: grupo livre = aceito na hora (se o teste ainda não começou e o app está liberado)
create or replace function public.doze_join_test(p_app uuid)
 returns doze_tests language plpgsql security definer set search_path to 'public' as
$function$
declare a public.doze_apps; r public.doze_tests;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  if not exists (select 1 from public.doze_profiles where id = auth.uid()) then raise exception 'perfil não encontrado'; end if;
  select * into a from public.doze_apps where id = p_app and status = 'ativo';
  if a.id is null then raise exception 'app não encontrado'; end if;
  if a.owner_id = auth.uid() then raise exception 'você não pode testar o próprio app'; end if;
  if exists (select 1 from public.doze_blocks where app_id=p_app and user_id=auth.uid()) then raise exception 'O dono deste app bloqueou você neste projeto.'; end if;
  insert into public.doze_tests(app_id, tester_id) values (p_app, auth.uid())
  on conflict (app_id, tester_id) do update set
    status = case when public.doze_tests.status = 'saiu' then 'pendente' else public.doze_tests.status end,
    flagged = case when public.doze_tests.status = 'saiu' then false else public.doze_tests.flagged end,
    added_at = case when public.doze_tests.status = 'saiu' then null else public.doze_tests.added_at end,
    installed_at = case when public.doze_tests.status = 'saiu' then null else public.doze_tests.installed_at end,
    joined_at = case when public.doze_tests.status = 'saiu' then now() else public.doze_tests.joined_at end
  returning * into r;
  if r.status = 'pendente' and a.join_method = 'grupo' and a.group_open and a.test_started_at is null and public.doze_app_liberado(a.id) then
    update public.doze_tests set status='adicionado', added_at=now() where id=r.id returning * into r;
  end if;
  return r;
end $function$;

revoke execute on function public.doze_set_join_v2(uuid,text,text,boolean) from public, anon;
revoke execute on function public.doze_my_apps_v7() from public, anon;
revoke execute on function public.doze_list_apps_v6() from public, anon;
grant execute on function public.doze_set_join_v2(uuid,text,text,boolean) to authenticated;
grant execute on function public.doze_my_apps_v7() to authenticated;
grant execute on function public.doze_list_apps_v6() to authenticated;
