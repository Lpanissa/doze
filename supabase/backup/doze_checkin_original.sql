-- Cópia da função doze_checkin como estava ANTES do convite com pontos (08/10/2026).
-- Para voltar atrás: rode este arquivo no SQL do Supabase.
CREATE OR REPLACE FUNCTION public.doze_checkin(p_test uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := (now() at time zone 'America/Sao_Paulo')::date; n text := btrim(coalesce(p_note,'')); st timestamptz; oid_ uuid;
begin
  if length(n) < 8 then raise exception 'Escreva em uma frase o que você viu ou testou hoje no app (mínimo 8 letras).'; end if;
  select case when a.start_mode='livre' then t.installed_at else a.test_started_at end, a.owner_id into st, oid_ from public.doze_tests t join public.doze_apps a on a.id=t.app_id where t.id=p_test and t.tester_id=auth.uid() and t.status='instalado' and t.flagged=false;
  if not found then raise exception 'Check-in só vale para testes com app instalado.'; end if;
  if st is null then raise exception 'O dono ainda não iniciou o teste. Aguarde o início para todos.'; end if;
  if exists (select 1 from public.doze_checkins where test_id=p_test and lower(btrim(note))=lower(n)) then raise exception 'Escreva algo diferente dos check-ins anteriores.'; end if;
  insert into public.doze_checkins(test_id, day, note) values (p_test, d, left(n,200)) on conflict (test_id, day) do nothing;
  if not found then raise exception 'Você já fez o check-in de hoje.'; end if;
  if not exists (select 1 from public.doze_point_log where user_id=auth.uid() and owner_id=oid_ and test_id<>p_test and points>0) then
    update public.doze_profiles set points_pending = points_pending + 1 where id=auth.uid();
    insert into public.doze_point_log(user_id,test_id,owner_id,points,reason) values (auth.uid(),p_test,oid_,1,'check-in');
  end if;
end $function$;
