-- Gobierno integral de usuarios: perfiles, accesos temporales, sesiones, solicitudes,
-- incompatibilidades, auditoría y reportes. Ejecutar después de user_employee_link.sql.

alter table public.app_users
  add column if not exists account_status text not null default 'ACTIVO',
  add column if not exists permission_profile_code text,
  add column if not exists permission_expires_at timestamptz,
  add column if not exists last_permission_review_at timestamptz,
  add column if not exists last_permission_review_by uuid references public.app_users(id);

alter table public.app_user_sessions
  add column if not exists ip_address text not null default '',
  add column if not exists user_agent text not null default '',
  add column if not exists device_name text not null default '',
  add column if not exists last_seen_at timestamptz not null default now(),
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_by uuid references public.app_users(id),
  add column if not exists revoke_reason text not null default '';

create table if not exists public.security_permission_profiles (
  id uuid primary key default gen_random_uuid(),
  profile_code text not null unique,
  profile_name text not null,
  role_name text not null,
  direction_name text not null,
  description text not null default '',
  permissions jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.security_temporary_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  direction_name text not null,
  organization_unit_id uuid references public.organization_units(id),
  permissions jsonb not null default '{}'::jsonb,
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  justification text not null,
  status text not null default 'ACTIVO' check(status in ('PENDIENTE','ACTIVO','VENCIDO','REVOCADO','RECHAZADO')),
  approved_by uuid references public.app_users(id),
  revoked_by uuid references public.app_users(id),
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  check(valid_until>valid_from)
);

create table if not exists public.security_permission_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity,
  requester_user_id uuid not null references public.app_users(id),
  target_user_id uuid not null references public.app_users(id),
  requested_permissions jsonb not null default '{}'::jsonb,
  justification text not null,
  valid_until timestamptz,
  status text not null default 'PENDIENTE' check(status in ('PENDIENTE','APROBADA','RECHAZADA','APLICADA','CANCELADA')),
  reviewed_by uuid references public.app_users(id),
  reviewed_at timestamptz,
  review_note text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.security_permission_conflicts (
  id uuid primary key default gen_random_uuid(),
  conflict_code text not null unique,
  permission_a text not null,
  permission_b text not null,
  severity text not null default 'ALTA',
  description text not null,
  active boolean not null default true
);

insert into public.security_permission_conflicts(conflict_code,permission_a,permission_b,severity,description) values
 ('REGISTRA_APRUEBA_CUBICACION','registrar_cubicaciones','pagar_cubicaciones','CRITICA','La misma cuenta no debe registrar y pagar cubicaciones.'),
 ('REGISTRA_PAGA_ACTIVO','registrar_activos','pagar_activos','CRITICA','La misma cuenta no debe registrar y pagar activos.'),
 ('PROCESA_REABRE_NOMINA','procesar_nomina','reabrir_nomina','ALTA','La reapertura debe quedar en una función de control independiente.'),
 ('CREA_APRUEBA_PERSONAL','crear_recursos_humanos','aprobar_acciones_personal','ALTA','La creación y aprobación de acciones de personal deben separarse.')
on conflict(conflict_code) do update set permission_a=excluded.permission_a,permission_b=excluded.permission_b,severity=excluded.severity,description=excluded.description,active=true;

