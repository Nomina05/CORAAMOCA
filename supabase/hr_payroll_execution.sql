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

  select count(*),coalesce(sum(monthly_salary),0) into v_count,v_total from public.hr_payroll_run_lines where payroll_run_id=v_run_id;
  update public.hr_payroll_runs set employee_count=v_count,total_amount=v_total,updated_at=now() where id=v_run_id;
  insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'IMPORTACION_NOMINA','Recursos Humanos',jsonb_build_object('run_id',v_run_id,'year',p_year,'month',p_month,'employees',v_count,'total',v_total));
  return jsonb_build_object('success',true,'run_id',v_run_id,'employee_count',v_count,'total_amount',v_total);
exception when unique_violation then return jsonb_build_object('success',false,'error','La nómina contiene cédulas duplicadas.');
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

grant execute on function public.import_hr_payroll_run(text,integer,integer,text,jsonb),public.list_hr_payroll_runs(text,integer,integer) to anon,authenticated;
