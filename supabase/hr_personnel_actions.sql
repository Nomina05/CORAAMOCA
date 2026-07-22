-- Acciones de personal vinculadas al expediente maestro del empleado.
create table if not exists public.hr_personnel_actions(
 id uuid primary key default gen_random_uuid(), action_number bigint generated always as identity,
 employee_id uuid not null references public.hr_employees(id), effective_date date not null,
 action_type text not null check(action_type in ('APERTURA_CONCURSO','AUMENTO_SUELDO','ASCENSO','INTERINAJE','VACACIONES','LICENCIA_ESTUDIOS','LICENCIA_SIN_SUELDO','LICENCIA_ENFERMEDAD','LICENCIA_EMBARAZO','COMPENSACION','REINGRESO_TRABAJO','NOMBRAMIENTO_REGULAR','NOMBRAMIENTO_CONTRATO','RESCISION_CONTRATO','PRORROGA_CONTRATO','DESPIDO','ABANDONO_TRABAJO','RENUNCIA','TRASLADO','OTROS')),
 other_action text not null default '', present_state jsonb not null default '{}'::jsonb,
 proposed_state jsonb not null default '{}'::jsonb, observations text not null default '', recommendation text not null default '',
 immediate_supervisor text not null default '', department_manager text not null default '', payroll_officer text not null default '', general_director text not null default '',
 status text not null default 'BORRADOR' check(status in ('BORRADOR','RECOMENDADA','APROBADA','ANULADA')),
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists hr_personnel_actions_employee_idx on public.hr_personnel_actions(employee_id,created_at desc);
alter table public.hr_personnel_actions add column if not exists exit_date date;
alter table public.hr_personnel_actions add column if not exists exit_cause text not null default '';
alter table public.hr_personnel_actions add column if not exists approved_by uuid references public.app_users(id);
alter table public.hr_personnel_actions add column if not exists approved_at timestamptz;
alter table public.hr_personnel_actions enable row level security;
revoke all on public.hr_personnel_actions from anon,authenticated;

create or replace function public.list_hr_personnel_actions(p_token text,p_employee_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar acciones de personal.');end if;
 return jsonb_build_object('success',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
  select a.*,e.employee_code,e.document_number,e.full_name,e.position_name from public.hr_personnel_actions a join public.hr_employees e on e.id=a.employee_id where p_employee_id is null or a.employee_id=p_employee_id)x),'[]'::jsonb));end $$;

create or replace function public.save_hr_personnel_action(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_id uuid;v_employee public.hr_employees;v_type text:=p_data->>'action_type';v_effective date:=(p_data->>'effective_date')::date;v_exit_cause text;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false) and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar acciones de personal.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 v_exit_cause:=case v_type when 'DESPIDO' then 'Despido' when 'ABANDONO_TRABAJO' then 'Abandono del trabajo' when 'RENUNCIA' then 'Renuncia' when 'RESCISION_CONTRATO' then 'Rescisión de contrato' else '' end;
 insert into public.hr_personnel_actions(employee_id,effective_date,action_type,other_action,present_state,proposed_state,observations,recommendation,immediate_supervisor,department_manager,payroll_officer,general_director,exit_date,exit_cause,created_by)
 values(v_employee.id,v_effective,p_data->>'action_type',coalesce(p_data->>'other_action',''),
 jsonb_build_object('direction',v_employee.direction_name,'department',v_employee.department_name,'division',v_employee.division_name,'section',v_employee.section_name,'position',v_employee.position_name,'salary',v_employee.monthly_salary),
 coalesce(p_data->'proposed_state','{}'::jsonb),coalesce(p_data->>'observations',''),coalesce(p_data->>'recommendation',''),coalesce(p_data->>'immediate_supervisor',''),coalesce(p_data->>'department_manager',''),coalesce(p_data->>'payroll_officer',''),coalesce(p_data->>'general_director',''),case when v_exit_cause<>'' then v_effective else null end,v_exit_cause,v_user.id) returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_ACCION_PERSONAL','Recursos Humanos',jsonb_build_object('id',v_id,'employee_id',v_employee.id,'type',p_data->>'action_type'));
 return jsonb_build_object('success',true,'id',v_id);end $$;

