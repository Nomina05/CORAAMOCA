-- Relación obligatoria entre las nuevas cuentas del sistema y empleados activos.
create unique index if not exists hr_employees_app_user_unique
  on public.hr_employees(app_user_id) where app_user_id is not null;

create or replace function public.admin_create_employee_user(
  p_token text,p_employee_id uuid,p_username text,p_temp_password text,p_role text,p_permissions jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  v_admin public.app_users%rowtype;
  v_employee public.hr_employees%rowtype;
  v_unit public.organization_units%rowtype;
  v_username text:=lower(trim(p_username));
  v_user_id uuid;
  v_area text;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now()
    and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;

  select * into v_employee from public.hr_employees where id=p_employee_id for update;
  if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.'); end if;
  if v_employee.employment_status in ('Desvinculado','Suspendido') then
    return jsonb_build_object('success',false,'error','Solo se pueden crear usuarios para empleados activos.');
  end if;
  if v_employee.app_user_id is not null then
    return jsonb_build_object('success',false,'error','Este empleado ya posee un usuario del sistema.');
  end if;
  if v_username !~ '^[a-z0-9._-]{3,32}$' then return jsonb_build_object('success',false,'error','El usuario debe tener entre 3 y 32 caracteres y usar letras, números, punto, guion o guion bajo.'); end if;
  if length(p_temp_password)<8 then return jsonb_build_object('success',false,'error','La contraseña temporal debe tener al menos 8 caracteres.'); end if;
  if p_role not in ('Administrador','Director','Supervisor','Analista','Consulta','Usuario') then return jsonb_build_object('success',false,'error','Rol inválido.'); end if;
  if exists(select 1 from public.app_users where username=v_username) then return jsonb_build_object('success',false,'error','Ese nombre de usuario ya existe.'); end if;

  select * into v_unit from public.organization_units where id=v_employee.organization_unit_id;
  v_area:=coalesce(nullif(trim(v_employee.direction_name),''),nullif(trim(v_unit.unit_name),''),'Institucional');
  insert into public.app_users(username,password_hash,full_name,area,department,role,permissions,must_change_password,active)
  values(v_username,crypt(p_temp_password,gen_salt('bf',10)),v_employee.full_name,v_area,coalesce(v_unit.unit_name,''),p_role,coalesce(p_permissions,'{}'::jsonb),true,true)
  returning id into v_user_id;
  update public.hr_employees set app_user_id=v_user_id,updated_at=now() where id=v_employee.id;
  insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail)
  values(v_admin.id,v_user_id,'USER_CREATED_FROM_EMPLOYEE','Usuarios',jsonb_build_object('employee_id',v_employee.id,'employee_code',v_employee.employee_code,'organization_unit_id',v_employee.organization_unit_id));
  return jsonb_build_object('success',true,'user',jsonb_build_object(
    'id',v_user_id,'employee_id',v_employee.id,'employee_code',v_employee.employee_code,'username',v_username,
    'full_name',v_employee.full_name,'area',v_area,'department',coalesce(v_unit.unit_name,''),'role',p_role,
    'permissions',coalesce(p_permissions,'{}'::jsonb),'active',true,'must_change_password',true));
end $$;

create or replace function public.admin_list_users(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users%rowtype;v_users jsonb;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,'employee_id',e.id,'employee_code',e.employee_code,'username',u.username,'full_name',u.full_name,
    'area',u.area,'department',u.department,'role',u.role,'active',u.active,'permissions',u.permissions,
    'permissions_version',u.permissions_version,'created_at',u.created_at,'last_login_at',u.last_login_at,
    'locked_until',u.locked_until,'suspended_at',u.suspended_at,'suspension_reason',u.suspension_reason,
    'must_change_password',u.must_change_password,'employee_status',e.employment_status,'organization_unit',o.unit_name
  ) order by u.created_at),'[]'::jsonb) into v_users
  from public.app_users u left join public.hr_employees e on e.app_user_id=u.id left join public.organization_units o on o.id=e.organization_unit_id;
  return jsonb_build_object('success',true,'users',v_users);
end $$;

create or replace function public.admin_link_user_employee(p_token text,p_user_id uuid,p_employee_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  v_admin public.app_users%rowtype;
  v_target public.app_users%rowtype;
  v_employee public.hr_employees%rowtype;
  v_unit public.organization_units%rowtype;
  v_area text;
begin
  select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now()
    and u.active=true and u.suspended_at is null and u.role='Administrador';
  if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select * into v_target from public.app_users where id=p_user_id for update;
  if v_target.id is null then return jsonb_build_object('success',false,'error','Usuario no encontrado.'); end if;
  select * into v_employee from public.hr_employees where id=p_employee_id for update;
  if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.'); end if;
  if v_employee.employment_status in ('Desvinculado','Suspendido') then return jsonb_build_object('success',false,'error','Solo se pueden vincular empleados activos.'); end if;
  if v_employee.app_user_id is not null and v_employee.app_user_id<>p_user_id then return jsonb_build_object('success',false,'error','Este empleado ya está vinculado a otro usuario.'); end if;
  select * into v_unit from public.organization_units where id=v_employee.organization_unit_id;
  v_area:=coalesce(nullif(trim(v_employee.direction_name),''),nullif(trim(v_unit.unit_name),''),'Institucional');
  update public.hr_employees set app_user_id=null,updated_at=now() where app_user_id=p_user_id and id<>p_employee_id;
  update public.hr_employees set app_user_id=p_user_id,updated_at=now() where id=p_employee_id;
  update public.app_users set full_name=v_employee.full_name,area=v_area,department=coalesce(v_unit.unit_name,''),updated_at=now() where id=p_user_id;
  insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail)
  values(v_admin.id,p_user_id,'USER_EMPLOYEE_LINKED','Usuarios',jsonb_build_object('employee_id',v_employee.id,'employee_code',v_employee.employee_code,'organization_unit_id',v_employee.organization_unit_id));
  return jsonb_build_object('success',true,'user',jsonb_build_object(
    'id',p_user_id,'employee_id',v_employee.id,'employee_code',v_employee.employee_code,'full_name',v_employee.full_name,
    'area',v_area,'department',coalesce(v_unit.unit_name,''),'employee_status',v_employee.employment_status,'organization_unit',coalesce(v_unit.unit_name,'')));
end $$;

grant execute on function public.admin_create_employee_user(text,uuid,text,text,text,jsonb),public.admin_link_user_employee(text,uuid,uuid),public.admin_list_users(text) to anon,authenticated;
