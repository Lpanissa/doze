-- Limite de uso por usuário (anti-abuso). Tabela interna + função doze_throttle chamada dentro das RPCs.
-- Aplicado em produção (migration "doze_limite_de_uso"): doze_throttle + limites em
--   doze_join_test (30/min), doze_feedback_add_v2 (20/min), doze_create_app_v4 (10/h), doze_push_subscribe (20/h).
create table if not exists public.doze_rate(user_id uuid not null, k text not null, win timestamptz not null default now(), n int not null default 0, primary key(user_id,k));
alter table public.doze_rate enable row level security;
revoke all on public.doze_rate from anon, authenticated;
create or replace function public.doze_throttle(p_k text, p_max int, p_secs int) returns void
language plpgsql security definer set search_path to 'public' as $$
declare c int;
begin
  if auth.uid() is null then return; end if;
  insert into doze_rate(user_id,k,win,n) values (auth.uid(),p_k,now(),1)
  on conflict (user_id,k) do update set
    win = case when doze_rate.win < now() - make_interval(secs => p_secs) then now() else doze_rate.win end,
    n   = case when doze_rate.win < now() - make_interval(secs => p_secs) then 1 else doze_rate.n + 1 end
  returning n into c;
  if c > p_max then raise exception 'Muitas tentativas seguidas. Espere um pouco e tente de novo.'; end if;
end $$;
revoke all on function public.doze_throttle(text,int,int) from public, anon, authenticated;
-- (as 4 funções acima receberam a linha: perform public.doze_throttle('<chave>', <max>, <segundos>);)
