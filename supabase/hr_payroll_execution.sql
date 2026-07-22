-- Ejecución mensual de nómina. Los datos personales permanecen exclusivamente en Supabase.
create table if not exists public.hr_payroll_runs (
  id uuid primary key default gen_random_uuid(),
  payroll_year integer not null check(payroll_year between 2000 and 2100),
  payroll_month integer not null check(payroll_month between 1 and 12),
  status text not null default 'BORRADOR' check(status in ('BORRADOR','VALIDADA','APROBADA','CERRADA')),
  employee_count integer not null default 0,
  total_amount numeric(18,2) not null default 0,
  source_name text not null default '',
  uploaded_by uuid references public.app_users(id),
  uploaded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(payroll_year,payroll_month)
);

create table if not exists public.hr_payroll_run_lines (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.hr_payroll_runs(id) on delete cascade,
  execution_fund text not null,
  program integer not null,
  subproduct integer not null,
  activity integer not null,
  first_names text not null,
  last_names text not null,
  gender text,
  birth_date date,
  age integer,
  document_number text not null,
  phone text,
  academic_level text,
  hire_date date,
  years_of_service integer,
  termination_date date,
  termination_type text,
  bank_account text,
  position_name text,
  employee_group text,
  employment_status text,
  direction_name text,
  department_name text,
  division_name text,
  section_name text,
  center_name text,
  monthly_salary numeric(18,2) not null check(monthly_salary>=0),
  created_at timestamptz not null default now(),
  unique(payroll_run_id,document_number)
);

create index if not exists hr_payroll_lines_run_idx on public.hr_payroll_run_lines(payroll_run_id);
create index if not exists hr_payroll_lines_budget_idx on public.hr_payroll_run_lines(execution_fund,program,subproduct,activity);
alter table public.hr_payroll_runs enable row level security;
alter table public.hr_payroll_run_lines enable row level security;
revoke all on public.hr_payroll_runs,public.hr_payroll_run_lines from anon,authenticated;

alter table public.hr_employees alter column organization_unit_id drop not null;
alter table public.hr_employees add column if not exists first_names text;
alter table public.hr_employees add column if not exists last_names text;
alter table public.hr_employees add column if not exists gender text;
alter table public.hr_employees add column if not exists birth_date date;
alter table public.hr_employees add column if not exists phone text;
alter table public.hr_employees add column if not exists academic_level text;
alter table public.hr_employees add column if not exists years_of_service integer;
alter table public.hr_employees add column if not exists termination_date date;
alter table public.hr_employees add column if not exists termination_type text;
alter table public.hr_employees add column if not exists bank_account text;
alter table public.hr_employees add column if not exists employee_group text;
alter table public.hr_employees add column if not exists payroll_status text;
alter table public.hr_employees add column if not exists direction_name text;
alter table public.hr_employees add column if not exists department_name text;
alter table public.hr_employees add column if not exists division_name text;
alter table public.hr_employees add column if not exists section_name text;
alter table public.hr_employees add column if not exists center_name text;
alter table public.hr_employees add column if not exists execution_fund text;
alter table public.hr_employees add column if not exists program integer;
alter table public.hr_employees add column if not exists subproduct integer;
alter table public.hr_employees add column if not exists activity integer;
alter table public.hr_employees add column if not exists monthly_salary numeric(18,2) not null default 0;
alter table public.hr_employees add column if not exists last_payroll_year integer;
alter table public.hr_employees add column if not exists last_payroll_month integer;

create table if not exists public.hr_employee_history (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  payroll_run_id uuid references public.hr_payroll_runs(id) on delete set null,
  effective_year integer not null,
  effective_month integer not null,
  position_name text,
  employment_status text,
  payroll_status text,
  direction_name text,
  department_name text,
  division_name text,
  section_name text,
  center_name text,
  execution_fund text,
  program integer,
  subproduct integer,
  activity integer,
  monthly_salary numeric(18,2) not null default 0,
  change_type text not null default 'SIN_CAMBIO' check(change_type in ('NUEVO','CAMBIO','SIN_CAMBIO')),
  created_at timestamptz not null default now(),
  unique(employee_id,effective_year,effective_month)
);
create index if not exists hr_employee_history_period_idx on public.hr_employee_history(effective_year,effective_month);
alter table public.hr_employee_history enable row level security;
revoke all on public.hr_employee_history from anon,authenticated;

