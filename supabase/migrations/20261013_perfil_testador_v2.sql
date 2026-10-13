-- Mini perfil do testador (visto só pelo dono do app): apps publicados, testados, concluídos, check-ins etc.
create or replace function public.doze_tester_profile_v2(p_test uuid)
returns table(name text, avatar_url text, points integer, tests_done integer, tests_active integer, tests_total integer, checkins integer, checkins_total integer, apps_published integer, apps_total integer, left_count integer, member_since timestamptz, status text)
language sql stable security definer set search_path to 'public' as $$
  select coalesce(p.name,''), p.avatar_url, coalesce(p.points,0)::int,
    (select count(*)::int from public.doze_tests x where x.tester_id=t.tester_id and x.status='concluido'),
    (select count(*)::int from public.doze_tests x where x.tester_id=t.tester_id and x.status in ('adicionado','instalado')),
    (select count(*)::int from public.doze_tests x where x.tester_id=t.tester_id and x.status<>'saiu'),
    (select count(*)::int from public.doze_checkins c where c.test_id=t.id),
    (select count(*)::int from public.doze_checkins c join public.doze_tests x on x.id=c.test_id where x.tester_id=t.tester_id),
    (select count(*)::int from public.doze_apps o where o.owner_id=t.tester_id and o.status<>'fila'),
    (select count(*)::int from public.doze_apps o where o.owner_id=t.tester_id),
    (select count(*)::int from public.doze_tests x where x.tester_id=t.tester_id and x.status='saiu'),
    p.created_at, t.status
  from public.doze_tests t join public.doze_apps a on a.id=t.app_id left join public.doze_profiles p on p.id=t.tester_id
  where t.id=p_test and a.owner_id=auth.uid()
$$;
revoke all on function public.doze_tester_profile_v2(uuid) from public, anon;
grant execute on function public.doze_tester_profile_v2(uuid) to authenticated;
