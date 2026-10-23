-- Calidad, validación y trazabilidad de los datos maestros de empleados.

create table if not exists public.hr_employee_change_audit(
 id bigint generated always as identity primary key,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 changed_by uuid references public.app_users(id),
 operation text not null check(operation in('CREAR','MODIFICAR')),
 changed_fields text[] not null default '{}',
 previous_data jsonb,
 new_data jsonb not null,
 created_at timestamptz not null default now()
);
create index if not exists hr_employee_change_audit_employee_idx on public.hr_employee_change_audit(employee_id,created_at desc);
alter table public.hr_employee_change_audit enable row level security;
revoke all on public.hr_employee_change_audit from anon,authenticated;

create or replace function public.hr_validate_employee_master()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_document text:=regexp_replace(coalesce(new.document_number,''),'\D','','g');v_check_structure boolean;
begin
 if v_document='' or length(v_document)<>11 then raise exception 'La cédula debe contener exactamente 11 dígitos.';end if;
 if exists(select 1 from public.hr_employees e where e.document_number=v_document and e.id<>new.id) then raise exception 'Ya existe un empleado con esta cédula.';end if;
 new.document_number:=v_document;
 if new.birth_date is not null and (new.birth_date>current_date-interval '18 years' or new.birth_date<current_date-interval '100 years') then raise exception 'La edad del empleado debe estar entre 18 y 100 años.';end if;
 if new.hire_date is not null and new.birth_date is not null and new.hire_date<new.birth_date+interval '18 years' then raise exception 'La fecha de entrada no puede ser anterior a la mayoría de edad.';end if;
 if new.termination_date is not null and (new.hire_date is null or new.termination_date<new.hire_date) then raise exception 'La fecha de salida no puede ser anterior a la fecha de entrada.';end if;
 if nullif(trim(coalesce(new.position_name,'')),'') is null then raise exception 'El cargo es obligatorio.';end if;
 if new.organization_unit_id is null or not exists(select 1 from public.organization_units where id=new.organization_unit_id and active) then raise exception 'Seleccione una unidad organizacional válida.';end if;
 v_check_structure:=tg_op='INSERT' or new.direction_name is distinct from old.direction_name or new.department_name is distinct from old.department_name or new.division_name is distinct from old.division_name or new.section_name is distinct from old.section_name;
 if v_check_structure then
  if not exists(select 1 from public.organization_units where active and unit_type='Dirección' and lower(trim(unit_name))=lower(trim(new.direction_name))) then raise exception 'La dirección no pertenece a la estructura institucional.';end if;
  if not public.hr_unit_is_descendant(new.direction_name,new.department_name,'Departamento') then raise exception 'El departamento no pertenece a la dirección seleccionada.';end if;
  if not public.hr_unit_is_descendant(coalesce(nullif(new.department_name,''),new.direction_name),new.division_name,'División') then raise exception 'La división no pertenece a su nivel superior.';end if;
  if not public.hr_unit_is_descendant(coalesce(nullif(new.division_name,''),nullif(new.department_name,''),new.direction_name),new.section_name,'Sección') then raise exception 'La sección no pertenece a su nivel superior.';end if;
 end if;
 return new;
end $$;

create or replace function public.hr_audit_employee_master()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_old jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else null end;v_new jsonb:=to_jsonb(new);v_fields text[];
begin
 if tg_op='INSERT' then v_fields:=array(select jsonb_object_keys(v_new));
 else select coalesce(array_agg(key order by key),'{}') into v_fields from jsonb_each(v_new)n where n.value is distinct from v_old->n.key;end if;
 insert into public.hr_employee_change_audit(employee_id,changed_by,operation,changed_fields,previous_data,new_data)
 values(new.id,coalesce(new.updated_by,new.created_by),case when tg_op='INSERT' then 'CREAR' else 'MODIFICAR' end,v_fields,v_old,v_new);
 return new;
end $$;

drop trigger if exists trg_hr_validate_employee_master on public.hr_employees;
create trigger trg_hr_validate_employee_master before insert or update on public.hr_employees for each row execute function public.hr_validate_employee_master();
drop trigger if exists trg_hr_audit_employee_master on public.hr_employees;
create trigger trg_hr_audit_employee_master after insert or update on public.hr_employees for each row execute function public.hr_audit_employee_master();

