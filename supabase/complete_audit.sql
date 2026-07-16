-- Auditoría transversal e inmutable.
-- Ejecutar después de institutional_reports.sql.

create table if not exists public.complete_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.app_users(id),
  actor_name text not null default '',
  action text not null,
  module text not null,
  entity_type text not null,
  entity_id text,
  project_id uuid references public.technical_projects(id),
  measurement_id uuid references public.project_measurements(id),
  previous_value jsonb,
  new_value jsonb,
  reason text not null default '',
  ip_address text not null default '',
  session_fingerprint text not null default '',
  created_at timestamptz not null default now()
);
alter table public.complete_audit_log enable row level security;
revoke all on public.complete_audit_log from anon,authenticated;

create or replace function public.record_complete_audit(p_token text,p_action text,p_module text,p_entity_type text,
  p_entity_id text,p_project_id uuid,p_measurement_id uuid,p_previous jsonb,p_new jsonb,p_reason text,p_ip text,p_session text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now();
  if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión no válida.'); end if;
  insert into public.complete_audit_log(actor_user_id,actor_name,action,module,entity_type,entity_id,project_id,measurement_id,
    previous_value,new_value,reason,ip_address,session_fingerprint)
  values(v_user.id,v_user.full_name,p_action,p_module,p_entity_type,p_entity_id,p_project_id,p_measurement_id,
    p_previous,p_new,coalesce(p_reason,''),coalesce(p_ip,''),coalesce(p_session,''));
  return jsonb_build_object('success',true);
end $$;

create or replace function public.list_complete_audit(p_token text,p_limit integer default 200,p_module text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_auditoria_seguridad')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar la auditoría.'); end if;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc),'[]'::jsonb) into v_items
  from (select * from public.complete_audit_log where p_module is null or module=p_module
    order by created_at desc limit greatest(1,least(coalesce(p_limit,200),1000)))a;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

grant execute on function public.record_complete_audit(text,text,text,text,text,uuid,uuid,jsonb,jsonb,text,text,text),
  public.list_complete_audit(text,integer,text) to anon,authenticated;
