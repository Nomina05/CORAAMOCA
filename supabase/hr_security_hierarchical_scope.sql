-- Fase 2: seguridad, confidencialidad y alcance jerárquico de Recursos Humanos.
-- Se ejecuta después de hr_module_foundation.sql y user_employee_link.sql.

alter table public.app_users
  add column if not exists organization_scope_unit_id uuid references public.organization_units(id);

-- Conserva la configuración existente, pero la convierte en una relación estable.
update public.app_users u
set organization_scope_unit_id=(
 select ou.id from public.organization_units ou
 where ou.active and lower(trim(ou.unit_name))=lower(trim(coalesce(nullif(u.department,''),u.area)))
 order by case ou.unit_type when 'Centro' then 1 when 'Sección' then 2 when 'División' then 3 when 'Departamento' then 4 else 5 end
 limit 1
)
where u.organization_scope_unit_id is null;

create index if not exists app_users_organization_scope_idx
on public.app_users(organization_scope_unit_id) where organization_scope_unit_id is not null;

create or replace function public.hr_unit_contains(p_ancestor uuid,p_descendant uuid)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive lineage as (
   select id,parent_id from public.organization_units where id=p_descendant and active
   union all
   select parent.id,parent.parent_id from public.organization_units parent
   join lineage child on child.parent_id=parent.id where parent.active
 )
 select p_ancestor is not null and exists(select 1 from lineage where id=p_ancestor)
$$;

create or replace function public.hr_employee_in_user_scope(p_user public.app_users,p_employee public.hr_employees)
returns boolean language sql stable security definer set search_path=public as $$
 select p_user.role='Administrador'
 or not (coalesce((p_user.permissions->>'consultar_empleados_bajo_cargo')::boolean,false)
         or coalesce((p_user.permissions->>'limitar_novedades_area')::boolean,false))
 or (p_user.organization_scope_unit_id is not null
     and public.hr_unit_contains(p_user.organization_scope_unit_id,p_employee.organization_unit_id))
$$;

create or replace function public.admin_set_user_hr_scope(p_token text,p_user_id uuid,p_unit_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users;v_unit public.organization_units;v_previous uuid;
begin
 v_admin:=public.hr_authenticated_user(p_token);
 if v_admin.id is null or v_admin.role<>'Administrador' then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 if p_unit_id is not null then select * into v_unit from public.organization_units where id=p_unit_id and active;
  if v_unit.id is null then return jsonb_build_object('success',false,'error','La unidad organizacional no existe o está inactiva.');end if;
 end if;
 select organization_scope_unit_id into v_previous from public.app_users where id=p_user_id for update;
 if not found then return jsonb_build_object('success',false,'error','Usuario no encontrado.');end if;
 if p_unit_id is null and exists(select 1 from public.app_users where id=p_user_id and (coalesce((permissions->>'consultar_empleados_bajo_cargo')::boolean,false) or coalesce((permissions->>'limitar_novedades_area')::boolean,false))) then
  return jsonb_build_object('success',false,'error','No puede retirar la unidad mientras el usuario tenga activo el alcance limitado.');end if;
 update public.app_users set organization_scope_unit_id=p_unit_id,
  department=coalesce(v_unit.unit_name,''),permissions_version=permissions_version+1,updated_at=now()
 where id=p_user_id;
 insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail)
 values(v_admin.id,p_user_id,'HR_SCOPE_UPDATED','Recursos Humanos',jsonb_build_object('before_unit_id',v_previous,'after_unit_id',p_unit_id,'unit_name',v_unit.unit_name));
 return jsonb_build_object('success',true,'organization_scope_unit_id',p_unit_id,'organization_scope_unit',v_unit.unit_name);
end $$;