create or replace function public.import_hr_payroll_run(p_token text,p_year integer,p_month integer,p_source_name text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_run_id uuid; v_count integer; v_total numeric;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para importar nóminas.'); end if;
  if p_month<1 or p_month>12 or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)=0
    then return jsonb_build_object('success',false,'error','La nómina no contiene registros válidos.'); end if;

  insert into public.hr_payroll_runs(payroll_year,payroll_month,status,source_name,uploaded_by)
  values(p_year,p_month,'BORRADOR',coalesce(p_source_name,''),v_user.id)
  on conflict(payroll_year,payroll_month) do update set status='BORRADOR',source_name=excluded.source_name,uploaded_by=excluded.uploaded_by,uploaded_at=now(),updated_at=now()
  returning id into v_run_id;
  delete from public.hr_payroll_run_lines where payroll_run_id=v_run_id;

  insert into public.hr_payroll_run_lines(payroll_run_id,execution_fund,program,subproduct,activity,first_names,last_names,gender,birth_date,age,document_number,phone,academic_level,hire_date,years_of_service,termination_date,termination_type,bank_account,position_name,employee_group,employment_status,direction_name,department_name,division_name,section_name,center_name,monthly_salary)
  select v_run_id,trim(x.execution_fund),x.program,x.subproduct,x.activity,trim(x.first_names),trim(x.last_names),nullif(trim(x.gender),''),x.birth_date,x.age,trim(x.document_number),nullif(trim(x.phone),''),nullif(trim(x.academic_level),''),x.hire_date,x.years_of_service,x.termination_date,nullif(trim(x.termination_type),''),nullif(trim(x.bank_account),''),nullif(trim(x.position_name),''),nullif(trim(x.employee_group),''),case when upper(trim(x.employment_status))='FRIJO' then 'FIJO' else upper(trim(x.employment_status)) end,nullif(trim(x.direction_name),''),nullif(trim(x.department_name),''),nullif(trim(x.division_name),''),nullif(trim(x.section_name),''),nullif(trim(x.center_name),''),x.monthly_salary
  from jsonb_to_recordset(p_rows) as x(execution_fund text,program integer,subproduct integer,activity integer,first_names text,last_names text,gender text,birth_date date,age integer,document_number text,phone text,academic_level text,hire_date date,years_of_service integer,termination_date date,termination_type text,bank_account text,position_name text,employee_group text,employment_status text,direction_name text,department_name text,division_name text,section_name text,center_name text,monthly_salary numeric);

  insert into public.hr_employees(employee_code,document_number,full_name,organization_unit_id,position_name,employment_status,hire_date,created_by,first_names,last_names,gender,birth_date,phone,academic_level,years_of_service,termination_date,termination_type,bank_account,employee_group,payroll_status,direction_name,department_name,division_name,section_name,center_name,execution_fund,program,subproduct,activity,monthly_salary,last_payroll_year,last_payroll_month)
  select l.document_number,l.document_number,trim(l.first_names||' '||l.last_names),
    (select o.id from public.organization_units o where lower(trim(o.unit_name))=lower(trim(l.direction_name)) limit 1),
    coalesce(l.position_name,'Sin cargo'),case when l.termination_date is null then 'Activo' else 'Desvinculado' end,l.hire_date,v_user.id,l.first_names,l.last_names,l.gender,l.birth_date,l.phone,l.academic_level,l.years_of_service,l.termination_date,l.termination_type,l.bank_account,l.employee_group,l.employment_status,l.direction_name,l.department_name,l.division_name,l.section_name,l.center_name,l.execution_fund,l.program,l.subproduct,l.activity,l.monthly_salary,p_year,p_month
  from public.hr_payroll_run_lines l where l.payroll_run_id=v_run_id
  on conflict(document_number) do update set full_name=excluded.full_name,organization_unit_id=excluded.organization_unit_id,position_name=excluded.position_name,employment_status=excluded.employment_status,hire_date=excluded.hire_date,first_names=excluded.first_names,last_names=excluded.last_names,gender=excluded.gender,birth_date=excluded.birth_date,phone=excluded.phone,academic_level=excluded.academic_level,years_of_service=excluded.years_of_service,termination_date=excluded.termination_date,termination_type=excluded.termination_type,bank_account=excluded.bank_account,employee_group=excluded.employee_group,payroll_status=excluded.payroll_status,direction_name=excluded.direction_name,department_name=excluded.department_name,division_name=excluded.division_name,section_name=excluded.section_name,center_name=excluded.center_name,execution_fund=excluded.execution_fund,program=excluded.program,subproduct=excluded.subproduct,activity=excluded.activity,monthly_salary=excluded.monthly_salary,last_payroll_year=excluded.last_payroll_year,last_payroll_month=excluded.last_payroll_month,updated_at=now();

  insert into public.hr_employee_history(employee_id,payroll_run_id,effective_year,effective_month,position_name,employment_status,payroll_status,direction_name,department_name,division_name,section_name,center_name,execution_fund,program,subproduct,activity,monthly_salary,change_type)
  select e.id,v_run_id,p_year,p_month,l.position_name,e.employment_status,l.employment_status,l.direction_name,l.department_name,l.division_name,l.section_name,l.center_name,l.execution_fund,l.program,l.subproduct,l.activity,l.monthly_salary,
    case when not exists(select 1 from public.hr_employee_history h where h.employee_id=e.id) then 'NUEVO'
      when exists(select 1 from public.hr_employee_history h where h.employee_id=e.id and (coalesce(h.position_name,'')<>coalesce(l.position_name,'') or coalesce(h.payroll_status,'')<>coalesce(l.employment_status,'') or coalesce(h.direction_name,'')<>coalesce(l.direction_name,'') or coalesce(h.department_name,'')<>coalesce(l.department_name,'') or coalesce(h.execution_fund,'')<>coalesce(l.execution_fund,'') or coalesce(h.program,0)<>l.program or coalesce(h.subproduct,0)<>l.subproduct or coalesce(h.activity,0)<>l.activity or coalesce(h.monthly_salary,0)<>l.monthly_salary) and (h.effective_year*100+h.effective_month)<(p_year*100+p_month)) then 'CAMBIO' else 'SIN_CAMBIO' end
  from public.hr_payroll_run_lines l join public.hr_employees e on e.document_number=l.document_number where l.payroll_run_id=v_run_id
  on conflict(employee_id,effective_year,effective_month) do update set payroll_run_id=excluded.payroll_run_id,position_name=excluded.position_name,employment_status=excluded.employment_status,payroll_status=excluded.payroll_status,direction_name=excluded.direction_name,department_name=excluded.department_name,division_name=excluded.division_name,section_name=excluded.section_name,center_name=excluded.center_name,execution_fund=excluded.execution_fund,program=excluded.program,subproduct=excluded.subproduct,activity=excluded.activity,monthly_salary=excluded.monthly_salary,change_type=excluded.change_type;

  select count(*),coalesce(sum(monthly_salary),0) into v_count,v_total from public.hr_payroll_run_lines where payroll_run_id=v_run_id;
  update public.hr_payroll_runs set employee_count=v_count,total_amount=v_total,updated_at=now() where id=v_run_id;
  insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'IMPORTACION_NOMINA','Recursos Humanos',jsonb_build_object('run_id',v_run_id,'year',p_year,'month',p_month,'employees',v_count,'total',v_total));
  return jsonb_build_object('success',true,'run_id',v_run_id,'employee_count',v_count,'total_amount',v_total);
