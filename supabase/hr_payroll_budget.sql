-- Programación anual del presupuesto de nómina de Gestión Humana.
create table if not exists public.hr_payroll_budget_lines (
  id uuid primary key default gen_random_uuid(),
  budget_year integer not null check (budget_year between 2000 and 2100),
  category text not null check (category in ('NOMINAS_FIJAS','OTRAS_NOMINAS','OTRAS_REMUNERACIONES')),
  payroll_type text not null,
  execution_fund text not null,
  program integer not null default 0,
  subproduct integer not null default 0,
  activity integer not null default 0,
  monthly_amount numeric(18,2) not null check (monthly_amount >= 0),
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (budget_year,category,payroll_type,execution_fund,program,subproduct,activity)
);

create table if not exists public.hr_payroll_budget_caps (
  id uuid primary key default gen_random_uuid(),
  budget_year integer not null check (budget_year between 2000 and 2100),
  execution_fund text not null,
  monthly_cap numeric(18,2) not null check (monthly_cap >= 0),
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (budget_year,execution_fund)
);

alter table public.hr_payroll_budget_lines enable row level security;
alter table public.hr_payroll_budget_caps enable row level security;
revoke all on public.hr_payroll_budget_lines,public.hr_payroll_budget_caps from anon,authenticated;

insert into public.hr_payroll_budget_lines(budget_year,category,payroll_type,execution_fund,program,subproduct,activity,monthly_amount) values
  (2026,'NOMINAS_FIJAS','Fija','30',1,0,1,857250.00),
  (2026,'NOMINAS_FIJAS','Fija','30',1,0,2,4336105.00),
  (2026,'NOMINAS_FIJAS','Fija','30',1,0,3,20000.00),
  (2026,'NOMINAS_FIJAS','Fija','30',1,0,4,30000.00),
  (2026,'NOMINAS_FIJAS','Fija','30',11,3,1,1913989.00),
  (2026,'NOMINAS_FIJAS','Fija','30',11,3,2,455000.00),
  (2026,'NOMINAS_FIJAS','Fija','30',11,3,3,632550.00),
  (2026,'NOMINAS_FIJAS','Fija','30',12,3,1,108000.00),
  (2026,'NOMINAS_FIJAS','Fija','30',12,3,2,202000.00),
  (2026,'NOMINAS_FIJAS','Fija','30',13,2,1,363663.73),
  (2026,'NOMINAS_FIJAS','Fija','10',13,2,1,3378618.60),
  (2026,'OTRAS_NOMINAS','SUPLENCIA','30',1,0,2,10000.00),
  (2026,'OTRAS_NOMINAS','INTERINATO','30',1,0,2,150000.00),
  (2026,'OTRAS_NOMINAS','TEMPORAL','30',1,0,2,326750.00),
  (2026,'OTRAS_REMUNERACIONES','DIETA DENTRO DEL PAÍS','30',1,0,2,245000.00),
  (2026,'OTRAS_REMUNERACIONES','PRIMA DE TRANSPORTE','30',1,0,2,650000.00),
  (2026,'OTRAS_REMUNERACIONES','MILITARES','30',1,0,2,119035.00),
  (2026,'OTRAS_REMUNERACIONES','HORAS EXTRAS','30',1,0,2,40000.00)
on conflict (budget_year,category,payroll_type,execution_fund,program,subproduct,activity)
do update set monthly_amount=excluded.monthly_amount,updated_at=now();

insert into public.hr_payroll_budget_caps(budget_year,execution_fund,monthly_cap) values
  (2026,'30',11150504.77),(2026,'10',3993167.00)
on conflict (budget_year,execution_fund) do update set monthly_cap=excluded.monthly_cap,updated_at=now();

create or replace function public.list_hr_payroll_budget(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_lines jsonb; v_caps jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar el presupuesto de nómina.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.category,x.program,x.subproduct,x.activity,x.payroll_type),'[]'::jsonb) into v_lines
  from (select id,budget_year,category,payroll_type,execution_fund,program,subproduct,activity,monthly_amount,updated_at
        from public.hr_payroll_budget_lines where budget_year=p_year and active=true)x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.execution_fund),'[]'::jsonb) into v_caps
  from (select c.id,c.execution_fund,c.monthly_cap,
    coalesce((select sum(l.monthly_amount) from public.hr_payroll_budget_lines l where l.budget_year=c.budget_year and l.execution_fund=c.execution_fund and l.active=true),0) programmed_amount
    from public.hr_payroll_budget_caps c where c.budget_year=p_year)x;
  return jsonb_build_object('success',true,'year',p_year,'lines',v_lines,'caps',v_caps);
end $$;

create or replace function public.save_hr_payroll_budget_line(p_token text,p_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)=false and coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para modificar el presupuesto de nómina.'); end if;
  if coalesce((p_data->>'monthly_amount')::numeric,-1)<0 then return jsonb_build_object('success',false,'error','El monto debe ser mayor o igual a cero.'); end if;
  if p_id is null then
    insert into public.hr_payroll_budget_lines(budget_year,category,payroll_type,execution_fund,program,subproduct,activity,monthly_amount,created_by)
    values((p_data->>'budget_year')::integer,p_data->>'category',upper(trim(p_data->>'payroll_type')),trim(p_data->>'execution_fund'),(p_data->>'program')::integer,(p_data->>'subproduct')::integer,(p_data->>'activity')::integer,(p_data->>'monthly_amount')::numeric,v_user.id)
    returning id into v_id;
  else
    update public.hr_payroll_budget_lines set category=p_data->>'category',payroll_type=upper(trim(p_data->>'payroll_type')),execution_fund=trim(p_data->>'execution_fund'),program=(p_data->>'program')::integer,subproduct=(p_data->>'subproduct')::integer,activity=(p_data->>'activity')::integer,monthly_amount=(p_data->>'monthly_amount')::numeric,updated_at=now()
    where id=p_id returning id into v_id;
  end if;
  return jsonb_build_object('success',true,'id',v_id);
exception when unique_violation then return jsonb_build_object('success',false,'error','Ya existe una partida con esa clasificación.');
end $$;

create or replace function public.save_hr_payroll_budget_cap(p_token text,p_year integer,p_fund text,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para modificar topes de nómina.'); end if;
  insert into public.hr_payroll_budget_caps(budget_year,execution_fund,monthly_cap,created_by) values(p_year,trim(p_fund),p_amount,v_user.id)
  on conflict(budget_year,execution_fund) do update set monthly_cap=excluded.monthly_cap,updated_at=now();
  return jsonb_build_object('success',true);
end $$;

grant execute on function public.list_hr_payroll_budget(text,integer),public.save_hr_payroll_budget_line(text,uuid,jsonb),public.save_hr_payroll_budget_cap(text,integer,text,numeric) to anon,authenticated;