create or replace function public.admin_set_user_permissions(p_token text,p_user_id uuid,p_permissions jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users;v_target public.app_users;v_previous jsonb;
begin
 v_admin:=public.hr_authenticated_user(p_token);
 if v_admin.id is null or v_admin.role<>'Administrador' then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 select * into v_target from public.app_users where id=p_user_id for update;
 if v_target.id is null then return jsonb_build_object('success',false,'error','Usuario no encontrado.');end if;
 if (coalesce((p_permissions->>'consultar_empleados_bajo_cargo')::boolean,false) or coalesce((p_permissions->>'limitar_novedades_area')::boolean,false)) and v_target.organization_scope_unit_id is null then
  return jsonb_build_object('success',false,'error','Seleccione primero la unidad organizacional bajo su cargo.');end if;
 v_previous:=v_target.permissions;
 update public.app_users set permissions=coalesce(p_permissions,'{}'::jsonb),permissions_version=permissions_version+1,updated_at=now() where id=p_user_id;
 insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail)
 values(v_admin.id,p_user_id,'PERMISSIONS_UPDATED','Usuarios',jsonb_build_object('before',v_previous,'after',p_permissions,'scope_unit_id',v_target.organization_scope_unit_id));
 return jsonb_build_object('success',true);
end $$;

create or replace function public.admin_list_users(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users;v_users jsonb;
begin
 v_admin:=public.hr_authenticated_user(p_token);
 if v_admin.id is null or v_admin.role<>'Administrador' then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',u.id,'employee_id',e.id,'employee_code',e.employee_code,'username',u.username,'full_name',u.full_name,
  'area',u.area,'department',u.department,'role',u.role,'active',u.active,'permissions',u.permissions,
  'permissions_version',u.permissions_version,'created_at',u.created_at,'last_login_at',u.last_login_at,
  'locked_until',u.locked_until,'suspended_at',u.suspended_at,'suspension_reason',u.suspension_reason,
  'must_change_password',u.must_change_password,'employee_status',e.employment_status,'organization_unit',o.unit_name,
  'organization_scope_unit_id',u.organization_scope_unit_id,'organization_scope_unit',scope.unit_name
 ) order by u.created_at),'[]'::jsonb) into v_users
 from public.app_users u left join public.hr_employees e on e.app_user_id=u.id
 left join public.organization_units o on o.id=e.organization_unit_id
 left join public.organization_units scope on scope.id=u.organization_scope_unit_id;
 return jsonb_build_object('success',true,'users',v_users);
end $$;

-- Las cuentas vinculadas a empleados nacen con la unidad real del empleado como alcance.
create or replace function public.hr_sync_user_scope_from_employee()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.app_user_id is not null and (old.app_user_id is distinct from new.app_user_id or old.organization_unit_id is distinct from new.organization_unit_id) then
  update public.app_users set organization_scope_unit_id=new.organization_unit_id,
   department=coalesce((select unit_name from public.organization_units where id=new.organization_unit_id),department),updated_at=now()
  where id=new.app_user_id and organization_scope_unit_id is null;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_sync_user_scope_from_employee on public.hr_employees;
create trigger trg_hr_sync_user_scope_from_employee after insert or update of app_user_id,organization_unit_id
on public.hr_employees for each row execute function public.hr_sync_user_scope_from_employee();

update public.app_users u set organization_scope_unit_id=e.organization_unit_id,
 department=coalesce(o.unit_name,u.department)
from public.hr_employees e left join public.organization_units o on o.id=e.organization_unit_id
where e.app_user_id=u.id and u.organization_scope_unit_id is null;

-- Lista mínima de empleados: respeta alcance y no expone cédula ni salario.
create or replace function public.list_hr_employees(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_items jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar Recursos Humanos.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_items from(
  select e.id,e.employee_code,e.full_name,e.position_name,e.employment_status,e.hire_date,
   e.organization_unit_id,o.unit_name,e.app_user_id,e.created_at
  from public.hr_employees e join public.organization_units o on o.id=e.organization_unit_id
  where public.hr_employee_in_user_scope(v_user,e)
 )x;
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'HR_EMPLOYEE_LIST_VIEWED','Recursos Humanos',jsonb_build_object('result_count',jsonb_array_length(v_items),'scope_unit_id',v_user.organization_scope_unit_id));
 return jsonb_build_object('success',true,'employees',v_items);