insert into public.security_permission_profiles(profile_code,profile_name,role_name,direction_name,description,permissions) values
 ('CONSULTA_GENERAL','Consulta institucional','Consulta','Dirección General','Lectura de paneles y reportes institucionales','{"acceso_direccion_general":true,"ver_resumen":true,"ver_reportes":true}'::jsonb),
 ('DIRECTOR_RRHH','Director de Recursos Humanos','Director','Dirección de Recursos Humanos','Aprobación, indicadores y reportes de Recursos Humanos','{"acceso_recursos_humanos":true,"ver_recursos_humanos":true,"ver_indicadores_rrhh":true,"aprobar_acciones_personal":true,"aprobar_vacaciones":true,"aprobar_permisos_laborales":true,"ver_reportes_oficiales_rrhh":true}'::jsonb),
 ('REGISTRO_NOMINA','Registro y Control de Nómina','Analista','Dirección de Recursos Humanos','Procesamiento de nómina sin reapertura administrativa','{"acceso_recursos_humanos":true,"ver_nomina_rrhh":true,"ver_presupuesto_nomina_rrhh":true,"procesar_nomina":true,"ver_salarios":true,"ver_descuentos":true}'::jsonb),
 ('ENCARGADO_UNIDAD','Encargado de unidad','Supervisor','Dirección de Recursos Humanos','Consulta exclusiva del personal bajo su cargo','{"acceso_recursos_humanos":true,"ver_recursos_humanos":true,"consultar_empleados_bajo_cargo":true,"limitar_novedades_area":true,"ver_permisos_laborales":true,"ver_vacaciones":true,"ver_amonestaciones":true}'::jsonb),
 ('TECNICO_OBRAS','Técnico de obras','Analista','Dirección Técnica','Registro y seguimiento técnico sin pago','{"acceso_direccion_tecnica":true,"ver_proyectos_tecnicos":true,"registrar_cubicaciones":true,"ver_cubicaciones":true,"ver_expediente_proyecto":true}'::jsonb),
 ('FINANZAS_PAGO','Finanzas y pagos','Analista','Dirección Administrativa y Financiera','Libramientos y pagos sin registro técnico','{"acceso_administrativa_financiera":true,"ver_gestion_presupuestaria":true,"ver_cubicaciones":true,"libramiento_cubicaciones":true,"pagar_cubicaciones":true,"ver_activos":true,"pagar_activos":true}'::jsonb),
 ('COMERCIAL_OPERATIVO','Operador comercial','Usuario','Dirección Comercial','Operaciones comerciales sin administración de usuarios','{"acceso_direccion_comercial":true,"ver_gestion_comercial":true,"gestionar_comercial":true,"ver_clientes_comercial":true,"ver_facturacion_comercial":true,"ver_cobros_comercial":true,"ver_atencion_cliente_comercial":true}'::jsonb)
on conflict(profile_code) do update set profile_name=excluded.profile_name,role_name=excluded.role_name,direction_name=excluded.direction_name,description=excluded.description,permissions=excluded.permissions,active=true,updated_at=now();

alter table public.security_permission_profiles enable row level security;
alter table public.security_temporary_access enable row level security;
alter table public.security_permission_requests enable row level security;
alter table public.security_permission_conflicts enable row level security;
revoke all on public.security_permission_profiles,public.security_temporary_access,public.security_permission_requests,public.security_permission_conflicts from anon,authenticated;

create or replace function public.security_permission_conflict_report(p_permissions jsonb)
returns jsonb language sql stable set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code',conflict_code,'severity',severity,'description',description)),'[]'::jsonb)
  from public.security_permission_conflicts
  where active and coalesce((p_permissions->>permission_a)::boolean,false) and coalesce((p_permissions->>permission_b)::boolean,false)
$$;