create or replace function public.list_hr_data_quality(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar la calidad de datos.');end if;
 return jsonb_build_object('success',true,
  'issues',coalesce((select jsonb_agg(to_jsonb(q) order by q.severity,q.full_name,q.issue_code) from(
   select e.id employee_id,e.employee_code,e.full_name,e.direction_name,e.department_name,'CEDULA_INVALIDA' issue_code,'CRITICA' severity,'Cédula ausente o diferente de 11 dígitos' detail from public.hr_employees e where coalesce(e.document_number,'')!~'^\d{11}$'
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'EMPLEADO_DUPLICADO','CRITICA','Posible duplicidad por nombre y fecha de nacimiento' from public.hr_employees e where exists(select 1 from public.hr_employees d where d.id<>e.id and lower(regexp_replace(d.full_name,'\s+','','g'))=lower(regexp_replace(e.full_name,'\s+','','g')) and d.birth_date is not distinct from e.birth_date)
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'EDAD_INVALIDA','ALTA','Edad ausente o fuera del rango de 18 a 100 años' from public.hr_employees e where e.birth_date is null or e.birth_date>current_date-interval '18 years' or e.birth_date<current_date-interval '100 years'
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'FECHAS_INCOHERENTES','CRITICA','Fecha de salida anterior a la entrada o entrada anterior a los 18 años' from public.hr_employees e where (e.termination_date is not null and (e.hire_date is null or e.termination_date<e.hire_date)) or (e.birth_date is not null and e.hire_date<e.birth_date+interval '18 years')
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'UNIDAD_INVALIDA','ALTA','Unidad ausente, inactiva o jerarquía organizacional incoherente' from public.hr_employees e where e.organization_unit_id is null or not exists(select 1 from public.organization_units u where u.id=e.organization_unit_id and u.active) or not exists(select 1 from public.organization_units d where d.active and d.unit_type='Dirección' and lower(trim(d.unit_name))=lower(trim(e.direction_name))) or not public.hr_unit_is_descendant(e.direction_name,e.department_name,'Departamento') or not public.hr_unit_is_descendant(coalesce(nullif(e.department_name,''),e.direction_name),e.division_name,'División') or not public.hr_unit_is_descendant(coalesce(nullif(e.division_name,''),nullif(e.department_name,''),e.direction_name),e.section_name,'Sección')
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'CARGO_INVALIDO','ALTA','Cargo ausente o no incluido en el manual institucional' from public.hr_employees e where nullif(trim(coalesce(e.position_name,'')),'') is null or not exists(select 1 from public.hr_position_catalog p where p.active and lower(trim(p.position_name))=lower(trim(e.position_name)))
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'SIN_SALARIO','MEDIA','Empleado activo sin salario vigente' from public.hr_employees e where e.employment_status<>'Desvinculado' and coalesce(e.monthly_salary,0)<=0
   union all select e.id,e.employee_code,e.full_name,e.direction_name,e.department_name,'CLASIFICACION_PRESUPUESTARIA','MEDIA','Falta fondo, programa o cuenta presupuestaria activa' from public.hr_employees e where e.employment_status<>'Desvinculado' and (nullif(trim(coalesce(e.execution_fund,'')),'') is null or coalesce(e.program,0)<=0 or not exists(select 1 from public.hr_employee_payroll_assignments a where a.employee_id=e.id and a.active and nullif(trim(coalesce(a.account_code,'')),'') is not null))
  )q where v_user.role='Administrador' or exists(select 1 from public.hr_employees e where e.id=q.employee_id and public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
  'audit',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from(select x.id,x.employee_id,e.employee_code,e.full_name,x.operation,x.changed_fields,x.created_at,coalesce(u.full_name,'Sistema') changed_by_name from public.hr_employee_change_audit x join public.hr_employees e on e.id=x.employee_id left join public.app_users u on u.id=x.changed_by where v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e) order by x.created_at desc limit 100)a),'[]'::jsonb)
 );
end $$;

revoke all on function public.list_hr_data_quality(text) from public;
grant execute on function public.list_hr_data_quality(text) to anon,authenticated;
