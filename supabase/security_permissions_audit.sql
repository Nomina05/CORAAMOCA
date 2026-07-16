-- Seguridad institucional: permisos granulares, bloqueo, suspensión y auditoría.
-- Ejecutar después de username_auth.sql y cubicaciones_workflow.sql.

alter table public.app_users
  add column if not exists department text not null default '',
  add column if not exists failed_login_attempts integer not null default 0,
  add column if not exists locked_until timestamptz,
  add column if not exists suspended_at timestamptz,
  add column if not exists suspended_by uuid references public.app_users(id),
  add column if not exists suspension_reason text not null default '',
  add column if not exists permissions_version bigint not null default 1;

create table if not exists public.security_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.app_users(id),
  target_user_id uuid references public.app_users(id),
  action text not null,
  module text not null default 'Seguridad',
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.security_audit_log enable row level security;
revoke all on public.security_audit_log from anon, authenticated;

create or replace function public.has_app_permission(p_user public.app_users, p_permission text)
returns boolean language sql immutable as $$
  select p_user.role = 'Administrador'
    or coalesce((p_user.permissions ->> p_permission)::boolean, false)
$$;

create or replace function public.login_app_user(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype; v_token text;
begin
  select * into v_user from public.app_users where username=lower(trim(p_username));
  if v_user.id is null then
    insert into public.security_audit_log(action,detail) values('LOGIN_FAILED',jsonb_build_object('username',lower(trim(p_username)),'reason','UNKNOWN_USER'));
    return jsonb_build_object('success',false,'code','INVALID_CREDENTIALS','error','Usuario o contraseña incorrectos.');
  end if;
  if not v_user.active or v_user.suspended_at is not null then
    insert into public.security_audit_log(actor_user_id,target_user_id,action,detail) values(v_user.id,v_user.id,'LOGIN_BLOCKED',jsonb_build_object('reason','SUSPENDED'));
    return jsonb_build_object('success',false,'code','SUSPENDED','error','La cuenta está suspendida. Contacte al administrador.');
  end if;
  if v_user.locked_until is not null and v_user.locked_until>now() then
    insert into public.security_audit_log(actor_user_id,target_user_id,action,detail) values(v_user.id,v_user.id,'LOGIN_BLOCKED',jsonb_build_object('reason','TEMPORARY_LOCK','locked_until',v_user.locked_until));
    return jsonb_build_object('success',false,'code','LOCKED','error','Cuenta bloqueada temporalmente. Intente nuevamente más tarde.','locked_until',v_user.locked_until);
  end if;
  if v_user.password_hash<>crypt(p_password,v_user.password_hash) then
    update public.app_users set failed_login_attempts=failed_login_attempts+1,
      locked_until=case when failed_login_attempts+1>=5 then now()+interval '15 minutes' else null end,updated_at=now() where id=v_user.id;
    insert into public.security_audit_log(actor_user_id,target_user_id,action,detail) values(v_user.id,v_user.id,'LOGIN_FAILED',jsonb_build_object('reason','INVALID_PASSWORD','attempt',v_user.failed_login_attempts+1));
    return jsonb_build_object('success',false,'code',case when v_user.failed_login_attempts+1>=5 then 'LOCKED' else 'INVALID_CREDENTIALS' end,
      'error',case when v_user.failed_login_attempts+1>=5 then 'Cuenta bloqueada durante 15 minutos por varios intentos fallidos.' else 'Usuario o contraseña incorrectos.' end);
  end if;
  delete from public.app_user_sessions where expires_at<now();
  v_token:=encode(gen_random_bytes(32),'hex');
  insert into public.app_user_sessions(user_id,token_hash,expires_at) values(v_user.id,encode(digest(v_token,'sha256'),'hex'),now()+interval '12 hours');
  update public.app_users set last_login_at=now(),failed_login_attempts=0,locked_until=null,updated_at=now() where id=v_user.id;
  insert into public.security_audit_log(actor_user_id,target_user_id,action) values(v_user.id,v_user.id,'LOGIN_SUCCESS');
  return jsonb_build_object('success',true,'token',v_token,'user',jsonb_build_object(
    'id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'department',v_user.department,
    'role',v_user.role,'permissions',v_user.permissions,'permissions_version',v_user.permissions_version,'must_change_password',v_user.must_change_password));
end $$;

create or replace function public.get_app_session(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now()
    and u.active=true and u.suspended_at is null and (u.locked_until is null or u.locked_until<=now());
  if v_user.id is null then return null; end if;
  return jsonb_build_object('user',jsonb_build_object(
    'id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'department',v_user.department,
    'role',v_user.role,'permissions',v_user.permissions,'permissions_version',v_user.permissions_version,'must_change_password',v_user.must_change_password));
end $$;

create or replace function public.admin_update_user(p_token text,p_user_id uuid,p_role text,p_area text,p_active boolean,p_department text default '',p_suspension_reason text default '')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_admin public.app_users%rowtype;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  if p_user_id=v_admin.id and (p_role<>'Administrador' or p_active=false) then return jsonb_build_object('success',false,'error','No puedes retirar tu propio acceso administrativo.'); end if;
  update public.app_users set role=p_role,area=coalesce(nullif(trim(p_area),''),area),department=coalesce(trim(p_department),''),
    active=p_active,suspended_at=case when p_active then null else now() end,suspended_by=case when p_active then null else v_admin.id end,
    suspension_reason=case when p_active then '' else coalesce(nullif(trim(p_suspension_reason),''),'Suspendido por el administrador') end,
    failed_login_attempts=case when p_active then 0 else failed_login_attempts end,locked_until=case when p_active then null else locked_until end,
    permissions_version=permissions_version+1,updated_at=now() where id=p_user_id;
  if not found then return jsonb_build_object('success',false,'error','Usuario no encontrado.'); end if;
  if p_active=false then delete from public.app_user_sessions where user_id=p_user_id; end if;
  insert into public.security_audit_log(actor_user_id,target_user_id,action,detail) values(v_admin.id,p_user_id,
    case when p_active then 'USER_UPDATED' else 'USER_SUSPENDED' end,jsonb_build_object('role',p_role,'area',p_area,'department',p_department,'active',p_active,'reason',p_suspension_reason));
  return jsonb_build_object('success',true);
end $$;

create or replace function public.admin_set_user_permissions(p_token text,p_user_id uuid,p_permissions jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_admin public.app_users%rowtype; v_previous jsonb;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select permissions into v_previous from public.app_users where id=p_user_id;
  update public.app_users set permissions=coalesce(p_permissions,'{}'::jsonb),permissions_version=permissions_version+1,updated_at=now() where id=p_user_id;
  if not found then return jsonb_build_object('success',false,'error','Usuario no encontrado.'); end if;
  insert into public.security_audit_log(actor_user_id,target_user_id,action,detail) values(v_admin.id,p_user_id,'PERMISSIONS_UPDATED',jsonb_build_object('before',v_previous,'after',p_permissions));
  return jsonb_build_object('success',true);
end $$;

create or replace function public.admin_list_security_audit(p_token text,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_admin public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (
    select a.id,a.action,a.module,a.detail,a.created_at,actor.full_name actor_name,target.full_name target_name
    from public.security_audit_log a left join public.app_users actor on actor.id=a.actor_user_id left join public.app_users target on target.id=a.target_user_id
    order by a.created_at desc limit greatest(1,least(coalesce(p_limit,100),500))) x;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

create or replace function public.admin_list_users(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_admin public.app_users%rowtype; v_users jsonb;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'username',username,'full_name',full_name,'area',area,'department',department,'role',role,'active',active,
    'permissions',permissions,'permissions_version',permissions_version,'created_at',created_at,'last_login_at',last_login_at,
    'locked_until',locked_until,'suspended_at',suspended_at,'suspension_reason',suspension_reason,
    'must_change_password',must_change_password) order by created_at),'[]'::jsonb)
  into v_users from public.app_users;
  return jsonb_build_object('success',true,'users',v_users);
end $$;

grant execute on function public.login_app_user(text,text),public.get_app_session(text),
  public.admin_update_user(text,uuid,text,text,boolean,text,text),public.admin_set_user_permissions(text,uuid,jsonb),
  public.admin_list_security_audit(text,integer),public.admin_list_users(text) to anon,authenticated;
