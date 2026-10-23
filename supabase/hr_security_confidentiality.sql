-- Seguridad y confidencialidad granular para Recursos Humanos.
-- La autorización se aplica en las funciones SECURITY DEFINER y no depende de ocultar botones.

update public.app_users
set permissions=coalesce(permissions,'{}'::jsonb)||jsonb_build_object(
 'ver_datos_personales',case when role='Administrador' then true else coalesce((permissions->>'ver_datos_personales')::boolean,false) end,
 'ver_salarios',case when role='Administrador' then true else coalesce((permissions->>'ver_salarios')::boolean,false) end,
 'ver_descuentos',case when role='Administrador' then true else coalesce((permissions->>'ver_descuentos')::boolean,false) end,
 'modificar_empleados',case when role='Administrador' then true else coalesce((permissions->>'modificar_empleados')::boolean,false) end,
 'aprobar_acciones_personal',case when role='Administrador' then true else coalesce((permissions->>'aprobar_acciones_personal')::boolean,false) end,
 'procesar_nomina',case when role='Administrador' then true else coalesce((permissions->>'procesar_nomina')::boolean,false) end,
 'cerrar_nomina',case when role='Administrador' then true else coalesce((permissions->>'cerrar_nomina')::boolean,false) end,
 'consultar_expedientes_disciplinarios',case when role='Administrador' then true else coalesce((permissions->>'consultar_expedientes_disciplinarios')::boolean,false) end,
 'exportar_informacion_rrhh',case when role='Administrador' then true else coalesce((permissions->>'exportar_informacion_rrhh')::boolean,false) end,
 'consultar_empleados_bajo_cargo',case when role='Administrador' then false else coalesce((permissions->>'consultar_empleados_bajo_cargo')::boolean,false) end
),permissions_version=permissions_version+1,updated_at=now();

create or replace function public.hr_employee_in_user_scope(p_user public.app_users,p_employee public.hr_employees)
returns boolean language sql stable set search_path=public as $$
 select not (coalesce((p_user.permissions->>'consultar_empleados_bajo_cargo')::boolean,false)
             or coalesce((p_user.permissions->>'limitar_novedades_area')::boolean,false))
 or case when trim(coalesce(p_user.department,''))<>'' then
   lower(trim(p_user.department)) in(lower(trim(coalesce(p_employee.direction_name,''))),lower(trim(coalesce(p_employee.department_name,''))),lower(trim(coalesce(p_employee.division_name,''))),lower(trim(coalesce(p_employee.section_name,''))),lower(trim(coalesce(p_employee.center_name,''))))
 else lower(trim(coalesce(p_user.area,''))) in(lower(trim(coalesce(p_employee.direction_name,''))),lower(trim(coalesce(p_employee.department_name,''))),lower(trim(coalesce(p_employee.division_name,''))),lower(trim(coalesce(p_employee.section_name,''))),lower(trim(coalesce(p_employee.center_name,'')))) end
$$;

create or replace function public.list_hr_employee_registry(p_token text,p_year integer default null,p_month integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employees jsonb;v_history jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar empleados.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_employees from(
  select e.*,coalesce((select jsonb_agg(jsonb_build_object('type',b.benefit_type,'amount',b.default_amount,'active',b.active) order by b.benefit_type) from public.hr_employee_benefits b where b.employee_id=e.id),'[]'::jsonb) benefits,
   coalesce((select jsonb_agg(jsonb_build_object('type',d.deduction_type,'description',d.description,'amount',d.monthly_amount,'active',d.active) order by d.deduction_type) from public.hr_employee_deductions d where d.employee_id=e.id),'[]'::jsonb) deductions,
   coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'payroll_type',a.payroll_type,'account_code',a.account_code,'position_name',a.position_name,'execution_fund',a.execution_fund,'program',a.program,'subproduct',a.subproduct,'activity',a.activity,'gross_amount',a.gross_amount,'start_date',a.start_date,'end_date',a.end_date,'active',a.active) order by a.payroll_type) from public.hr_employee_payroll_assignments a where a.employee_id=e.id),'[]'::jsonb) payroll_assignments
  from public.hr_employees e where v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e)
 )x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.effective_year desc,x.effective_month desc,x.full_name),'[]'::jsonb) into v_history from(
  select h.*,e.document_number,e.full_name from public.hr_employee_history h join public.hr_employees e on e.id=h.employee_id
  where (p_year is null or h.effective_year=p_year) and (p_month is null or h.effective_month=p_month) and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x;
 return jsonb_build_object('success',true,'employees',v_employees,'history',v_history);
end $$;

grant execute on function public.list_hr_employee_registry(text,integer,integer) to anon,authenticated;