end $$;

create or replace function public.list_hr_employee_registry(p_token text,p_year integer default null,p_month integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employees jsonb;v_history jsonb;v_personal boolean;v_salary boolean;v_deductions boolean;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar empleados.');end if;
 v_personal:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_datos_personales')::boolean,false);
 v_salary:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_salarios')::boolean,false);
 v_deductions:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_descuentos')::boolean,false);
 select coalesce(jsonb_agg(
  (to_jsonb(e)-'document_number'-'birth_date'-'phone'-'cell_phone'-'landline_phone'-'driver_license'-'blood_type'-'home_address'-'bank_account'-'academic_level'-'monthly_salary')
  ||case when v_personal then jsonb_build_object('document_number',e.document_number,'birth_date',e.birth_date,'phone',e.phone,'cell_phone',e.cell_phone,'landline_phone',e.landline_phone,'driver_license',e.driver_license,'blood_type',e.blood_type,'home_address',e.home_address,'bank_account',e.bank_account,'academic_level',e.academic_level) else '{}'::jsonb end
  ||case when v_salary then jsonb_build_object('monthly_salary',e.monthly_salary,
   'benefits',coalesce((select jsonb_agg(jsonb_build_object('type',b.benefit_type,'amount',b.default_amount,'active',b.active)) from public.hr_employee_benefits b where b.employee_id=e.id),'[]'::jsonb),
   'payroll_assignments',coalesce((select jsonb_agg(to_jsonb(a)) from public.hr_employee_payroll_assignments a where a.employee_id=e.id),'[]'::jsonb))
   else jsonb_build_object('benefits','[]'::jsonb,'payroll_assignments','[]'::jsonb) end
  ||jsonb_build_object('deductions',case when v_deductions then coalesce((select jsonb_agg(to_jsonb(d)) from public.hr_employee_deductions d where d.employee_id=e.id),'[]'::jsonb) else '[]'::jsonb end)
  order by e.full_name),'[]'::jsonb) into v_employees
 from public.hr_employees e where public.hr_employee_in_user_scope(v_user,e);
 select coalesce(jsonb_agg(case when v_salary then to_jsonb(h)||jsonb_build_object('document_number',case when v_personal then e.document_number else null end,'full_name',e.full_name) else (to_jsonb(h)-'monthly_salary')||jsonb_build_object('full_name',e.full_name) end order by h.effective_year desc,h.effective_month desc,e.full_name),'[]'::jsonb)
 into v_history from public.hr_employee_history h join public.hr_employees e on e.id=h.employee_id
 where (p_year is null or h.effective_year=p_year) and (p_month is null or h.effective_month=p_month) and public.hr_employee_in_user_scope(v_user,e);
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'HR_REGISTRY_VIEWED','Recursos Humanos',jsonb_build_object('result_count',jsonb_array_length(v_employees),'personal_data',v_personal,'salary',v_salary,'deductions',v_deductions));
 return jsonb_build_object('success',true,'employees',v_employees,'history',v_history);
end $$;

