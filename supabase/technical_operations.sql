-- Operación técnica, fallos y observabilidad.
-- Ejecutar después de institutional_notifications.sql.

create table if not exists public.technical_error_log (
  id bigint generated always as identity primary key,
  user_id uuid references public.app_users(id),
  environment text not null default '',
  source text not null,
  error_code text not null default '',
  message text not null,
  technical_detail text not null default '',
  request_path text not null default '',
  deployment_id text not null default '',
  created_at timestamptz not null default now()
);

alter table public.technical_error_log enable row level security;
revoke all on public.technical_error_log from anon,authenticated;

create or replace function public.record_technical_error(p_token text,p_environment text,p_source text,p_error_code text,
  p_message text,p_detail text,p_path text,p_deployment_id text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user_id uuid;
begin
  select u.id into v_user_id from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now();
  insert into public.technical_error_log(user_id,environment,source,error_code,message,technical_detail,request_path,deployment_id)
  values(v_user_id,coalesce(p_environment,''),left(coalesce(p_source,'Sistema'),120),left(coalesce(p_error_code,''),80),
    left(coalesce(p_message,'Error no especificado'),800),left(coalesce(p_detail,''),4000),
    left(coalesce(p_path,''),500),left(coalesce(p_deployment_id,''),120));
  return jsonb_build_object('success',true);
end $$;

create or replace function public.list_technical_errors(p_token text,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or v_user.role<>'Administrador'
    then return jsonb_build_object('success',false,'error','Acceso reservado para administradores.'); end if;
  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc),'[]'::jsonb) into v_items
  from (select * from public.technical_error_log order by created_at desc limit greatest(1,least(coalesce(p_limit,100),500)))e;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

grant execute on function public.record_technical_error(text,text,text,text,text,text,text,text),
  public.list_technical_errors(text,integer) to anon,authenticated;
