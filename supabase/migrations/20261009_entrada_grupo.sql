-- Os Doze — 09/10/2026 — Como os testadores entram: lista de e-mails (padrão) ou link de grupo do Google.
alter table public.doze_apps add column if not exists join_method text not null default 'lista' check (join_method in ('lista','grupo'));
alter table public.doze_apps add column if not exists group_url text;

create or replace function public.doze_set_join(p_app uuid, p_method text, p_group_url text)
 returns void language plpgsql security definer set search_path to 'public' as
$$
declare g text := nullif(btrim(coalesce(p_group_url,'')),'');
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  if p_method not in ('lista','grupo') then raise exception 'modo inválido'; end if;
  if p_method = 'grupo' then
    if g is null or g !~ '^https://groups\.google\.com/' then raise exception 'Cole o link de convite do grupo do Google (começa com https://groups.google.com/).'; end if;
  else g := null; end if;
  update public.doze_apps set join_method = p_method, group_url = g where id = p_app and owner_id = auth.uid();
  if not found then raise exception 'app não encontrado'; end if;
end $$;

create or replace function public.doze_my_apps_v6()
 returns table(id uuid, name text, description text, package_name text, opt_in_url text, icon_url text, status text, testers_needed integer, active_testers bigint, pending_testers bigint, created_at timestamptz, liberado boolean, test_started_at timestamptz, accepted bigint, start_mode text, screenshots text[], category text, join_method text, group_url text)
 language sql stable security definer set search_path to 'public' as
$$ select m.*, a.join_method, a.group_url from public.doze_my_apps_v5() m join public.doze_apps a on a.id=m.id $$;

-- o testador só recebe o link do grupo depois que o dono aceitá-lo
create or replace function public.doze_my_tests_v4()
 returns table(test_id uuid, app_id uuid, app_name text, icon_url text, status text, opt_in_url text, joined_at timestamptz, installed_at timestamptz, days_done integer, checkins integer, last_checkin date, checked_today boolean, flagged boolean, started_at timestamptz, group_url text)
 language sql stable security definer set search_path to 'public' as
$$ select m.*, case when m.status in ('adicionado','instalado','concluido') and a.join_method='grupo' then a.group_url end
   from public.doze_my_tests_v3() m join public.doze_apps a on a.id=m.app_id $$;

revoke execute on function public.doze_set_join(uuid,text,text) from public, anon;
revoke execute on function public.doze_my_apps_v6() from public, anon;
revoke execute on function public.doze_my_tests_v4() from public, anon;
grant execute on function public.doze_set_join(uuid,text,text) to authenticated;
grant execute on function public.doze_my_apps_v6() to authenticated;
grant execute on function public.doze_my_tests_v4() to authenticated;