create or replace function public.register_session_context(p_token text,p_ip text,p_user_agent text,p_device text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
begin
 update public.app_user_sessions set ip_address=coalesce(p_ip,''),user_agent=left(coalesce(p_user_agent,''),500),device_name=left(coalesce(p_device,''),120),last_seen_at=now()
 where token_hash=encode(digest(p_token,'sha256'),'hex') and expires_at>now() and revoked_at is null;
 return found;
end $$;

create or replace function public.admin_user_governance_snapshot(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users%rowtype;v_result jsonb;
begin
 select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
 where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and s.revoked_at is null and u.active and u.role='Administrador';
 if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 update public.security_temporary_access set status='VENCIDO' where status='ACTIVO' and valid_until<=now();
 select jsonb_build_object(
  'success',true,
  'profiles',(select coalesce(jsonb_agg(to_jsonb(p) order by p.direction_name,p.profile_name),'[]'::jsonb) from public.security_permission_profiles p where p.active),
  'temporaryAccess',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'userId',t.user_id,'userName',u.full_name,'direction',t.direction_name,'unit',o.unit_name,'permissions',t.permissions,'validFrom',t.valid_from,'validUntil',t.valid_until,'status',t.status,'justification',t.justification) order by t.created_at desc),'[]'::jsonb) from public.security_temporary_access t join public.app_users u on u.id=t.user_id left join public.organization_units o on o.id=t.organization_unit_id),
  'requests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'number',r.request_number,'targetUser',u.full_name,'requestedPermissions',r.requested_permissions,'justification',r.justification,'validUntil',r.valid_until,'status',r.status,'createdAt',r.created_at) order by r.created_at desc),'[]'::jsonb) from public.security_permission_requests r join public.app_users u on u.id=r.target_user_id),
  'sessions',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'userId',s.user_id,'userName',u.full_name,'username',u.username,'ip',s.ip_address,'device',s.device_name,'userAgent',s.user_agent,'createdAt',s.created_at,'lastSeenAt',s.last_seen_at,'expiresAt',s.expires_at,'revokedAt',s.revoked_at) order by s.created_at desc),'[]'::jsonb) from public.app_user_sessions s join public.app_users u on u.id=s.user_id where s.expires_at>now()-interval '30 days'),
  'audit',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select a.id,a.action,a.module,a.detail,a.created_at,actor.full_name actor_name,target.full_name target_name from public.security_audit_log a left join public.app_users actor on actor.id=a.actor_user_id left join public.app_users target on target.id=a.target_user_id order by a.created_at desc limit 250)x),
  'alerts',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
    select u.id user_id,u.full_name,'SIN_EMPLEADO' alert_type,'Usuario sin empleado activo vinculado' detail from public.app_users u left join public.hr_employees e on e.app_user_id=u.id where u.active and e.id is null
    union all select u.id,u.full_name,'SIN_ACCESO','Más de 60 días sin iniciar sesión' from public.app_users u where u.active and (u.last_login_at is null or u.last_login_at<now()-interval '60 days')
    union all select u.id,u.full_name,'PERMISOS_INCOMPATIBLES',c.value->>'description' from public.app_users u cross join lateral jsonb_array_elements(public.security_permission_conflict_report(u.permissions)) c
  )x),
  'summary',jsonb_build_object(
    'activeUsers',(select count(*) from public.app_users where active and suspended_at is null),
    'suspendedUsers',(select count(*) from public.app_users where not active or suspended_at is not null),
    'temporaryAccess',(select count(*) from public.security_temporary_access where status='ACTIVO' and valid_until>now()),
    'pendingRequests',(select count(*) from public.security_permission_requests where status='PENDIENTE'),
    'activeSessions',(select count(*) from public.app_user_sessions where expires_at>now() and revoked_at is null),
    'unlinkedUsers',(select count(*) from public.app_users u left join public.hr_employees e on e.app_user_id=u.id where u.active and e.id is null)
  )
 ) into v_result;
 return v_result;
end $$;

