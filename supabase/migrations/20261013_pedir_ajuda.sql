-- "Pedir ajuda": o dono notifica um testador para ajudar a testar o app dele (1x por dia por testador/app)
create table if not exists public.doze_help_asks(
  app_id uuid not null references public.doze_apps(id) on delete cascade,
  tester_id uuid not null,
  day date not null default current_date,
  primary key(app_id,tester_id,day)
);
alter table public.doze_help_asks enable row level security;
revoke all on public.doze_help_asks from anon, authenticated;

create or replace function public.doze_ask_help(p_test uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
declare t doze_tests; a doze_apps;
begin
  select * into t from doze_tests where id=p_test; select * into a from doze_apps where id=t.app_id;
  if a.owner_id is distinct from auth.uid() then raise exception 'sem permissão'; end if;
  if t.status not in ('adicionado','instalado') then raise exception 'testador não aceito'; end if;
  if exists(select 1 from doze_help_asks where app_id=a.id and tester_id=t.tester_id and day=current_date) then raise exception 'Você já pediu ajuda a este testador hoje.'; end if;
  insert into doze_help_asks(app_id,tester_id) values (a.id,t.tester_id);
  perform doze_push_send(array[t.tester_id],'Pedido de ajuda','O dono de '||a.name||' pediu sua ajuda para testar o app.','/#tests');
end $$;
revoke all on function public.doze_ask_help(uuid) from public, anon;
grant execute on function public.doze_ask_help(uuid) to authenticated;

-- notificação dentro do app para o testador (mesmo formato dos outros avisos)
create or replace function public.doze_notifs() returns table(app_id uuid, app_name text, kind text, n integer)
language sql stable security definer set search_path to 'public' as $$
  select a.id, a.name, 'pedido', count(*)::int from doze_tests t join doze_apps a on a.id=t.app_id where a.owner_id=auth.uid() and t.status='pendente' group by a.id, a.name
  union all
  select a.id, a.name, case when a.owner_id=auth.uid() then 'comentario_dono' else 'comentario_teste' end, count(*)::int
  from doze_feedback f join doze_tests t on t.id=f.test_id join doze_apps a on a.id=t.app_id
  where (a.owner_id=auth.uid() or t.tester_id=auth.uid()) and f.author_id<>auth.uid()
    and f.created_at > coalesce((select s.seen_at from doze_feedback_seen s where s.user_id=auth.uid() and s.test_id=t.id),'-infinity')
  group by a.id, a.name, a.owner_id
  union all
  select a.id, a.name, 'aceito', count(*)::int from doze_tests t join doze_apps a on a.id=t.app_id where t.tester_id=auth.uid() and t.status='adicionado' group by a.id, a.name
  union all
  select a.id, a.name, 'lembrete', 1 from doze_nudges n join doze_apps a on a.id=n.app_id join doze_tests t on t.app_id=a.id and t.tester_id=n.tester_id
  where n.tester_id=auth.uid() and n.day=current_date and not exists(select 1 from doze_checkins c where c.test_id=t.id and c.day=current_date)
  union all
  select a.id, a.name, 'ajuda', 1 from doze_help_asks h join doze_apps a on a.id=h.app_id
  where h.tester_id=auth.uid() and h.day=current_date
$$;
revoke all on function public.doze_notifs() from public, anon;
grant execute on function public.doze_notifs() to authenticated;
