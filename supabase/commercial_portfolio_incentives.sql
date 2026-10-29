-- Carteras, rutas, metas, morosidad e incentivos de la Dirección Comercial.
-- Ejecutar después de commercial_advanced_25.sql.

alter table public.commercial_payments
 add column if not exists managed_by_employee_id uuid references public.hr_employees(id),
 add column if not exists collection_type text not null default 'CORRIENTE',
 add column if not exists management_reference text not null default '';

create table if not exists public.commercial_portfolios(
 id uuid primary key default gen_random_uuid(),portfolio_code text not null unique,portfolio_name text not null,
 employee_id uuid not null references public.hr_employees(id),route_id uuid references public.commercial_reading_routes(id),
 service_center text not null default '',municipality text not null default '',district text not null default '',sector text not null default '',
 start_date date not null default current_date,end_date date,status text not null default 'ACTIVA',
 created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.commercial_portfolio_customers(
 id uuid primary key default gen_random_uuid(),portfolio_id uuid not null references public.commercial_portfolios(id) on delete cascade,
 customer_id uuid not null references public.commercial_customers(id),assigned_from date not null default current_date,assigned_until date,
 status text not null default 'ACTIVO',transfer_reason text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now()
);
create unique index if not exists commercial_portfolio_customer_active_uq on public.commercial_portfolio_customers(customer_id) where status='ACTIVO';

create table if not exists public.commercial_collection_targets(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),portfolio_id uuid references public.commercial_portfolios(id),
 target_year integer not null,target_month integer not null check(target_month between 1 and 12),billing_target numeric(18,2) not null default 0,
 collection_target numeric(18,2) not null default 0,delinquency_target numeric(18,2) not null default 0,visit_target integer not null default 0,
 minimum_effectiveness numeric(8,2) not null default 80,status text not null default 'CONFIGURADA',
 reviewed_by uuid references public.app_users(id),approved_by uuid references public.app_users(id),created_by uuid references public.app_users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(employee_id,portfolio_id,target_year,target_month)
);

create table if not exists public.commercial_collection_actions(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.commercial_customers(id),
 employee_id uuid not null references public.hr_employees(id),portfolio_id uuid references public.commercial_portfolios(id),
 action_type text not null,action_date timestamptz not null default now(),result text not null,next_follow_up date,
 promised_amount numeric(18,2) not null default 0,promise_date date,evidence_url text not null default '',latitude numeric(10,7),longitude numeric(10,7),
 status text not null default 'REGISTRADA',created_by uuid references public.app_users(id),created_at timestamptz not null default now()
);

create table if not exists public.commercial_incentive_rules(
 id uuid primary key default gen_random_uuid(),rule_name text not null,min_effectiveness numeric(8,2) not null,max_effectiveness numeric(8,2),
 incentive_percent numeric(8,4) not null default 0,delinquency_bonus_percent numeric(8,4) not null default 0,maximum_amount numeric(18,2),
 effective_from date not null,effective_until date,active boolean not null default true,created_by uuid references public.app_users(id),created_at timestamptz not null default now()
);
create unique index if not exists commercial_incentive_rule_range_uq on public.commercial_incentive_rules(min_effectiveness,coalesce(max_effectiveness,-1),effective_from);
insert into public.commercial_incentive_rules(rule_name,min_effectiveness,max_effectiveness,incentive_percent,delinquency_bonus_percent,effective_from) values
('Cumplimiento 80 a 89.99',80,89.99,2,0.50,current_date),('Cumplimiento 90 a 99.99',90,99.99,3,0.75,current_date),
('Cumplimiento 100 a 109.99',100,109.99,4,1,current_date),('Cumplimiento desde 110',110,null,5,1.25,current_date)
on conflict do nothing;

