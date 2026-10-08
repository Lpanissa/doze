-- Os Doze — 08/10/2026
-- 1) Fila de espera: cadastrar app sempre pode; publicar (gastar 12 pontos) só com 12 pontos.
-- 2) Convide amigos e ganhe pontos: 3 pontos para quem convida, quando o amigo faz o 1º check-in.

-- ===== 1) Fila de espera =====
alter table public.doze_apps drop constraint if exists doze_apps_status_check;
alter table public.doze_apps add constraint doze_apps_status_check
  check (status = any (array['ativo'::text, 'encerrado'::text, 'fila'::text]));

create or replace function public.doze_create_app_v4(p_name text, p_description text, p_package text, p_opt_in text, p_icon text, p_shots text[])
 returns doze_apps
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare pts int; total int; r doze_apps; pre text := 'https://fyxksvydxwvygjebanno.supabase.co/storage/v1/object/public/doze-shots/' || auth.uid()::text || '/';
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  if length(btrim(coalesce(p_description,''))) < 10 then raise exception 'A descrição é obrigatória (mínimo 10 letras).'; end if;
  if coalesce(p_icon,'') <> '' and left(p_icon, length(pre)) <> pre then raise exception 'logo inválido'; end if;
  select points into pts from public.doze_profiles where id=auth.uid() for update;
  if pts is null then raise exception 'perfil não encontrado'; end if;
  select count(*) into total from public.doze_apps where owner_id=auth.uid();
  -- (REMOVIDO) antes o cadastro era barrado a partir do 2º app:
  -- if total > 0 and pts < 12 then raise exception 'Para publicar outro app você precisa de 12 pontos (você tem %). ...', pts; end if;
  r := public.doze_create_app_v2(p_name,p_description,p_package,p_opt_in,p_icon,p_shots);
  if total = 0 then
    return r;                                  -- primeiro app: grátis e publicado
  elsif pts >= 12 then
    update public.doze_profiles set points = points - 12 where id=auth.uid();
    insert into public.doze_point_log(user_id,points,reason) values (auth.uid(),-12,'publicou: '||left(coalesce(p_name,''),60));
    return r;                                  -- tem 12 pontos: publica na hora
  else
    update public.doze_apps set status='fila' where id=r.id returning * into r;
    return r;                                  -- sem pontos: fica na fila de espera
  end if;
end $function$;

create or replace function public.doze_publish_app(p_app uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare pts int; nm text; n int;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select name into nm from public.doze_apps where id=p_app and owner_id=auth.uid() and status='fila' for update;
  if nm is null then raise exception 'App não encontrado na fila de espera.'; end if;
  select points into pts from public.doze_profiles where id=auth.uid() for update;
  if coalesce(pts,0) < 12 then raise exception 'Para publicar você precisa de 12 pontos (você tem %).', coalesce(pts,0); end if;
  select count(*) into n from public.doze_apps where owner_id=auth.uid() and status='ativo';
  if n >= 5 then raise exception 'Limite de 5 apps ativos por pessoa. Conclua ou exclua algum.'; end if;
  update public.doze_apps set status='ativo' where id=p_app;
  update public.doze_profiles set points = points - 12 where id=auth.uid();
  insert into public.doze_point_log(user_id,points,reason) values (auth.uid(),-12,'publicou: '||left(nm,60));
end $function$;

-- ===== 2) Convites =====
alter table public.doze_profiles add column if not exists ref_code text;
create unique index if not exists doze_profiles_ref_code_key on public.doze_profiles(ref_code);

create table if not exists public.doze_referrals (
  invited_id  uuid primary key references public.doze_profiles(id) on delete cascade,
  referrer_id uuid not null references public.doze_profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  rewarded_at timestamptz,
  check (invited_id <> referrer_id)
);
create index if not exists doze_referrals_referrer_idx on public.doze_referrals(referrer_id);
alter table public.doze_referrals enable row level security;   -- sem policies: só as funções acessam

create or replace function public.doze_my_referral()
 returns table(code text, invited int, rewarded int)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare c text;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select ref_code into c from public.doze_profiles where id=auth.uid();
  if c is null then
    loop
      c := substr(replace(gen_random_uuid()::text,'-',''),1,8);
      begin
        update public.doze_profiles set ref_code=c where id=auth.uid() and ref_code is null;
        exit;
      exception when unique_violation then null;
      end;
    end loop;
    select ref_code into c from public.doze_profiles where id=auth.uid();
  end if;
  return query select c,
    (select count(*)::int from public.doze_referrals where referrer_id=auth.uid()),
    (select count(*)::int from public.doze_referrals where referrer_id=auth.uid() and rewarded_at is not null);
end $function$;

create or replace function public.doze_apply_referral(p_code text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare rid uuid; cr timestamptz;
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select created_at into cr from public.doze_profiles where id=auth.uid();
  if cr is null or cr < now() - interval '2 days' then return false; end if;   -- só vale para quem acabou de entrar
  if exists (select 1 from public.doze_referrals where invited_id=auth.uid()) then return false; end if;
  select id into rid from public.doze_profiles where ref_code = lower(btrim(coalesce(p_code,'')));
  if rid is null or rid = auth.uid() then return false; end if;
  insert into public.doze_referrals(invited_id, referrer_id) values (auth.uid(), rid) on conflict do nothing;
  return true;
end $function$;

-- doze_checkin: igual ao original + 3 pontos para quem convidou, no 1º check-in do amigo
create or replace function public.doze_checkin(p_test uuid, p_note text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d date := (now() at time zone 'America/Sao_Paulo')::date; n text := btrim(coalesce(p_note,'')); st timestamptz; oid_ uuid; ref_ uuid; nm_ text;
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
  update public.doze_referrals set rewarded_at = now() where invited_id = auth.uid() and rewarded_at is null returning referrer_id into ref_;
  if ref_ is not null then
    select name into nm_ from public.doze_profiles where id = auth.uid();
    update public.doze_profiles set points = points + 3 where id = ref_;
    insert into public.doze_point_log(user_id,points,reason) values (ref_,3,'convite: '||left(coalesce(nm_,'amigo'),40));
  end if;
end $function$;

-- só quem está logado chama as funções novas
revoke execute on function public.doze_create_app_v4(text,text,text,text,text,text[]) from public, anon;
revoke execute on function public.doze_publish_app(uuid) from public, anon;
revoke execute on function public.doze_my_referral() from public, anon;
revoke execute on function public.doze_apply_referral(text) from public, anon;
grant execute on function public.doze_create_app_v4(text,text,text,text,text,text[]) to authenticated;
grant execute on function public.doze_publish_app(uuid) to authenticated;
grant execute on function public.doze_my_referral() to authenticated;
grant execute on function public.doze_apply_referral(text) to authenticated;
