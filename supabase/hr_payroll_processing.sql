-- Procesamiento integral de nomina y ficha ampliada de empleados.
alter table public.hr_employees add column if not exists cell_phone text;
alter table public.hr_employees add column if not exists landline_phone text;
alter table public.hr_employees add column if not exists driver_license text;
alter table public.hr_employees add column if not exists blood_type text;
alter table public.hr_employees add column if not exists home_address text;
alter table public.hr_employees add column if not exists occupational_group text;
alter table public.hr_employees add column if not exists immediate_supervisor text;
alter table public.hr_employees drop constraint if exists hr_employees_employment_status_check;
alter table public.hr_employees add constraint hr_employees_employment_status_check check(employment_status in ('Activo','Fijo','Carrera Administrativa','Temporal','Interino','Estatuto Simplificado','Licencia','Suspendido','Desvinculado'));

create sequence if not exists public.hr_employee_code_seq start 1000;

create table if not exists public.hr_payroll_account_catalog(
  code text primary key, parent_code text references public.hr_payroll_account_catalog(code),
  name text not null, active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.hr_employee_benefits(
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.hr_employees(id) on delete cascade,
  benefit_type text not null check(benefit_type in ('PRIMA_TRANSPORTE','VIATICOS','HORAS_EXTRAS')),
  default_amount numeric(18,2) not null default 0 check(default_amount>=0), active boolean not null default true,
  unique(employee_id,benefit_type)
);
create table if not exists public.hr_employee_deductions(
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.hr_employees(id) on delete cascade,
  deduction_type text not null check(deduction_type in ('AGUA','SEGURO_COMPLEMENTARIO','DEPENDIENTE_ADICIONAL','ASOCIACION_SERVIDORES_PUBLICOS','OTRO')),
  description text not null default '', monthly_amount numeric(18,2) not null default 0 check(monthly_amount>=0), active boolean not null default true,
  unique(employee_id,deduction_type,description)
);
create table if not exists public.hr_employee_dependents(
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.hr_employees(id) on delete cascade,
  full_name text not null, relationship text not null default '', birth_date date, active boolean not null default true
);
create table if not exists public.hr_payroll_parameters(
  code text not null, effective_from date not null, effective_to date, value numeric(18,6) not null,
  description text not null, primary key(code,effective_from)
);
create table if not exists public.hr_payroll_batches(
  id uuid primary key default gen_random_uuid(), payroll_type text not null check(payroll_type in ('NOMINA','PRIMA_TRANSPORTE','VIATICOS','HORAS_EXTRAS')),
  payroll_year integer not null, payroll_month integer not null check(payroll_month between 1 and 12), account_code text references public.hr_payroll_account_catalog(code),
  status text not null default 'BORRADOR' check(status in ('BORRADOR','VALIDADA','APROBADA','CERRADA')),
  created_by uuid references public.app_users(id), approved_by uuid references public.app_users(id), created_at timestamptz not null default now(), approved_at timestamptz,
  unique(payroll_type,payroll_year,payroll_month)
);
create table if not exists public.hr_payroll_batch_lines(
  id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.hr_payroll_batches(id) on delete cascade,
  employee_id uuid not null references public.hr_employees(id), employee_code text not null, document_number text not null,
  employee_name text not null, position_name text not null, gross_salary numeric(18,2) not null default 0,
  isr numeric(18,2) not null default 0, insurance numeric(18,2) not null default 0,
  employee_pension numeric(18,2) not null default 0, employee_sfs numeric(18,2) not null default 0,
  employer_pension numeric(18,2) not null default 0, employer_sfs numeric(18,2) not null default 0, employer_labor_risk numeric(18,2) not null default 0,
  other_deductions numeric(18,2) not null default 0, total_deductions numeric(18,2) not null default 0, net_amount numeric(18,2) not null default 0,
  calculation_snapshot jsonb not null default '{}'::jsonb, unique(batch_id,employee_id)
);

alter table public.hr_payroll_account_catalog enable row level security;
alter table public.hr_employee_benefits enable row level security;
alter table public.hr_employee_deductions enable row level security;
alter table public.hr_employee_dependents enable row level security;
alter table public.hr_payroll_parameters enable row level security;
alter table public.hr_payroll_batches enable row level security;
alter table public.hr_payroll_batch_lines enable row level security;
revoke all on public.hr_payroll_account_catalog,public.hr_employee_benefits,public.hr_employee_deductions,public.hr_employee_dependents,public.hr_payroll_parameters,public.hr_payroll_batches,public.hr_payroll_batch_lines from anon,authenticated;

insert into public.hr_payroll_account_catalog(code,parent_code,name) values
('2.1.1.1',null,'Remuneraciones al personal fijo'),('2.1.1.1.01','2.1.1.1','Sueldo a empleados fijos'),
('2.1.1.2',null,'Remuneraciones al personal con carácter temporal'),('2.1.1.2.03','2.1.1.2','Suplencias'),('2.1.1.2.11','2.1.1.2','Interinato'),('2.1.1.2.08','2.1.1.2','Empleados temporales'),
('2.1.2.2',null,'Compensaciones'),('2.1.2.2.03','2.1.2.2','Pago de horas extraordinarias'),('2.1.2.2.04','2.1.2.2','Prima de transporte'),('2.1.2.2.05','2.1.2.2','Compensación por servicios de seguridad'),
('2.2.3.1',null,'Viáticos dentro del país'),('2.2.3.1.01','2.2.3.1','Viáticos dentro del país'),('2.2.4.4',null,'Peaje'),('2.2.4.4.01','2.2.4.4','Peaje')
on conflict(code) do update set parent_code=excluded.parent_code,name=excluded.name;

insert into public.hr_payroll_parameters(code,effective_from,value,description) values
('EMPLOYEE_PENSION_RATE','2026-01-01',0.0287,'Aporte empleado pensión'),('EMPLOYER_PENSION_RATE','2026-01-01',0.0710,'Aporte empleador pensión'),
('EMPLOYEE_SFS_RATE','2026-01-01',0.0304,'Aporte empleado SFS'),('EMPLOYER_SFS_RATE','2026-01-01',0.0709,'Aporte empleador SFS'),
('EMPLOYER_LABOR_RISK_RATE','2026-01-01',0.0110,'Riesgo laboral; confirmar categoría institucional'),
('SFS_CAP','2026-02-01',232230,'Tope SFS'),('PENSION_CAP','2026-02-01',464460,'Tope pensión'),('LABOR_RISK_CAP','2026-02-01',92892,'Tope riesgo laboral')
on conflict(code,effective_from) do update set value=excluded.value,description=excluded.description;

create or replace function public.hr_authenticated_user(p_token text) returns public.app_users
language sql stable security definer set search_path=public,extensions as $$
 select u from public.app_users u join public.app_user_sessions s on s.user_id=u.id
 where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active and u.suspended_at is null limit 1 $$;

create or replace function public.hr_calculate_monthly_isr_2026(p_gross numeric,p_employee_tss numeric)
returns numeric language sql immutable as $$
 select round(case when greatest((p_gross-p_employee_tss)*12,0)<=416220 then 0
  when greatest((p_gross-p_employee_tss)*12,0)<=624329 then (greatest((p_gross-p_employee_tss)*12,0)-416220)*0.15/12
  when greatest((p_gross-p_employee_tss)*12,0)<=867123 then (31216+(greatest((p_gross-p_employee_tss)*12,0)-624329)*0.20)/12
  else (79776+(greatest((p_gross-p_employee_tss)*12,0)-867123)*0.25)/12 end,2) $$;

create or replace function public.hr_unit_is_descendant(p_parent_name text,p_child_name text,p_type text)
returns boolean language sql stable security definer set search_path=public as $$
 with recursive tree as (
  select id,parent_id,unit_name,unit_type from public.organization_units where unit_name=p_parent_name and active
  union all select child.id,child.parent_id,child.unit_name,child.unit_type from public.organization_units child join tree parent on child.parent_id=parent.id where child.active
 ) select case when nullif(trim(coalesce(p_child_name,'')),'') is null then true else exists(select 1 from tree where unit_name=p_child_name and unit_type=p_type and unit_name<>p_parent_name) end $$;

create or replace function public.list_hr_payroll_processing(p_token text,p_year integer,p_month integer,p_type text default 'NOMINA')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users; v_batch uuid;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar nómina.'); end if;
 select id into v_batch from public.hr_payroll_batches where payroll_year=p_year and payroll_month=p_month and payroll_type=p_type;
 return jsonb_build_object('success',true,
  'batch',(select to_jsonb(b) from public.hr_payroll_batches b where b.id=v_batch),
  'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.employee_name) from public.hr_payroll_batch_lines l where l.batch_id=v_batch),'[]'::jsonb),
  'accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.code) from public.hr_payroll_account_catalog a where a.active),'[]'::jsonb));
end $$;

create or replace function public.generate_hr_payroll(p_token text,p_year integer,p_month integer,p_type text,p_account_code text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users; v_batch uuid; v_date date:=make_date(p_year,p_month,1);
 v_ep numeric;v_epr numeric;v_es numeric;v_esr numeric;v_lr numeric;v_pc numeric;v_sc numeric;v_lc numeric;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para generar nómina.'); end if;
 if p_type not in ('NOMINA','PRIMA_TRANSPORTE','VIATICOS','HORAS_EXTRAS') then return jsonb_build_object('success',false,'error','Tipo de nómina inválido.'); end if;
 select value into v_ep from public.hr_payroll_parameters where code='EMPLOYEE_PENSION_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_epr from public.hr_payroll_parameters where code='EMPLOYER_PENSION_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_es from public.hr_payroll_parameters where code='EMPLOYEE_SFS_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_esr from public.hr_payroll_parameters where code='EMPLOYER_SFS_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_lr from public.hr_payroll_parameters where code='EMPLOYER_LABOR_RISK_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_pc from public.hr_payroll_parameters where code='PENSION_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_sc from public.hr_payroll_parameters where code='SFS_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_lc from public.hr_payroll_parameters where code='LABOR_RISK_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 insert into public.hr_payroll_batches(payroll_type,payroll_year,payroll_month,account_code,created_by) values(p_type,p_year,p_month,p_account_code,v_user.id)
 on conflict(payroll_type,payroll_year,payroll_month) do update set account_code=coalesce(excluded.account_code,public.hr_payroll_batches.account_code)
 returning id into v_batch;
 delete from public.hr_payroll_batch_lines where batch_id=v_batch;
 insert into public.hr_payroll_batch_lines(batch_id,employee_id,employee_code,document_number,employee_name,position_name,gross_salary,isr,insurance,employee_pension,employee_sfs,employer_pension,employer_sfs,employer_labor_risk,other_deductions,total_deductions,net_amount,calculation_snapshot)
 select v_batch,e.id,e.employee_code,coalesce(e.document_number,''),e.full_name,e.position_name,x.gross,case when p_type='NOMINA' then public.hr_calculate_monthly_isr_2026(x.gross,round(least(x.gross,v_pc)*v_ep+least(x.gross,v_sc)*v_es,2)) else 0 end,0,
  case when p_type='NOMINA' then round(least(x.gross,v_pc)*v_ep,2) else 0 end,
  case when p_type='NOMINA' then round(least(x.gross,v_sc)*v_es,2) else 0 end,
  round(least(x.gross,v_pc)*v_epr,2),round(least(x.gross,v_sc)*v_esr,2),round(least(x.gross,v_lc)*v_lr,2),
  case when p_type='NOMINA' then coalesce(d.amount,0) else 0 end,
  case when p_type='NOMINA' then round(least(x.gross,v_pc)*v_ep+least(x.gross,v_sc)*v_es,2)+public.hr_calculate_monthly_isr_2026(x.gross,round(least(x.gross,v_pc)*v_ep+least(x.gross,v_sc)*v_es,2))+coalesce(d.amount,0) else 0 end,
  x.gross-(case when p_type='NOMINA' then round(least(x.gross,v_pc)*v_ep+least(x.gross,v_sc)*v_es,2)+public.hr_calculate_monthly_isr_2026(x.gross,round(least(x.gross,v_pc)*v_ep+least(x.gross,v_sc)*v_es,2))+coalesce(d.amount,0) else 0 end),
  jsonb_build_object('employee_pension_rate',v_ep,'employee_sfs_rate',v_es,'employer_pension_rate',v_epr,'employer_sfs_rate',v_esr,'labor_risk_rate',v_lr,'pension_cap',v_pc,'sfs_cap',v_sc,'labor_risk_cap',v_lc)
 from public.hr_employees e
 cross join lateral(select case when p_type='NOMINA' then e.monthly_salary else coalesce((select b.default_amount from public.hr_employee_benefits b where b.employee_id=e.id and b.active and b.benefit_type=case p_type when 'PRIMA_TRANSPORTE' then 'PRIMA_TRANSPORTE' when 'VIATICOS' then 'VIATICOS' else 'HORAS_EXTRAS' end),0) end gross)x
 left join lateral(select sum(monthly_amount) amount from public.hr_employee_deductions d where d.employee_id=e.id and d.active)d on true
 where coalesce(e.payroll_status,e.employment_status,'') not in ('INACTIVO','Inactivo','DESVINCULADO') and x.gross>0;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'GENERAR_'||p_type,'Recursos Humanos',jsonb_build_object('batch_id',v_batch,'year',p_year,'month',p_month));
 return jsonb_build_object('success',true,'id',v_batch);
end $$;

create or replace function public.update_hr_payroll_line_isr(p_token text,p_line_id uuid,p_isr numeric)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para editar ISR.'); end if;
 update public.hr_payroll_batch_lines set isr=greatest(p_isr,0),total_deductions=greatest(p_isr,0)+insurance+employee_pension+employee_sfs+other_deductions,net_amount=gross_salary-(greatest(p_isr,0)+insurance+employee_pension+employee_sfs+other_deductions) where id=p_line_id;
 return jsonb_build_object('success',found);end $$;

create or replace function public.save_hr_employee_profile(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_id uuid;v_code text;v_existing boolean;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and ((nullif(p_data->>'id','') is not null and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) or (nullif(p_data->>'id','') is null and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)))) then return jsonb_build_object('success',false,'error','No posee permiso para crear o editar empleados.'); end if;
 if nullif(regexp_replace(coalesce(p_data->>'document_number',''),'\D','','g'),'') is null then return jsonb_build_object('success',false,'error','La cédula es obligatoria y debe contener solo números.'); end if;
 if not exists(select 1 from public.organization_units where unit_name=p_data->>'direction_name' and unit_type='Dirección' and active) then return jsonb_build_object('success',false,'error','Seleccione una dirección válida de la estructura institucional.');end if;
 if not public.hr_unit_is_descendant(p_data->>'direction_name',p_data->>'department_name','Departamento') then return jsonb_build_object('success',false,'error','El departamento no pertenece a la dirección seleccionada.');end if;
 if not public.hr_unit_is_descendant(coalesce(nullif(p_data->>'department_name',''),p_data->>'direction_name'),p_data->>'division_name','División') then return jsonb_build_object('success',false,'error','La división no pertenece al nivel superior seleccionado.');end if;
 if not public.hr_unit_is_descendant(coalesce(nullif(p_data->>'division_name',''),nullif(p_data->>'department_name',''),p_data->>'direction_name'),p_data->>'section_name','Sección') then return jsonb_build_object('success',false,'error','La sección no pertenece al nivel superior seleccionado.');end if;
 v_id:=nullif(p_data->>'id','')::uuid;select exists(select 1 from public.hr_employees where id=v_id or document_number=regexp_replace(p_data->>'document_number','\D','','g')) into v_existing;v_code:=coalesce(nullif(p_data->>'employee_code',''),'EMP-'||lpad(nextval('public.hr_employee_code_seq')::text,6,'0'));
 insert into public.hr_employees(id,employee_code,document_number,full_name,position_name,employment_status,payroll_status,hire_date,birth_date,academic_level,cell_phone,landline_phone,driver_license,blood_type,home_address,occupational_group,immediate_supervisor,direction_name,department_name,division_name,section_name,center_name,monthly_salary,created_by)
 values(coalesce(v_id,gen_random_uuid()),v_code,regexp_replace(p_data->>'document_number','\D','','g'),trim(p_data->>'full_name'),p_data->>'position_name',p_data->>'employment_status',p_data->>'employment_status',nullif(p_data->>'hire_date','')::date,nullif(p_data->>'birth_date','')::date,p_data->>'academic_level',p_data->>'cell_phone',p_data->>'landline_phone',p_data->>'driver_license',p_data->>'blood_type',p_data->>'home_address',p_data->>'occupational_group',p_data->>'immediate_supervisor',p_data->>'direction_name',p_data->>'department_name',p_data->>'division_name',p_data->>'section_name',p_data->>'center_name',coalesce((p_data->>'monthly_salary')::numeric,0),v_user.id)
 on conflict(document_number) do update set full_name=excluded.full_name,position_name=excluded.position_name,employment_status=excluded.employment_status,payroll_status=excluded.payroll_status,hire_date=excluded.hire_date,birth_date=excluded.birth_date,academic_level=excluded.academic_level,cell_phone=excluded.cell_phone,landline_phone=excluded.landline_phone,driver_license=excluded.driver_license,blood_type=excluded.blood_type,home_address=excluded.home_address,occupational_group=excluded.occupational_group,immediate_supervisor=excluded.immediate_supervisor,direction_name=excluded.direction_name,department_name=excluded.department_name,division_name=excluded.division_name,section_name=excluded.section_name,center_name=excluded.center_name,monthly_salary=excluded.monthly_salary,updated_at=now()
 returning id,employee_code into v_id,v_code;
 delete from public.hr_employee_benefits where employee_id=v_id;
 insert into public.hr_employee_benefits(employee_id,benefit_type,default_amount) select v_id,x->>'type',coalesce((x->>'amount')::numeric,0) from jsonb_array_elements(coalesce(p_data->'benefits','[]'))x where coalesce((x->>'active')::boolean,true);
 insert into public.hr_employee_history(employee_id,effective_year,effective_month,position_name,employment_status,payroll_status,direction_name,department_name,division_name,section_name,center_name,execution_fund,program,subproduct,activity,monthly_salary,change_type)
 select e.id,extract(year from current_date)::integer,extract(month from current_date)::integer,e.position_name,e.employment_status,e.payroll_status,e.direction_name,e.department_name,e.division_name,e.section_name,e.center_name,e.execution_fund,e.program,e.subproduct,e.activity,e.monthly_salary,case when v_existing then 'CAMBIO' else 'NUEVO' end from public.hr_employees e where e.id=v_id
 on conflict(employee_id,effective_year,effective_month) do update set position_name=excluded.position_name,employment_status=excluded.employment_status,payroll_status=excluded.payroll_status,direction_name=excluded.direction_name,department_name=excluded.department_name,division_name=excluded.division_name,section_name=excluded.section_name,center_name=excluded.center_name,execution_fund=excluded.execution_fund,program=excluded.program,subproduct=excluded.subproduct,activity=excluded.activity,monthly_salary=excluded.monthly_salary,change_type=excluded.change_type,created_at=now();
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,case when v_existing then 'EMPLEADO_EDITADO' else 'EMPLEADO_CREADO' end,'Recursos Humanos',jsonb_build_object('employee_id',v_id,'employee_code',v_code,'document_number',regexp_replace(p_data->>'document_number','\D','','g')));
 return jsonb_build_object('success',true,'id',v_id,'employee_code',v_code);end $$;

grant execute on function public.hr_authenticated_user(text),public.hr_calculate_monthly_isr_2026(numeric,numeric),public.hr_unit_is_descendant(text,text,text),public.list_hr_payroll_processing(text,integer,integer,text),public.generate_hr_payroll(text,integer,integer,text,text),public.update_hr_payroll_line_isr(text,uuid,numeric),public.save_hr_employee_profile(text,jsonb) to anon,authenticated;