create table if not exists public.commercial_incentive_calculations(
 id uuid primary key default gen_random_uuid(),target_id uuid not null unique references public.commercial_collection_targets(id),
 employee_id uuid not null references public.hr_employees(id),target_year integer not null,target_month integer not null,
 current_collected numeric(18,2) not null default 0,delinquent_collected numeric(18,2) not null default 0,total_collected numeric(18,2) not null default 0,
 effectiveness numeric(8,2) not null default 0,base_percent numeric(8,4) not null default 0,bonus_percent numeric(8,4) not null default 0,
 gross_incentive numeric(18,2) not null default 0,retention_amount numeric(18,2) not null default 0,net_incentive numeric(18,2) not null default 0,
 status text not null default 'CALCULADA',reviewed_by uuid references public.app_users(id),approved_by uuid references public.app_users(id),
 applied_by uuid references public.app_users(id),reviewed_at timestamptz,approved_at timestamptz,applied_at timestamptz,
 observation text not null default '',calculation_snapshot jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.commercial_incentive_payroll_novelties(
 id uuid primary key default gen_random_uuid(),calculation_id uuid not null unique references public.commercial_incentive_calculations(id),
 employee_id uuid not null references public.hr_employees(id),payroll_year integer not null,payroll_month integer not null,
 novelty_type text not null default 'INCENTIVO_RECAUDACION',amount numeric(18,2) not null,status text not null default 'PENDIENTE_NOMINA',
 account_code text not null default '',execution_fund text not null default '30',program integer not null default 1,subproduct integer not null default 0,activity integer not null default 1,
 created_at timestamptz not null default now(),applied_at timestamptz
);

do $$declare t text;begin foreach t in array array['commercial_portfolios','commercial_portfolio_customers','commercial_collection_targets','commercial_collection_actions','commercial_incentive_rules','commercial_incentive_calculations','commercial_incentive_payroll_novelties'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);end loop;end$$;

create or replace function public.list_commercial_portfolio_management(p_token text,p_year integer default extract(year from current_date)::integer,p_month integer default extract(month from current_date)::integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'ver_carteras_comercial')::boolean,false) and not coalesce((u.permissions->>'ver_gestion_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No autorizado para consultar carteras comerciales.');end if;
 return jsonb_build_object('success',true,
  'portfolios',coalesce((select jsonb_agg(to_jsonb(x) order by employee_name,portfolio_name) from(select p.*,e.employee_code,e.full_name employee_name,e.position_name,r.route_name,(select count(*) from public.commercial_portfolio_customers pc where pc.portfolio_id=p.id and pc.status='ACTIVO') customer_count,(select coalesce(sum(i.amount),0) from public.commercial_portfolio_customers pc join public.commercial_invoices i on i.customer_id=pc.customer_id where pc.portfolio_id=p.id and pc.status='ACTIVO' and i.status<>'Anulada') portfolio_billed,(select coalesce(sum(i.amount),0)-coalesce(sum((select coalesce(sum(py.amount),0) from public.commercial_payments py where py.invoice_id=i.id)),0) from public.commercial_portfolio_customers pc join public.commercial_invoices i on i.customer_id=pc.customer_id where pc.portfolio_id=p.id and pc.status='ACTIVO' and i.status<>'Anulada') portfolio_balance from public.commercial_portfolios p join public.hr_employees e on e.id=p.employee_id left join public.commercial_reading_routes r on r.id=p.route_id)x),'[]'::jsonb),
  'assignments',coalesce((select jsonb_agg(to_jsonb(x) order by customer_name) from(select pc.*,c.account_code,c.full_name customer_name,(select coalesce(sum(i.amount),0)-coalesce(sum((select coalesce(sum(py.amount),0) from public.commercial_payments py where py.invoice_id=i.id)),0) from public.commercial_invoices i where i.customer_id=c.id and i.status<>'Anulada') balance,p.portfolio_name,e.full_name employee_name from public.commercial_portfolio_customers pc join public.commercial_customers c on c.id=pc.customer_id join public.commercial_portfolios p on p.id=pc.portfolio_id join public.hr_employees e on e.id=p.employee_id where pc.status='ACTIVO')x),'[]'::jsonb),
  'targets',coalesce((select jsonb_agg(to_jsonb(x) order by employee_name) from(select t.*,e.full_name employee_name,p.portfolio_name from public.commercial_collection_targets t join public.hr_employees e on e.id=t.employee_id left join public.commercial_portfolios p on p.id=t.portfolio_id where t.target_year=p_year and t.target_month=p_month)x),'[]'::jsonb),
  'actions',coalesce((select jsonb_agg(to_jsonb(x) order by action_date desc) from(select a.*,c.account_code,c.full_name customer_name,e.full_name employee_name from public.commercial_collection_actions a join public.commercial_customers c on c.id=a.customer_id join public.hr_employees e on e.id=a.employee_id where extract(year from a.action_date)=p_year and extract(month from a.action_date)=p_month)x),'[]'::jsonb),
  'incentives',coalesce((select jsonb_agg(to_jsonb(x) order by effectiveness desc) from(select i.*,e.full_name employee_name,t.collection_target,t.delinquency_target from public.commercial_incentive_calculations i join public.hr_employees e on e.id=i.employee_id join public.commercial_collection_targets t on t.id=i.target_id where i.target_year=p_year and i.target_month=p_month)x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by payment_date desc) from(select py.*,c.account_code,c.full_name customer_name,e.full_name manager_name from public.commercial_payments py join public.commercial_customers c on c.id=py.customer_id left join public.hr_employees e on e.id=py.managed_by_employee_id where extract(year from py.payment_date)=p_year and extract(month from py.payment_date)=p_month)x),'[]'::jsonb),
  'rules',coalesce((select jsonb_agg(to_jsonb(r) order by min_effectiveness) from public.commercial_incentive_rules r where r.active and r.effective_from<=make_date(p_year,p_month,1) and (r.effective_until is null or r.effective_until>=make_date(p_year,p_month,1))),'[]'::jsonb),
  'delinquentCustomers',coalesce((select jsonb_agg(to_jsonb(x) order by overdue_balance desc) from(select c.id,c.account_code,c.full_name,c.phone,c.sector,p.portfolio_name,e.full_name employee_name,coalesce(sum(i.amount-(select coalesce(sum(py.amount),0) from public.commercial_payments py where py.invoice_id=i.id)),0) overdue_balance,min(i.due_date) oldest_due_date,count(*) overdue_invoices from public.commercial_customers c join public.commercial_invoices i on i.customer_id=c.id left join public.commercial_portfolio_customers pc on pc.customer_id=c.id and pc.status='ACTIVO' left join public.commercial_portfolios p on p.id=pc.portfolio_id left join public.hr_employees e on e.id=p.employee_id where i.status in('Pendiente','Parcial','Vencida') and i.due_date<current_date group by c.id,p.portfolio_name,e.full_name having coalesce(sum(i.amount-(select coalesce(sum(py.amount),0) from public.commercial_payments py where py.invoice_id=i.id)),0)>0)x),'[]'::jsonb),
  'metrics',jsonb_build_object('assignedCustomers',(select count(*) from public.commercial_portfolio_customers where status='ACTIVO'),'activePortfolios',(select count(*) from public.commercial_portfolios where status='ACTIVA'),'targetAmount',(select coalesce(sum(collection_target),0) from public.commercial_collection_targets where target_year=p_year and target_month=p_month),'collected',(select coalesce(sum(amount),0) from public.commercial_payments where extract(year from payment_date)=p_year and extract(month from payment_date)=p_month and managed_by_employee_id is not null),'delinquentCollected',(select coalesce(sum(amount),0) from public.commercial_payments where extract(year from payment_date)=p_year and extract(month from payment_date)=p_month and collection_type='MOROSIDAD'),'projectedIncentive',(select coalesce(sum(net_incentive),0) from public.commercial_incentive_calculations where target_year=p_year and target_month=p_month))
 );
