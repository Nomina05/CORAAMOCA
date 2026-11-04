-- Panel de Gestión Humana limitado a una dirección institucional.
create or replace function public.list_directional_hr_panel(p_token text,p_direction text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;required_permission text;canonical_direction text;employees jsonb;vacancies jsonb;
begin
 u:=public.hr_authenticated_user(p_token);
 canonical_direction:=case lower(trim(p_direction))
  when 'dirección general' then 'Dirección General'
  when 'direccion general' then 'Dirección General'
  when 'dirección administrativa y financiera' then 'Dirección Administrativa y Financiera'
  when 'direccion administrativa y financiera' then 'Dirección Administrativa y Financiera'
  when 'dirección de planificación y desarrollo' then 'Dirección de Planificación y Desarrollo'
  when 'direccion de planificacion y desarrollo' then 'Dirección de Planificación y Desarrollo'
  when 'dirección técnica' then 'Dirección Técnica'
  when 'direccion tecnica' then 'Dirección Técnica'
  when 'dirección comercial' then 'Dirección Comercial'
  when 'direccion comercial' then 'Dirección Comercial'
  else null end;
 required_permission:=case canonical_direction
  when 'Dirección General' then 'acceso_direccion_general'
  when 'Dirección Administrativa y Financiera' then 'acceso_administrativa_financiera'
  when 'Dirección de Planificación y Desarrollo' then 'acceso_planificacion'
  when 'Dirección Técnica' then 'acceso_direccion_tecnica'
  when 'Dirección Comercial' then 'acceso_direccion_comercial' end;
 if u.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 if canonical_direction is null then return jsonb_build_object('success',false,'error','La dirección solicitada no es válida.');end if;
 if u.role<>'Administrador' and not coalesce((u.permissions->>required_permission)::boolean,false) then
  return jsonb_build_object('success',false,'error','No posee acceso a la Gestión Humana de esta dirección.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.department_name,x.section_name,x.full_name),'[]'::jsonb) into employees from(
  select e.id,e.employee_code,e.full_name,e.position_name,e.employment_status,e.department_name,e.division_name,e.section_name,e.center_name,
   count(c.id) filter(where c.case_type='PERMISO' and c.status not in('RECHAZADO','ANULADA'))::integer permission_count,
   exists(select 1 from public.hr_employee_cases m where m.employee_id=e.id and m.status in('SOLICITADO','APROBADO') and current_date between m.start_date and m.end_date and (lower(coalesce(m.category,'')) like '%médic%' or lower(coalesce(m.category,'')) like '%medic%' or lower(coalesce(m.category,'')) like '%licencia%')) medical_leave_active,
   exists(select 1 from public.hr_employee_cases v where v.employee_id=e.id and v.case_type='VACACION' and v.status in('SOLICITADO','APROBADO') and current_date between v.start_date and v.end_date) vacation_active
  from public.hr_employees e left join public.hr_employee_cases c on c.employee_id=e.id
  where e.employment_status<>'Desvinculado' and lower(trim(e.direction_name))=lower(canonical_direction)
  group by e.id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.department_name,x.section_name,x.position_name),'[]'::jsonb) into vacancies from(
  select v.id,v.position_name,v.department_name,v.division_name,v.section_name,v.center_name,v.status,v.available_from,v.monthly_amount,coalesce(e.full_name,'Plaza de nueva creación') previous_employee_name
  from public.hr_vacancies v left join public.hr_employees e on e.id=v.source_employee_id
  where v.status in('VACANTE','CON_RECLUTAMIENTO') and lower(trim(v.direction_name))=lower(canonical_direction))x;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(u.id,'DIRECTIONAL_HR_PANEL_VIEWED','Recursos Humanos',jsonb_build_object('direction',canonical_direction,'employee_count',jsonb_array_length(employees)));
 return jsonb_build_object('success',true,'direction',canonical_direction,'employees',employees,'vacancies',vacancies);
end $$;
revoke all on function public.list_directional_hr_panel(text,text) from public,anon,authenticated;
grant execute on function public.list_directional_hr_panel(text,text) to anon,authenticated;
