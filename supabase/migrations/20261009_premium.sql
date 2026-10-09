-- Os Doze — 09/10/2026 — Premium (R$ 4,90 / 30 dias via Pix): publica apps sem gastar pontos e sem fila.
create table if not exists public.doze_premium (
  user_id uuid primary key references public.doze_profiles(id) on delete cascade,
  premium_until timestamptz not null
);
create table if not exists public.doze_payments (
  mp_payment_id text primary key,
  user_id uuid not null references public.doze_profiles(id) on delete cascade,
  amount numeric(10,2) not null,
  paid_at timestamptz not null default now()
);
create index if not exists doze_payments_paid_idx on public.doze_payments(paid_at desc);
alter table public.doze_premium enable row level security;   -- sem policies: só funções
alter table public.doze_payments enable row level security;

create or replace function public.doze_is_premium(p_uid uuid)
 returns boolean language sql stable security definer set search_path to 'public' as
$$ select coalesce((select premium_until > now() from public.doze_premium where user_id = p_uid), false) $$;

create or replace function public.doze_my_premium()
 returns timestamptz language sql stable security definer set search_path to 'public' as
$$ select case when premium_until > now() then premium_until end from public.doze_premium where user_id = auth.uid() $$;

-- chamada só pelo webhook (service_role): soma 30 dias, idempotente pelo id do pagamento
create or replace function public.doze_grant_premium(p_uid uuid, p_payment text, p_amount numeric)
 returns timestamptz language plpgsql security definer set search_path to 'public' as
$$
declare ins int; u timestamptz;
begin
  insert into public.doze_payments(mp_payment_id,user_id,amount) values (p_payment,p_uid,p_amount) on conflict do nothing;
  get diagnostics ins = row_count;
  if ins = 0 then select premium_until into u from public.doze_premium where user_id=p_uid; return u; end if;
  insert into public.doze_premium(user_id,premium_until) values (p_uid, now() + interval '30 days')
  on conflict (user_id) do update set premium_until = greatest(public.doze_premium.premium_until, now()) + interval '30 days'
  returning premium_until into u;
  return u;
end $$;

-- painel só do dono
create or replace function public.doze_admin_premium()
 returns jsonb language plpgsql security definer set search_path to 'public' as
$$
begin
  if coalesce(auth.jwt()->>'email','') <> 'lpanissa@gmail.com' then raise exception 'sem acesso'; end if;
  return jsonb_build_object(
    'month_total', coalesce((select sum(amount) from public.doze_payments where paid_at >= date_trunc('month', now())),0),
    'active', coalesce((select jsonb_agg(jsonb_build_object('name',p.name,'until',x.premium_until) order by x.premium_until desc)
                        from public.doze_premium x join public.doze_profiles p on p.id=x.user_id where x.premium_until>now()),'[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('name',p.name,'amount',y.amount,'at',y.paid_at))
                        from (select * from public.doze_payments order by paid_at desc limit 20) y join public.doze_profiles p on p.id=y.user_id),'[]'::jsonb));
end $$;

-- cadastro: Premium publica na hora, sem gastar pontos
create or replace function public.doze_create_app_v4(p_name text, p_description text, p_package text, p_opt_in text, p_icon text, p_shots text[])
 returns doze_apps language plpgsql security definer set search_path to 'public' as
$function$
declare pts int; total int; r doze_apps; pre text := 'https://fyxksvydxwvygjebanno.supabase.co/storage/v1/object/public/doze-shots/' || auth.uid()::text || '/';
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  if length(btrim(coalesce(p_description,''))) < 10 then raise exception 'A descrição é obrigatória (mínimo 10 letras).'; end if;
  if coalesce(p_icon,'') <> '' and left(p_icon, length(pre)) <> pre then raise exception 'logo inválido'; end if;
  select points into pts from public.doze_profiles where id=auth.uid() for update;
  if pts is null then raise exception 'perfil não encontrado'; end if;
  select count(*) into total from public.doze_apps where owner_id=auth.uid();
  r := public.doze_create_app_v2(p_name,p_description,p_package,p_opt_in,p_icon,p_shots);
  if total = 0 or public.doze_is_premium(auth.uid()) then
    return r;                                  -- primeiro app grátis, ou Premium: publicado na hora
  elsif pts >= 12 then
    update public.doze_profiles set points = points - 12 where id=auth.uid();
    insert into public.doze_point_log(user_id,points,reason) values (auth.uid(),-12,'publicou: '||left(coalesce(p_name,''),60));
    return r;
  else
    update public.doze_apps set status='fila' where id=r.id returning * into r;
    return r;
  end if;
end $function$;

-- publicar da fila: Premium não gasta pontos
create or replace function public.doze_publish_app(p_app uuid)
 returns void language plpgsql security definer set search_path to 'public' as
$function$
declare pts int; nm text; n int; prem boolean := public.doze_is_premium(auth.uid());
begin
  if auth.uid() is null then raise exception 'login necessário'; end if;
  select name into nm from public.doze_apps where id=p_app and owner_id=auth.uid() and status='fila' for update;
  if nm is null then raise exception 'App não encontrado na fila de espera.'; end if;
  select points into pts from public.doze_profiles where id=auth.uid() for update;
  if not prem and coalesce(pts,0) < 12 then raise exception 'Para publicar você precisa de 12 pontos (você tem %).', coalesce(pts,0); end if;
  select count(*) into n from public.doze_apps where owner_id=auth.uid() and status='ativo';
  if not prem and n >= 5 then raise exception 'Limite de 5 apps ativos por pessoa. Conclua ou exclua algum.'; end if;
  update public.doze_apps set status='ativo' where id=p_app;
  if not prem then
    update public.doze_profiles set points = points - 12 where id=auth.uid();
    insert into public.doze_point_log(user_id,points,reason) values (auth.uid(),-12,'publicou: '||left(nm,60));
  end if;
end $function$;

revoke execute on function public.doze_is_premium(uuid) from public, anon, authenticated;
revoke execute on function public.doze_grant_premium(uuid,text,numeric) from public, anon, authenticated;
revoke execute on function public.doze_my_premium() from public, anon;
revoke execute on function public.doze_admin_premium() from public, anon;
grant execute on function public.doze_my_premium() to authenticated;
grant execute on function public.doze_admin_premium() to authenticated;
revoke execute on function public.doze_create_app_v4(text,text,text,text,text,text[]) from public, anon;
revoke execute on function public.doze_publish_app(uuid) from public, anon;
grant execute on function public.doze_create_app_v4(text,text,text,text,text,text[]) to authenticated;
grant execute on function public.doze_publish_app(uuid) to authenticated;