-- Expediente protegido en el origen: cada bloque sensible exige su permiso.
create or replace function public.get_hr_employee_dossier(p_token text,p_employee_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_employee_json jsonb;v_salary boolean;v_personal boolean;v_deductions boolean;v_discipline boolean;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 select * into v_employee from public.hr_employees where id=p_employee_id;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para consultar expedientes.');end if;
 if not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','El colaborador no pertenece a la unidad organizacional autorizada.');end if;
 v_personal:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_datos_personales')::boolean,false);
 v_salary:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_salarios')::boolean,false);
 v_deductions:=v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_descuentos')::boolean,false);
 v_discipline:=v_user.role='Administrador' or coalesce((v_user.permissions->>'consultar_expedientes_disciplinarios')::boolean,false);
 v_employee_json:=to_jsonb(v_employee);
 if not v_personal then v_employee_json:=v_employee_json-'document_number'-'birth_date'-'phone'-'cell_phone'-'landline_phone'-'driver_license'-'blood_type'-'home_address'-'bank_account'-'academic_level'-'photo_data';end if;
 if not v_salary then v_employee_json:=v_employee_json-'monthly_salary';end if;
 insert into public.security_audit_log(actor_user_id,target_user_id,action,module,detail)
 values(v_user.id,v_employee.app_user_id,'HR_DOSSIER_VIEWED','Recursos Humanos',jsonb_build_object('employee_id',p_employee_id,'personal_data',v_personal,'salary',v_salary,'deductions',v_deductions,'discipline',v_discipline));
 return jsonb_build_object('success',true,'employee',v_employee_json,
  'history',case when v_salary then coalesce((select jsonb_agg(to_jsonb(h) order by h.effective_year desc,h.effective_month desc) from public.hr_employee_history h where h.employee_id=p_employee_id),'[]'::jsonb) else coalesce((select jsonb_agg(to_jsonb(h)-'monthly_salary' order by h.effective_year desc,h.effective_month desc) from public.hr_employee_history h where h.employee_id=p_employee_id),'[]'::jsonb) end,
  'actions',coalesce((select jsonb_agg(to_jsonb(a) order by a.effective_date desc) from public.hr_personnel_actions a where a.employee_id=p_employee_id),'[]'::jsonb),
  'cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.request_date desc) from public.hr_employee_cases c where c.employee_id=p_employee_id and (c.case_type<>'AMONESTACION' or v_discipline)),'[]'::jsonb),
  'payroll',case when v_salary then coalesce((select jsonb_agg(to_jsonb(x) order by x.payroll_year desc,x.payroll_month desc) from(select l.*,b.payroll_type,b.payroll_year,b.payroll_month,b.status batch_status,b.created_at from public.hr_payroll_batch_lines l join public.hr_payroll_batches b on b.id=l.batch_id where l.employee_id=p_employee_id)x),'[]'::jsonb) else '[]'::jsonb end,
  'assignments',case when v_salary then coalesce((select jsonb_agg(to_jsonb(a)) from public.hr_employee_payroll_assignments a where a.employee_id=p_employee_id),'[]'::jsonb) else '[]'::jsonb end,
  'benefits',case when v_salary then coalesce((select jsonb_agg(to_jsonb(b)) from public.hr_employee_benefits b where b.employee_id=p_employee_id),'[]'::jsonb) else '[]'::jsonb end,
  'dependents',case when v_deductions then coalesce((select jsonb_agg(to_jsonb(d)) from public.hr_employee_dependents d where d.employee_id=p_employee_id),'[]'::jsonb) else '[]'::jsonb end,
  'deductions',case when v_deductions then coalesce((select jsonb_agg(to_jsonb(d)) from public.hr_employee_deductions d where d.employee_id=p_employee_id),'[]'::jsonb) else '[]'::jsonb end,
  'documents',coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from public.hr_employee_files f where f.employee_id=p_employee_id),'[]'::jsonb),
  'audit',case when v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_auditoria_seguridad')::boolean,false) then coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.security_audit_log a where a.module='Recursos Humanos' and a.detail->>'employee_id'=p_employee_id::text),'[]'::jsonb) else '[]'::jsonb end);
end $$;

revoke all on function public.hr_unit_contains(uuid,uuid),public.hr_employee_in_user_scope(public.app_users,public.hr_employees),public.admin_set_user_hr_scope(text,uuid,uuid) from public;
grant execute on function public.admin_set_user_hr_scope(text,uuid,uuid),public.admin_set_user_permissions(text,uuid,jsonb),public.admin_list_users(text),public.list_hr_employees(text),public.list_hr_employee_registry(text,integer,integer),public.get_hr_employee_dossier(text,uuid) to anon,authenticated;
