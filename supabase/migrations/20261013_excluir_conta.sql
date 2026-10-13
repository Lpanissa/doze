-- Excluir conta dentro do app (exigência do Google Play). Cada usuário só apaga a própria conta.
-- Mantém o login Google (compartilhado com outros apps do mesmo Supabase); apaga todos os dados do Os Doze.
create or replace function public.doze_delete_account() returns void
language plpgsql security definer set search_path to 'public' as $$
declare u uuid:=auth.uid();
begin
  if u is null then raise exception 'não autenticado'; end if;
  delete from doze_apps where owner_id=u;
  delete from doze_tests where tester_id=u;
  delete from doze_feedback where author_id=u;
  delete from doze_feedback_seen where user_id=u;
  delete from doze_help_asks where tester_id=u;
  delete from doze_nudges where tester_id=u;
  delete from doze_blocks where user_id=u;
  delete from doze_point_log where user_id=u or owner_id=u;
  delete from doze_push_subs where user_id=u;
  delete from doze_reports where reporter_id=u or target_id=u;
  delete from doze_profiles where id=u;
end $$;
revoke all on function public.doze_delete_account() from public, anon;
grant execute on function public.doze_delete_account() to authenticated;
