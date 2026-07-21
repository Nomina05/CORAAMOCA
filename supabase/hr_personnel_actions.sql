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
declare v_user public.app_users;v_id uuid;v_employee public.hr_employees;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false) and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar acciones de personal.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 insert into public.hr_personnel_actions(employee_id,effective_date,action_type,other_action,present_state,proposed_state,observations,recommendation,immediate_supervisor,department_manager,payroll_officer,general_director,created_by)
 values(v_employee.id,(p_data->>'effective_date')::date,p_data->>'action_type',coalesce(p_data->>'other_action',''),
 jsonb_build_object('direction',v_employee.direction_name,'department',v_employee.department_name,'division',v_employee.division_name,'section',v_employee.section_name,'position',v_employee.position_name,'salary',v_employee.monthly_salary),
 coalesce(p_data->'proposed_state','{}'::jsonb),coalesce(p_data->>'observations',''),coalesce(p_data->>'recommendation',''),coalesce(p_data->>'immediate_supervisor',''),coalesce(p_data->>'department_manager',''),coalesce(p_data->>'payroll_officer',''),coalesce(p_data->>'general_director',''),v_user.id) returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_ACCION_PERSONAL','Recursos Humanos',jsonb_build_object('id',v_id,'employee_id',v_employee.id,'type',p_data->>'action_type'));
 return jsonb_build_object('success',true,'id',v_id);end $$;
grant execute on function public.list_hr_personnel_actions(text,uuid),public.save_hr_personnel_action(text,jsonb) to anon,authenticated;