exception when unique_violation then return jsonb_build_object('success',false,'error','La nómina contiene cédulas duplicadas.');
end $$;

create or replace function public.list_hr_employee_registry(p_token text,p_year integer default null,p_month integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_employees jsonb; v_history jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar empleados.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_employees from (
    select e.id,e.employee_code,e.document_number,e.full_name,e.first_names,e.last_names,e.gender,e.birth_date,e.phone,e.academic_level,e.hire_date,e.years_of_service,e.termination_date,e.termination_type,e.bank_account,e.position_name,e.employee_group,e.employment_status,e.payroll_status,e.direction_name,e.department_name,e.division_name,e.section_name,e.center_name,e.execution_fund,e.program,e.subproduct,e.activity,e.monthly_salary,e.last_payroll_year,e.last_payroll_month,e.updated_at,e.cell_phone,e.landline_phone,e.driver_license,e.blood_type,e.home_address,e.occupational_group,e.immediate_supervisor,coalesce((select jsonb_agg(jsonb_build_object('type',b.benefit_type,'amount',b.default_amount,'active',b.active) order by b.benefit_type) from public.hr_employee_benefits b where b.employee_id=e.id),'[]'::jsonb) benefits
    from public.hr_employees e)x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.effective_year desc,x.effective_month desc,x.full_name),'[]'::jsonb) into v_history from (
    select h.*,e.document_number,e.full_name from public.hr_employee_history h join public.hr_employees e on e.id=h.employee_id
    where (p_year is null or h.effective_year=p_year) and (p_month is null or h.effective_month=p_month))x;
  return jsonb_build_object('success',true,'employees',v_employees,'history',v_history);
end $$;

create or replace function public.list_hr_payroll_runs(p_token text,p_year integer,p_month integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_runs jsonb; v_lines jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar nóminas.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.payroll_month desc),'[]'::jsonb) into v_runs from (
    select r.*,coalesce((select jsonb_agg(to_jsonb(f) order by f.execution_fund) from (
      select l.execution_fund,count(*) employees,sum(l.monthly_salary) amount,c.monthly_cap,
        c.monthly_cap-sum(l.monthly_salary) available
      from public.hr_payroll_run_lines l left join public.hr_payroll_budget_caps c on c.budget_year=r.payroll_year and c.execution_fund=l.execution_fund
      where l.payroll_run_id=r.id group by l.execution_fund,c.monthly_cap)f),'[]'::jsonb) funds
    from public.hr_payroll_runs r where r.payroll_year=p_year and (p_month is null or r.payroll_month=p_month))x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.first_names,x.last_names),'[]'::jsonb) into v_lines from (
    select l.* from public.hr_payroll_run_lines l join public.hr_payroll_runs r on r.id=l.payroll_run_id
    where r.payroll_year=p_year and (p_month is null or r.payroll_month=p_month))x;
  return jsonb_build_object('success',true,'runs',v_runs,'lines',v_lines);
end $$;

grant execute on function public.import_hr_payroll_run(text,integer,integer,text,jsonb),public.list_hr_payroll_runs(text,integer,integer),public.list_hr_employee_registry(text,integer,integer) to anon,authenticated;
