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
 ,'limitar_novedades_area',coalesce((permissions->>'limitar_novedades_area')::boolean,false)
 ,'ver_indicadores_rrhh',coalesce((permissions->>'ver_indicadores_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false)
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
 request_date date not null default current_date,
 category text not null default '', start_date date not null, end_date date not null, day_count integer not null default 1 check(day_count>0),
 paid boolean not null default true, severity text not null default '', reason text not null, observations text not null default '',
 status text not null default 'SOLICITADO' check(status in ('SOLICITADO','APROBADO','RECHAZADO','REGISTRADA','NOTIFICADA','ANULADA')),
 decision_notes text not null default '', created_by uuid not null references public.app_users(id), approved_by uuid references public.app_users(id),
 approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(end_date>=start_date)
);
alter table public.hr_employee_cases add column if not exists request_date date;
update public.hr_employee_cases set request_date=coalesce(request_date,created_at::date,start_date) where request_date is null;
alter table public.hr_employee_cases alter column request_date set default current_date,alter column request_date set not null;
-- La identidad original es global para permisos, vacaciones y amonestaciones. La numeración
-- visible debe ser independiente por módulo para que no muestre saltos entre tipos de registro.
alter table public.hr_employee_cases add column if not exists module_number bigint;
with numbered as (
 select id,row_number() over(partition by case_type order by created_at,case_number,id) module_number
 from public.hr_employee_cases
)
update public.hr_employee_cases c set module_number=n.module_number
from numbered n where n.id=c.id and c.module_number is null;
alter table public.hr_employee_cases alter column module_number set not null;
create unique index if not exists hr_employee_cases_type_number_uidx on public.hr_employee_cases(case_type,module_number);

create or replace function public.assign_hr_employee_case_module_number()
returns trigger language plpgsql set search_path=public as $$
begin
 if new.module_number is null then
  perform pg_advisory_xact_lock(hashtext('hr_employee_cases:'||new.case_type));
  select coalesce(max(module_number),0)+1 into new.module_number
  from public.hr_employee_cases where case_type=new.case_type;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_employee_case_module_number on public.hr_employee_cases;
create trigger trg_hr_employee_case_module_number before insert on public.hr_employee_cases
for each row execute function public.assign_hr_employee_case_module_number();
create index if not exists hr_employee_cases_employee_idx on public.hr_employee_cases(employee_id,case_type,start_date desc);
create index if not exists hr_employee_cases_status_idx on public.hr_employee_cases(case_type,status,start_date desc);
alter table public.hr_employee_cases enable row level security;
revoke all on public.hr_employee_cases from anon,authenticated;

create or replace function public.hr_employee_in_user_scope(p_user public.app_users,p_employee public.hr_employees)
returns boolean language sql stable set search_path=public as $$
 select not coalesce((p_user.permissions->>'limitar_novedades_area')::boolean,false)
 or case when trim(coalesce(p_user.department,''))<>'' then lower(trim(p_user.department)) in(lower(trim(coalesce(p_employee.direction_name,''))),lower(trim(coalesce(p_employee.department_name,''))),lower(trim(coalesce(p_employee.division_name,''))),lower(trim(coalesce(p_employee.section_name,''))),lower(trim(coalesce(p_employee.center_name,''))))
 else lower(trim(coalesce(p_user.area,''))) in(lower(trim(coalesce(p_employee.direction_name,''))),lower(trim(coalesce(p_employee.department_name,''))),lower(trim(coalesce(p_employee.division_name,''))),lower(trim(coalesce(p_employee.section_name,''))),lower(trim(coalesce(p_employee.center_name,'')))) end
$$;

create or replace function public.list_hr_employee_cases(p_token text,p_case_type text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_permission text;v_register_permission text;begin
 v_user:=public.hr_authenticated_user(p_token);
 if p_case_type not in ('PERMISO','VACACION','AMONESTACION') then return jsonb_build_object('success',false,'error','Tipo de registro inválido.');end if;
 v_permission:=case p_case_type when 'PERMISO' then 'ver_permisos_laborales' when 'VACACION' then 'ver_vacaciones' else 'ver_amonestaciones' end;
 v_register_permission:=case p_case_type when 'PERMISO' then 'registrar_permisos_laborales' when 'VACACION' then 'registrar_vacaciones' else 'registrar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar este módulo.');end if;
 return jsonb_build_object('success',true,
 'employees',case when v_user.role='Administrador' or coalesce((v_user.permissions->>v_register_permission)::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'employment_status',e.employment_status) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb) else '[]'::jsonb end,
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.module_number desc) from(
  select c.*,e.employee_code,e.document_number,e.full_name,e.position_name,e.direction_name,e.department_name,u.full_name created_by_name,a.full_name approved_by_name
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id join public.app_users u on u.id=c.created_by left join public.app_users a on a.id=c.approved_by
  where c.case_type=p_case_type and (p_year is null or extract(year from c.request_date)=p_year) and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x),'[]'::jsonb));