create or replace function public.admin_manage_user_governance(p_token text,p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users%rowtype;v_user public.app_users%rowtype;v_profile public.security_permission_profiles%rowtype;v_id uuid;v_before jsonb;v_after jsonb;
begin
 select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
 where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and s.revoked_at is null and u.active and u.role='Administrador';
 if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 v_id=nullif(p_payload->>'userId','')::uuid;
 if p_action='APPLY_PROFILE' then
   select * into v_profile from public.security_permission_profiles where profile_code=p_payload->>'profileCode' and active;
   select * into v_user from public.app_users where id=v_id;v_before=to_jsonb(v_user);
   if v_profile.id is null or v_user.id is null then return jsonb_build_object('success',false,'error','Perfil o usuario no encontrado.');end if;
   if jsonb_array_length(public.security_permission_conflict_report(v_profile.permissions))>0 then return jsonb_build_object('success',false,'error','El perfil contiene permisos incompatibles.');end if;
   update public.app_users set role=v_profile.role_name,area=v_profile.direction_name,permissions=v_profile.permissions,permission_profile_code=v_profile.profile_code,permissions_version=permissions_version+1,last_permission_review_at=now(),last_permission_review_by=v_admin.id,updated_at=now() where id=v_id;
   v_after=(select to_jsonb(u) from public.app_users u where u.id=v_id);
 elsif p_action='COPY_PERMISSIONS' then
   select permissions into v_after from public.app_users where id=nullif(p_payload->>'sourceUserId','')::uuid;
   if v_after is null then return jsonb_build_object('success',false,'error','Usuario origen no encontrado.');end if;
   if jsonb_array_length(public.security_permission_conflict_report(v_after))>0 then return jsonb_build_object('success',false,'error','Los permisos copiados contienen incompatibilidades.');end if;
   select permissions into v_before from public.app_users where id=v_id;
   update public.app_users set permissions=v_after,permission_profile_code=null,permissions_version=permissions_version+1,last_permission_review_at=now(),last_permission_review_by=v_admin.id,updated_at=now() where id=v_id;
 elsif p_action='REVOKE_SESSION' then
   update public.app_user_sessions set revoked_at=now(),revoked_by=v_admin.id,revoke_reason=coalesce(nullif(p_payload->>'reason',''),'Revocada por el administrador') where id=nullif(p_payload->>'sessionId','')::uuid;
 elsif p_action='REVOKE_ALL_SESSIONS' then
   update public.app_user_sessions set revoked_at=now(),revoked_by=v_admin.id,revoke_reason=coalesce(nullif(p_payload->>'reason',''),'Cierre administrativo') where user_id=v_id and revoked_at is null;
 elsif p_action='CREATE_TEMPORARY_ACCESS' then
   insert into public.security_temporary_access(user_id,direction_name,organization_unit_id,permissions,valid_from,valid_until,justification,status,approved_by,created_by)
   values(v_id,p_payload->>'direction',nullif(p_payload->>'organizationUnitId','')::uuid,coalesce(p_payload->'permissions','{}'::jsonb),coalesce(nullif(p_payload->>'validFrom','')::timestamptz,now()),(p_payload->>'validUntil')::timestamptz,p_payload->>'justification','ACTIVO',v_admin.id,v_admin.id);
 elsif p_action='REVOKE_TEMPORARY_ACCESS' then
   update public.security_temporary_access set status='REVOCADO',revoked_by=v_admin.id where id=nullif(p_payload->>'accessId','')::uuid;
 elsif p_action='REVIEW_PERMISSIONS' then
   update public.app_users set last_permission_review_at=now(),last_permission_review_by=v_admin.id,permission_expires_at=nullif(p_payload->>'permissionExpiresAt','')::timestamptz where id=v_id;
 elsif p_action='SET_ACCOUNT_STATUS' then
   update public.app_users set account_status=p_payload->>'status',active=(p_payload->>'status')='ACTIVO',suspended_at=case when (p_payload->>'status')='ACTIVO' then null else now() end,suspended_by=case when (p_payload->>'status')='ACTIVO' then null else v_admin.id end,suspension_reason=coalesce(p_payload->>'reason',''),updated_at=now() where id=v_id;
   if (p_payload->>'status')<>'ACTIVO' then update public.app_user_sessions set revoked_at=now(),revoked_by=v_admin.id,revoke_reason='Cambio de estado de cuenta' where user_id=v_id and revoked_at is null;end if;
 else return jsonb_build_object('success',false,'error','Acción no reconocida.');
 end if;
 insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail) values(v_admin.id,v_id,p_action,'Usuarios',jsonb_build_object('before',v_before,'after',v_after,'payload',p_payload-'permissions'));
 return jsonb_build_object('success',true);
end $$;

create or replace function public.security_sync_employee_user_status()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.app_user_id is not null and lower(coalesce(new.employment_status,'')) not in ('activo','fijo','carrera administrativa','temporal','interino','estatuto simplificado') then
   update public.app_users set active=false,account_status='INACTIVO',suspended_at=now(),suspension_reason='Desvinculación automática del empleado',updated_at=now() where id=new.app_user_id;
   update public.app_user_sessions set revoked_at=now(),revoke_reason='Empleado desvinculado' where user_id=new.app_user_id and revoked_at is null;
 end if;
 return new;
end $$;
drop trigger if exists trg_security_sync_employee_user_status on public.hr_employees;
create trigger trg_security_sync_employee_user_status after insert or update of employment_status,app_user_id on public.hr_employees for each row execute function public.security_sync_employee_user_status();

grant execute on function public.admin_user_governance_snapshot(text),public.admin_manage_user_governance(text,text,jsonb),public.security_permission_conflict_report(jsonb),public.register_session_context(text,text,text,text) to anon,authenticated;