create or replace function public.approve_hr_personnel_action(p_token text,p_action_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_action public.hr_personnel_actions;v_employee public.hr_employees;v_before jsonb;v_salary numeric;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'aprobar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para aprobar acciones de personal.');end if;
 select * into v_action from public.hr_personnel_actions where id=p_action_id for update;if v_action.id is null then return jsonb_build_object('success',false,'error','Acción de personal no encontrada.');end if;
 if v_action.status<>'BORRADOR' then return jsonb_build_object('success',false,'error','La acción ya fue procesada.');end if;
 if v_action.effective_date>current_date then return jsonb_build_object('success',false,'error','La acción solo puede aplicarse en su fecha efectiva o después de ella.');end if;
 if v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') and v_action.exit_date>current_date then return jsonb_build_object('success',false,'error','La terminación solo puede aplicarse en la fecha de salida o después de ella.');end if;
 select * into v_employee from public.hr_employees where id=v_action.employee_id for update;
 if v_action.action_type='AUMENTO_SUELDO' and coalesce(nullif(v_action.proposed_state->>'salary','')::numeric,0)<=0 then return jsonb_build_object('success',false,'error','Indique el nuevo sueldo antes de aprobar el aumento.');end if;
 if v_action.action_type in ('ASCENSO','INTERINAJE','NOMBRAMIENTO_REGULAR','NOMBRAMIENTO_CONTRATO') and nullif(trim(coalesce(v_action.proposed_state->>'position','')),'') is null then return jsonb_build_object('success',false,'error','Indique el nuevo cargo o designación antes de aprobar.');end if;
 if v_action.action_type='TRASLADO' and nullif(trim(concat_ws('',v_action.proposed_state->>'direction',v_action.proposed_state->>'department',v_action.proposed_state->>'division',v_action.proposed_state->>'section')),'') is null then return jsonb_build_object('success',false,'error','Indique la nueva ubicación institucional antes de aprobar el traslado.');end if;
 v_before:=to_jsonb(v_employee);v_salary:=coalesce(nullif(v_action.proposed_state->>'salary','')::numeric,v_employee.monthly_salary);
 update public.hr_employees set
  direction_name=coalesce(nullif(v_action.proposed_state->>'direction',''),direction_name),department_name=coalesce(nullif(v_action.proposed_state->>'department',''),department_name),division_name=coalesce(nullif(v_action.proposed_state->>'division',''),division_name),section_name=coalesce(nullif(v_action.proposed_state->>'section',''),section_name),position_name=coalesce(nullif(v_action.proposed_state->>'position',''),position_name),monthly_salary=v_salary,
  termination_date=case when v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') then v_action.exit_date when v_action.action_type='REINGRESO_TRABAJO' then null else termination_date end,
  termination_type=case when v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') then v_action.exit_cause when v_action.action_type='REINGRESO_TRABAJO' then null else termination_type end,
  employment_status=case when v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') then 'Desvinculado' when v_action.action_type='REINGRESO_TRABAJO' then 'Activo' else employment_status end,
  payroll_status=case when v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') then 'DESVINCULADO' when v_action.action_type='REINGRESO_TRABAJO' then coalesce(nullif(payroll_status,'DESVINCULADO'),'FIJO') else payroll_status end,updated_at=now() where id=v_employee.id;
 if v_action.action_type in ('DESPIDO','ABANDONO_TRABAJO','RENUNCIA','RESCISION_CONTRATO') then update public.hr_employee_payroll_assignments set active=false,end_date=coalesce(end_date,v_action.exit_date),updated_at=now() where employee_id=v_employee.id and active;else update public.hr_employee_payroll_assignments set gross_amount=v_salary,position_name=coalesce(nullif(v_action.proposed_state->>'position',''),position_name),updated_at=now() where employee_id=v_employee.id and payroll_type='FIJA';end if;
 insert into public.hr_employee_history(employee_id,effective_year,effective_month,position_name,employment_status,payroll_status,direction_name,department_name,division_name,section_name,center_name,execution_fund,program,subproduct,activity,monthly_salary,change_type)
 select e.id,extract(year from v_action.effective_date)::integer,extract(month from v_action.effective_date)::integer,e.position_name,e.employment_status,e.payroll_status,e.direction_name,e.department_name,e.division_name,e.section_name,e.center_name,e.execution_fund,e.program,e.subproduct,e.activity,e.monthly_salary,'CAMBIO' from public.hr_employees e where e.id=v_employee.id
 on conflict(employee_id,effective_year,effective_month) do update set position_name=excluded.position_name,employment_status=excluded.employment_status,payroll_status=excluded.payroll_status,direction_name=excluded.direction_name,department_name=excluded.department_name,division_name=excluded.division_name,section_name=excluded.section_name,center_name=excluded.center_name,monthly_salary=excluded.monthly_salary,change_type='CAMBIO',created_at=now();
 update public.hr_personnel_actions set status='APROBADA',approved_by=v_user.id,approved_at=now(),updated_at=now() where id=v_action.id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'APROBAR_ACCION_PERSONAL','Recursos Humanos',jsonb_build_object('action_id',v_action.id,'employee_id',v_employee.id,'action_type',v_action.action_type,'previous',v_before,'new',(select to_jsonb(e) from public.hr_employees e where e.id=v_employee.id)));
 return jsonb_build_object('success',true,'id',v_action.id);end $$;
grant execute on function public.list_hr_personnel_actions(text,uuid),public.save_hr_personnel_action(text,jsonb),public.approve_hr_personnel_action(text,uuid) to anon,authenticated;