end $$;

create or replace function public.save_hr_employee_case(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_type text:=p_data->>'case_type';v_permission text;v_start date;v_end date;v_request date;v_id uuid;v_employee public.hr_employees;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_type not in ('PERMISO','VACACION','AMONESTACION') then return jsonb_build_object('success',false,'error','Tipo de registro inválido.');end if;
 v_permission:=case v_type when 'PERMISO' then 'registrar_permisos_laborales' when 'VACACION' then 'registrar_vacaciones' else 'registrar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para crear este registro.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','El empleado no pertenece al área asignada a este usuario.');end if;
 if v_employee.employment_status='Desvinculado' then return jsonb_build_object('success',false,'error','No se pueden registrar novedades para un empleado desvinculado.');end if;
 v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);v_request:=case when v_type in('PERMISO','VACACION') then (p_data->>'request_date')::date else v_start end;
 if v_request is null then return jsonb_build_object('success',false,'error','La fecha de solicitud es obligatoria.');end if;
 if v_end<v_start then return jsonb_build_object('success',false,'error','La fecha final no puede ser anterior a la inicial.');end if;
 if v_type in ('PERMISO','VACACION') and exists(select 1 from public.hr_employee_cases where employee_id=v_employee.id and case_type=v_type and status in ('SOLICITADO','APROBADO') and daterange(start_date,end_date,'[]')&&daterange(v_start,v_end,'[]')) then return jsonb_build_object('success',false,'error','El empleado ya posee un registro de este tipo que coincide con las fechas seleccionadas.');end if;
 insert into public.hr_employee_cases(employee_id,case_type,request_date,category,start_date,end_date,day_count,paid,severity,reason,observations,status,created_by)
 values(v_employee.id,v_type,v_request,coalesce(p_data->>'category',''),v_start,v_end,(v_end-v_start)+1,coalesce((p_data->>'paid')::boolean,true),coalesce(p_data->>'severity',''),trim(p_data->>'reason'),coalesce(p_data->>'observations',''),case when v_type='AMONESTACION' then 'REGISTRADA' else 'SOLICITADO' end,v_user.id) returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_'||v_type,'Recursos Humanos',jsonb_build_object('id',v_id,'employee_id',v_employee.id,'request_date',v_request,'start_date',v_start,'end_date',v_end));
 return jsonb_build_object('success',true,'id',v_id);exception when invalid_text_representation or not_null_violation then return jsonb_build_object('success',false,'error','Complete correctamente los campos obligatorios.');end $$;

create or replace function public.decide_hr_employee_case(p_token text,p_case_id uuid,p_decision text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_case public.hr_employee_cases;v_employee public.hr_employees;v_status text;v_permission text;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión no autorizada.');end if;
 if p_decision not in ('APROBAR','RECHAZAR') then return jsonb_build_object('success',false,'error','Decisión inválida.');end if;
 select * into v_case from public.hr_employee_cases where id=p_case_id for update;
 if v_case.id is null then return jsonb_build_object('success',false,'error','Registro no encontrado.');end if;
 select * into v_employee from public.hr_employees where id=v_case.employee_id;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','No puede procesar novedades de empleados fuera de su área.');end if;
 v_permission:=case v_case.case_type when 'PERMISO' then 'aprobar_permisos_laborales' when 'VACACION' then 'aprobar_vacaciones' else 'notificar_amonestaciones' end;
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para decidir este registro.');end if;
 if v_case.status not in ('SOLICITADO','REGISTRADA') then return jsonb_build_object('success',false,'error','Este registro ya fue procesado.');end if;
 v_status:=case when p_decision='RECHAZAR' then 'RECHAZADO' when v_case.case_type='AMONESTACION' then 'NOTIFICADA' else 'APROBADO' end;
 update public.hr_employee_cases set status=v_status,decision_notes=coalesce(p_notes,''),approved_by=v_user.id,approved_at=now(),updated_at=now() where id=p_case_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'DECIDIR_'||v_case.case_type,'Recursos Humanos',jsonb_build_object('id',p_case_id,'employee_id',v_case.employee_id,'from',v_case.status,'to',v_status,'notes',p_notes));
 return jsonb_build_object('success',true,'status',v_status);end $$;

