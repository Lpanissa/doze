-- Os Doze — 09/10/2026 — Feedback útil: o dono do app marca um comentário (com print) do testador e ele ganha 1 ponto (1 por teste).
alter table public.doze_feedback add column if not exists useful_at timestamptz;

create or replace function public.doze_feedback_list_v3(p_test uuid)
 returns table(id uuid, mine boolean, from_owner boolean, body text, created_at timestamptz, photo_url text, useful boolean, i_am_owner boolean, test_has_useful boolean)
 language sql stable security definer set search_path to 'public' as
$$
  select f.id, f.author_id=auth.uid(), f.author_id=a.owner_id, f.body, f.created_at, f.photo_url, f.useful_at is not null, a.owner_id=auth.uid(),
         exists (select 1 from public.doze_feedback x where x.test_id=p_test and x.useful_at is not null)
  from public.doze_feedback f join public.doze_tests t on t.id=f.test_id join public.doze_apps a on a.id=t.app_id
  where f.test_id=p_test and (t.tester_id=auth.uid() or a.owner_id=auth.uid()) order by f.created_at $$;

create or replace function public.doze_feedback_useful(p_feedback uuid)
 returns void language plpgsql security definer set search_path to 'public' as
$$
declare f record; nm text;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select fb.id, fb.test_id, fb.author_id, fb.photo_url, fb.useful_at, t.tester_id, a.owner_id, a.name into f
    from public.doze_feedback fb join public.doze_tests t on t.id=fb.test_id join public.doze_apps a on a.id=t.app_id
    where fb.id=p_feedback for update of fb;
  if f.id is null or f.owner_id <> auth.uid() then raise exception 'Só o dono do app pode marcar.'; end if;
  if f.author_id <> f.tester_id then raise exception 'Marque só comentários do testador.'; end if;
  if f.photo_url is null then raise exception 'O feedback útil precisa ter um print.'; end if;
  if f.useful_at is not null or exists (select 1 from public.doze_feedback x where x.test_id=f.test_id and x.useful_at is not null) then
    raise exception 'Este testador já ganhou o ponto de feedback útil neste app.'; end if;
  update public.doze_feedback set useful_at = now() where id = f.id;
  update public.doze_profiles set points = points + 1 where id = f.tester_id;
  insert into public.doze_point_log(user_id,test_id,points,reason) values (f.tester_id,f.test_id,1,'feedback útil');
end $$;

revoke execute on function public.doze_feedback_list_v3(uuid) from public, anon;
revoke execute on function public.doze_feedback_useful(uuid) from public, anon;
grant execute on function public.doze_feedback_list_v3(uuid) to authenticated;
grant execute on function public.doze_feedback_useful(uuid) to authenticated;
