-- Permisos laborales, vacaciones y amonestaciones vinculados al expediente del empleado.
update public.app_users set permissions=permissions||jsonb_build_object(
 'ver_permisos_laborales',coalesce((permissions->>'ver_permisos_laborales')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false),
 'registrar_permisos_laborales',coalesce((permissions->>'registrar_permisos_laborales')::boolean,(permissions->>'crear_recursos_humanos')::boolean,false),
 'aprobar_permisos_laborales',coalesce((permissions->>'aprobar_permisos_laborales')::boolean,(permissions->>'aprobar_recursos_humanos')::boolean,false),
 'ver_amonestaciones',coalesce((permissions->>'ver_amonestaciones')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false),
 'registrar_amonestaciones',coalesce((permissions->>'registrar_amonestaciones')::boolean,(permissions->>'crear_recursos_humanos')::boolean,false),
 'notificar_amonestaciones',coalesce((permissions->>'notificar_amonestaciones')::boolean,(permissions->>'aprobar_recursos_humanos')::boolean,false),
 'ver_vacaciones',coalesce((permissions->>'ver_vacaciones')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false),
 'registrar_vacaciones',coalesce((permissions->>'registrar_vacaciones')::boolean,(permissions->>'crear_recursos_humanos')::boolean,false),
 'aprobar_vacaciones',coalesce((permissions->>'aprobar_vacaciones')::boolean,(permissions->>'aprobar_recursos_humanos')::boolean,false)
) where role<>'Administrador';

-- Toda acción operativa implica la vista mínima de su propio módulo, nunca la vista general de Gestión Humana.
update public.app_users set permissions=permissions||jsonb_build_object(
 'ver_permisos_laborales',coalesce((permissions->>'ver_permisos_laborales')::boolean,false) or coalesce((permissions->>'registrar_permisos_laborales')::boolean,false) or coalesce((permissions->>'aprobar_permisos_laborales')::boolean,false),
 'ver_amonestaciones',coalesce((permissions->>'ver_amonestaciones')::boolean,false) or coalesce((permissions->>'registrar_amonestaciones')::boolean,false) or coalesce((permissions->>'notificar_amonestaciones')::boolean,false),
 'ver_vacaciones',coalesce((permissions->>'ver_vacaciones')::boolean,false) or coalesce((permissions->>'registrar_vacaciones')::boolean,false) or coalesce((permissions->>'aprobar_vacaciones')::boolean,false)
) where role<>'Administrador';

create table if not exists public.hr_employee_cases(
 id uuid primary key default gen_random_uuid(), case_number bigint generated always as identity,
 employee_id uuid not null references public.hr_employees(id), case_type text not null check(case_type in ('PERMISO','VACACION','AMONESTACION')),
 category text not null default '', start_date date not null, end_date date not null, day_count integer not null default 1 check(day_count>0),
 paid boolean not null default true, severity text not null default '', reason text not null, observations text not null default '',
 status text not null default 'SOLICITADO' check(status in ('SOLICITADO','APROBADO','RECHAZADO','REGISTRADA','NOTIFICADA','ANULADA')),
 decision_notes text not null default '', created_by uuid not null references public.app_users(id), approved_by uuid references public.app_users(id),
 approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(end_date>=start_date)
);
create index if not exists hr_employee_cases_employee_idx on public.hr_employee_cases(employee_id,case_type,start_date desc);
create index if not exists hr_employee_cases_status_idx on public.hr_employee_cases(case_type,status,start_date desc);
alter table public.hr_employee_cases enable row level security;
revoke all on public.hr_employee_cases from anon,authenticated;

create or replace function public.list_hr_employee_cases(p_token text,p_case_type text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_permission text;v_register_permission text;begin
 v_user:=public.hr_authenticated_user(p_token);
 if p_case_type not in ('PERMISO','VACACION','AMONESTACION') then return jsonb_build_object('success',false,'error','Tipo de registro inválido.');end if;
 v_permission:=case p_case_type when 'PERMISO' then 'ver_permisos_laborales' when 'VACACION' then 'ver_vacaciones' else 'ver_amonestaciones' end;
 v_register_permission:=case p_case_type when 'PERMISO' then 'registrar_permisos_laborales' when 'VACACION' then 'registrar_vacaciones' else 'registrar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar este módulo.');end if;
 return jsonb_build_object('success',true,
 'employees',case when v_user.role='Administrador' or coalesce((v_user.permissions->>v_register_permission)::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'employment_status',e.employment_status) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado'),'[]'::jsonb) else '[]'::jsonb end,
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.case_number desc) from(
  select c.*,e.employee_code,e.document_number,e.full_name,e.position_name,e.direction_name,e.department_name,u.full_name created_by_name,a.full_name approved_by_name
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id join public.app_users u on u.id=c.created_by left join public.app_users a on a.id=c.approved_by
  where c.case_type=p_case_type and (p_year is null or extract(year from c.start_date)=p_year)
 )x),'[]'::jsonb));