create or replace function public.get_hr_case_analytics(p_token text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employees jsonb;v_summary jsonb;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_indicadores_rrhh')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar los indicadores de Recursos Humanos.');
 end if;
 with scoped as (
  select c.*,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id
  where c.status<>'ANULADA' and (p_year is null or extract(year from c.request_date)=p_year)
   and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 ),medical_ordered as (
  select employee_id,start_date,end_date,lag(end_date) over(partition by employee_id order by start_date,end_date) previous_end
  from scoped where case_type='PERMISO' and (lower(category) like '%médic%' or lower(category) like '%medic%' or lower(category) like '%licencia%' or lower(category) like '%enfermedad%')
 ),medical_streaks as (
  select employee_id,count(*) filter(where previous_end is not null and start_date<=previous_end+7) consecutive_licenses
  from medical_ordered group by employee_id
 ),employee_totals as (
  select s.employee_id,max(s.employee_code) employee_code,max(s.full_name) full_name,max(s.position_name) position_name,
   max(s.direction_name) direction_name,max(s.department_name) department_name,
   count(*) filter(where s.case_type='PERMISO') permission_count,
   count(*) filter(where s.case_type='PERMISO' and (lower(s.category) like '%médic%' or lower(s.category) like '%medic%' or lower(s.category) like '%licencia%' or lower(s.category) like '%enfermedad%')) medical_license_count,
   count(*) filter(where s.case_type='VACACION') vacation_count,count(*) filter(where s.case_type='AMONESTACION') warning_count,
   count(*) filter(where s.status in ('SOLICITADO','REGISTRADA')) pending_count,
   coalesce(sum(s.day_count) filter(where s.case_type in ('PERMISO','VACACION') and s.status='APROBADO'),0) approved_absence_days,
   max(s.request_date) last_request_date from scoped s group by s.employee_id
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'employee_id',t.employee_id,'employee_code',t.employee_code,'full_name',t.full_name,'position_name',t.position_name,
  'direction_name',t.direction_name,'department_name',t.department_name,'permission_count',t.permission_count,
  'medical_license_count',t.medical_license_count,'consecutive_licenses',coalesce(m.consecutive_licenses,0),
  'vacation_count',t.vacation_count,'warning_count',t.warning_count,'pending_count',t.pending_count,
  'approved_absence_days',t.approved_absence_days,'last_request_date',t.last_request_date,
  'risk_level',case when t.permission_count>=5 or coalesce(m.consecutive_licenses,0)>=3 or t.warning_count>=3 then 'ALTO'
                    when t.permission_count>=3 or coalesce(m.consecutive_licenses,0)>=2 or t.vacation_count>=3 or t.warning_count>=2 then 'MEDIO' else 'BAJO' end,
  'recommendation',case when t.warning_count>=3 then 'Revisión disciplinaria y plan de mejora documentado'
                        when coalesce(m.consecutive_licenses,0)>=2 then 'Validar soportes médicos y realizar entrevista de seguimiento'
                        when t.permission_count>=3 then 'Revisar causas recurrentes y acordar medidas preventivas'
                        when t.vacation_count>=3 then 'Revisar fraccionamiento y planificación anual de vacaciones'
                        else 'Seguimiento ordinario' end
 ) order by case when t.permission_count>=5 or coalesce(m.consecutive_licenses,0)>=3 or t.warning_count>=3 then 1 when t.permission_count>=3 or coalesce(m.consecutive_licenses,0)>=2 or t.vacation_count>=3 or t.warning_count>=2 then 2 else 3 end,t.full_name),'[]'::jsonb)
 into v_employees from employee_totals t left join medical_streaks m on m.employee_id=t.employee_id;
 with scoped as (
  select c.* from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id
  where c.status<>'ANULADA' and (p_year is null or extract(year from c.request_date)=p_year)
   and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 ) select jsonb_build_object('permissions',count(*) filter(where case_type='PERMISO'),'vacations',count(*) filter(where case_type='VACACION'),
  'warnings',count(*) filter(where case_type='AMONESTACION'),'pending',count(*) filter(where status in ('SOLICITADO','REGISTRADA')),
  'approved_absence_days',coalesce(sum(day_count) filter(where case_type in ('PERMISO','VACACION') and status='APROBADO'),0))
 into v_summary from scoped;
 return jsonb_build_object('success',true,'summary',v_summary,'employees',v_employees,'year',p_year,'generated_at',now());
end $$;
revoke all on function public.hr_employee_in_user_scope(public.app_users,public.hr_employees) from public,anon,authenticated;
grant execute on function public.list_hr_employee_cases(text,text,integer),public.save_hr_employee_case(text,jsonb),public.decide_hr_employee_case(text,uuid,text,text),public.get_hr_case_analytics(text,integer) to anon,authenticated;