end$$;

create or replace function public.manage_commercial_portfolio(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;new_id uuid;v_target public.commercial_collection_targets;v_rule public.commercial_incentive_rules;v_current numeric:=0;v_delinquent numeric:=0;v_effect numeric:=0;v_gross numeric:=0;v_retention numeric:=0;v_existing uuid;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null then return jsonb_build_object('success',false,'error','No autorizado para gestionar carteras comerciales.');end if;
 if u.role<>'Administrador' then
  if p_action in('CREATE_PORTFOLIO','ASSIGN_CUSTOMER','ATTRIBUTE_PAYMENT') and not coalesce((u.permissions->>'gestionar_carteras_comercial')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para asignar carteras y cobros.');end if;
  if p_action='CREATE_TARGET' and not coalesce((u.permissions->>'configurar_metas_comercial')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para configurar metas.');end if;
  if p_action='LOG_ACTION' and not coalesce((u.permissions->>'gestionar_morosidad_comercial')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para gestionar morosidad.');end if;
  if p_action in('CALCULATE_INCENTIVE','ADVANCE_INCENTIVE') and not coalesce((u.permissions->>'aprobar_incentivos_comercial')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para calcular o aprobar incentivos.');end if;
 end if;
 if p_action='CREATE_PORTFOLIO' then insert into public.commercial_portfolios(portfolio_code,portfolio_name,employee_id,route_id,service_center,municipality,district,sector,start_date,created_by) values(p_data->>'portfolio_code',p_data->>'portfolio_name',(p_data->>'employee_id')::uuid,nullif(p_data->>'route_id','')::uuid,coalesce(p_data->>'service_center',''),coalesce(p_data->>'municipality',''),coalesce(p_data->>'district',''),coalesce(p_data->>'sector',''),coalesce(nullif(p_data->>'start_date','')::date,current_date),u.id) returning id into new_id;
 elsif p_action='ASSIGN_CUSTOMER' then update public.commercial_portfolio_customers set status='TRANSFERIDO',assigned_until=current_date,transfer_reason=coalesce(p_data->>'reason','Reasignación') where customer_id=(p_data->>'customer_id')::uuid and status='ACTIVO';insert into public.commercial_portfolio_customers(portfolio_id,customer_id,created_by) values((p_data->>'portfolio_id')::uuid,(p_data->>'customer_id')::uuid,u.id) returning id into new_id;
 elsif p_action='CREATE_TARGET' then insert into public.commercial_collection_targets(employee_id,portfolio_id,target_year,target_month,billing_target,collection_target,delinquency_target,visit_target,minimum_effectiveness,created_by) values((p_data->>'employee_id')::uuid,nullif(p_data->>'portfolio_id','')::uuid,(p_data->>'target_year')::integer,(p_data->>'target_month')::integer,coalesce(nullif(p_data->>'billing_target','')::numeric,0),(p_data->>'collection_target')::numeric,coalesce(nullif(p_data->>'delinquency_target','')::numeric,0),coalesce(nullif(p_data->>'visit_target','')::integer,0),coalesce(nullif(p_data->>'minimum_effectiveness','')::numeric,80),u.id) on conflict(employee_id,portfolio_id,target_year,target_month) do update set billing_target=excluded.billing_target,collection_target=excluded.collection_target,delinquency_target=excluded.delinquency_target,visit_target=excluded.visit_target,minimum_effectiveness=excluded.minimum_effectiveness,status='CONFIGURADA',updated_at=now() returning id into new_id;
 elsif p_action='LOG_ACTION' then insert into public.commercial_collection_actions(customer_id,employee_id,portfolio_id,action_type,result,next_follow_up,promised_amount,promise_date,evidence_url,latitude,longitude,created_by) values((p_data->>'customer_id')::uuid,(p_data->>'employee_id')::uuid,nullif(p_data->>'portfolio_id','')::uuid,p_data->>'action_type',p_data->>'result',nullif(p_data->>'next_follow_up','')::date,coalesce(nullif(p_data->>'promised_amount','')::numeric,0),nullif(p_data->>'promise_date','')::date,coalesce(p_data->>'evidence_url',''),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,u.id) returning id into new_id;
 elsif p_action='ATTRIBUTE_PAYMENT' then update public.commercial_payments set managed_by_employee_id=(p_data->>'employee_id')::uuid,collection_type=coalesce(p_data->>'collection_type','CORRIENTE'),management_reference=coalesce(p_data->>'management_reference','') where id=(p_data->>'payment_id')::uuid returning id into new_id;
 elsif p_action='CALCULATE_INCENTIVE' then select * into v_target from public.commercial_collection_targets where id=(p_data->>'target_id')::uuid;select coalesce(sum(amount) filter(where collection_type<>'MOROSIDAD'),0),coalesce(sum(amount) filter(where collection_type='MOROSIDAD'),0) into v_current,v_delinquent from public.commercial_payments where managed_by_employee_id=v_target.employee_id and extract(year from payment_date)=v_target.target_year and extract(month from payment_date)=v_target.target_month;v_effect:=case when v_target.collection_target>0 then round(((v_current+v_delinquent)/v_target.collection_target)*100,2) else 0 end;select * into v_rule from public.commercial_incentive_rules where active and min_effectiveness<=v_effect and (max_effectiveness is null or max_effectiveness>=v_effect) order by min_effectiveness desc limit 1;v_gross:=round((v_current+v_delinquent)*coalesce(v_rule.incentive_percent,0)/100+v_delinquent*coalesce(v_rule.delinquency_bonus_percent,0)/100,2);if v_rule.maximum_amount is not null then v_gross:=least(v_gross,v_rule.maximum_amount);end if;v_retention:=coalesce(nullif(p_data->>'retention_percent','')::numeric,0)*v_gross/100;insert into public.commercial_incentive_calculations(target_id,employee_id,target_year,target_month,current_collected,delinquent_collected,total_collected,effectiveness,base_percent,bonus_percent,gross_incentive,retention_amount,net_incentive,calculation_snapshot) values(v_target.id,v_target.employee_id,v_target.target_year,v_target.target_month,v_current,v_delinquent,v_current+v_delinquent,v_effect,coalesce(v_rule.incentive_percent,0),coalesce(v_rule.delinquency_bonus_percent,0),v_gross,v_retention,v_gross-v_retention,jsonb_build_object('target',to_jsonb(v_target),'rule',to_jsonb(v_rule),'calculated_at',now())) on conflict(target_id) do update set current_collected=excluded.current_collected,delinquent_collected=excluded.delinquent_collected,total_collected=excluded.total_collected,effectiveness=excluded.effectiveness,base_percent=excluded.base_percent,bonus_percent=excluded.bonus_percent,gross_incentive=excluded.gross_incentive,retention_amount=excluded.retention_amount,net_incentive=excluded.net_incentive,status='CALCULADA',calculation_snapshot=excluded.calculation_snapshot,updated_at=now() returning id into new_id;
 elsif p_action='ADVANCE_INCENTIVE' then
  select id into v_existing from public.commercial_incentive_calculations where id=(p_data->>'id')::uuid for update;
  if p_data->>'next_status'='REVISADA' then update public.commercial_incentive_calculations set status='REVISADA',reviewed_by=u.id,reviewed_at=now(),observation=coalesce(p_data->>'observation',''),updated_at=now() where id=v_existing and status='CALCULADA' returning id into new_id;
  elsif p_data->>'next_status'='APROBADA' then update public.commercial_incentive_calculations set status='APROBADA',approved_by=u.id,approved_at=now(),observation=coalesce(p_data->>'observation',''),updated_at=now() where id=v_existing and status='REVISADA' returning id into new_id;
  elsif p_data->>'next_status'='APLICADA_NOMINA' then update public.commercial_incentive_calculations set status='APLICADA_NOMINA',applied_by=u.id,applied_at=now(),updated_at=now() where id=v_existing and status='APROBADA' returning id into new_id;
  else return jsonb_build_object('success',false,'error','Transición no permitida.');end if;
  if new_id is null then return jsonb_build_object('success',false,'error','No se puede saltar la etapa del incentivo.');end if;
  if p_data->>'next_status'='APLICADA_NOMINA' then insert into public.commercial_incentive_payroll_novelties(calculation_id,employee_id,payroll_year,payroll_month,amount) select id,employee_id,target_year,target_month,net_incentive from public.commercial_incentive_calculations where id=new_id on conflict(calculation_id) do update set amount=excluded.amount,status='PENDIENTE_NOMINA';end if;
 else return jsonb_build_object('success',false,'error','Acción no reconocida.');end if;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(u.id,'COMERCIAL_'||p_action,'Gestión Comercial',p_data||jsonb_build_object('entity_id',new_id));return jsonb_build_object('success',true,'id',new_id);
exception when others then return jsonb_build_object('success',false,'error',sqlerrm);end$$;

grant execute on function public.list_commercial_portfolio_management(text,integer,integer),public.manage_commercial_portfolio(text,text,jsonb) to anon,authenticated;