end $$;

create or replace function public.save_hr_employee_case(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_type text:=p_data->>'case_type';v_permission text;v_start date;v_end date;v_id uuid;v_employee public.hr_employees;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_type not in ('PERMISO','VACACION','AMONESTACION') then return jsonb_build_object('success',false,'error','Tipo de registro inválido.');end if;
 v_permission:=case v_type when 'PERMISO' then 'registrar_permisos_laborales' when 'VACACION' then 'registrar_vacaciones' else 'registrar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para crear este registro.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_employee.employment_status='Desvinculado' then return jsonb_build_object('success',false,'error','No se pueden registrar novedades para un empleado desvinculado.');end if;
 v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);
 if v_end<v_start then return jsonb_build_object('success',false,'error','La fecha final no puede ser anterior a la inicial.');end if;
 if v_type in ('PERMISO','VACACION') and exists(select 1 from public.hr_employee_cases where employee_id=v_employee.id and case_type=v_type and status in ('SOLICITADO','APROBADO') and daterange(start_date,end_date,'[]')&&daterange(v_start,v_end,'[]')) then return jsonb_build_object('success',false,'error','El empleado ya posee un registro de este tipo que coincide con las fechas seleccionadas.');end if;
 insert into public.hr_employee_cases(employee_id,case_type,category,start_date,end_date,day_count,paid,severity,reason,observations,status,created_by)
 values(v_employee.id,v_type,coalesce(p_data->>'category',''),v_start,v_end,(v_end-v_start)+1,coalesce((p_data->>'paid')::boolean,true),coalesce(p_data->>'severity',''),trim(p_data->>'reason'),coalesce(p_data->>'observations',''),case when v_type='AMONESTACION' then 'REGISTRADA' else 'SOLICITADO' end,v_user.id) returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_'||v_type,'Recursos Humanos',jsonb_build_object('id',v_id,'employee_id',v_employee.id,'start_date',v_start,'end_date',v_end));
 return jsonb_build_object('success',true,'id',v_id);exception when invalid_text_representation or not_null_violation then return jsonb_build_object('success',false,'error','Complete correctamente los campos obligatorios.');end $$;

create or replace function public.decide_hr_employee_case(p_token text,p_case_id uuid,p_decision text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_case public.hr_employee_cases;v_status text;v_permission text;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión no autorizada.');end if;
 if p_decision not in ('APROBAR','RECHAZAR') then return jsonb_build_object('success',false,'error','Decisión inválida.');end if;
 select * into v_case from public.hr_employee_cases where id=p_case_id for update;
 if v_case.id is null then return jsonb_build_object('success',false,'error','Registro no encontrado.');end if;
 v_permission:=case v_case.case_type when 'PERMISO' then 'aprobar_permisos_laborales' when 'VACACION' then 'aprobar_vacaciones' else 'notificar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para decidir este registro.');end if;
 if v_case.status not in ('SOLICITADO','REGISTRADA') then return jsonb_build_object('success',false,'error','Este registro ya fue procesado.');end if;
 v_status:=case when p_decision='RECHAZAR' then 'RECHAZADO' when v_case.case_type='AMONESTACION' then 'NOTIFICADA' else 'APROBADO' end;
 update public.hr_employee_cases set status=v_status,decision_notes=coalesce(p_notes,''),approved_by=v_user.id,approved_at=now(),updated_at=now() where id=p_case_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'DECIDIR_'||v_case.case_type,'Recursos Humanos',jsonb_build_object('id',p_case_id,'employee_id',v_case.employee_id,'from',v_case.status,'to',v_status,'notes',p_notes));
 return jsonb_build_object('success',true,'status',v_status);end $$;
grant execute on function public.list_hr_employee_cases(text,text,integer),public.save_hr_employee_case(text,jsonb),public.decide_hr_employee_case(text,uuid,text,text) to anon,authenticated;
