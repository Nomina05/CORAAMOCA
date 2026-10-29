-- Gestión Comercial integral: ampliación operativa de las 25 mejoras.
-- Ejecutar después de commercial_management.sql.

alter table public.commercial_customers
 add column if not exists owner_type text not null default 'Titular',
 add column if not exists municipality text not null default '',
 add column if not exists district text not null default '',
 add column if not exists route_code text not null default '',
 add column if not exists tariff_code text not null default '',
 add column if not exists contract_status text not null default 'Activo',
 add column if not exists service_status text not null default 'Conectado',
 add column if not exists risk_level text not null default 'Normal';
alter table public.commercial_meters
 add column if not exists brand text not null default '',add column if not exists model text not null default '',add column if not exists diameter text not null default '',
 add column if not exists capacity text not null default '',add column if not exists installation_date date,add column if not exists initial_reading numeric(18,3) not null default 0,
 add column if not exists photo_url text not null default '',add column if not exists replacement_meter_id uuid references public.commercial_meters(id);
alter table public.commercial_invoices
 add column if not exists fixed_charge numeric(18,2) not null default 0,add column if not exists consumption_charge numeric(18,2) not null default 0,
 add column if not exists late_fee numeric(18,2) not null default 0,add column if not exists discount numeric(18,2) not null default 0,
 add column if not exists estimated boolean not null default false,add column if not exists approved_by uuid references public.app_users(id),add column if not exists void_reason text not null default '';
alter table public.commercial_service_requests
 add column if not exists priority text not null default 'Media',add column if not exists due_at timestamptz,add column if not exists resolved_at timestamptz,
 add column if not exists satisfaction_score integer,add column if not exists response_text text not null default '';
alter table public.commercial_cut_reconnection_orders
 add column if not exists brigade_id uuid,add column if not exists latitude numeric(10,7),add column if not exists longitude numeric(10,7),
 add column if not exists before_photo_url text not null default '',add column if not exists after_photo_url text not null default '',add column if not exists execution_note text not null default '';

create table if not exists public.commercial_customer_documents(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.commercial_customers(id) on delete cascade,document_type text not null,file_name text not null,storage_path text not null,notes text not null default '',uploaded_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_contract_history(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.commercial_customers(id) on delete cascade,action_type text not null,previous_value jsonb,new_value jsonb,reason text not null default '',approved_by uuid references public.app_users(id),created_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_tariffs(id uuid primary key default gen_random_uuid(),tariff_code text not null unique,tariff_name text not null,category text not null,fixed_charge numeric(18,2) not null default 0,unit_price numeric(18,4) not null default 0,minimum_consumption numeric(18,3) not null default 0,active boolean not null default true,created_at timestamptz not null default now());
create table if not exists public.commercial_billing_cycles(id uuid primary key default gen_random_uuid(),cycle_code text not null unique,cycle_name text not null,reading_day integer not null check(reading_day between 1 and 28),billing_day integer not null check(billing_day between 1 and 28),due_days integer not null default 20,active boolean not null default true);
create table if not exists public.commercial_reading_routes(id uuid primary key default gen_random_uuid(),route_code text not null unique,route_name text not null,municipality text not null,sector text not null,assigned_employee_id uuid references public.hr_employees(id),scheduled_date date,status text not null default 'PLANIFICADA',total_customers integer not null default 0,completed_customers integer not null default 0,created_at timestamptz not null default now());
create table if not exists public.commercial_reading_incidents(id uuid primary key default gen_random_uuid(),route_id uuid references public.commercial_reading_routes(id),meter_id uuid references public.commercial_meters(id),incident_type text not null,description text not null,photo_url text not null default '',latitude numeric(10,7),longitude numeric(10,7),resolved boolean not null default false,created_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_credit_debit_notes(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.commercial_customers(id),invoice_id uuid references public.commercial_invoices(id),note_number text not null unique,note_type text not null check(note_type in('CREDITO','DEBITO')),amount numeric(18,2) not null check(amount>0),reason text not null,status text not null default 'PENDIENTE',approved_by uuid references public.app_users(id),created_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_cash_registers(id uuid primary key default gen_random_uuid(),cashier_user_id uuid not null references public.app_users(id),opened_at timestamptz not null default now(),opening_amount numeric(18,2) not null default 0,closed_at timestamptz,expected_amount numeric(18,2),counted_amount numeric(18,2),difference_amount numeric(18,2),status text not null default 'ABIERTA',created_at timestamptz not null default now());
create table if not exists public.commercial_payment_agreements(id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.commercial_customers(id),agreement_number text not null unique,total_debt numeric(18,2) not null,initial_payment numeric(18,2) not null default 0,installment_amount numeric(18,2) not null,installment_count integer not null,next_due_date date,status text not null default 'ACTIVO',broken_at timestamptz,approved_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_brigades(id uuid primary key default gen_random_uuid(),brigade_code text not null unique,brigade_name text not null,supervisor_employee_id uuid references public.hr_employees(id),vehicle text not null default '',zone text not null default '',active boolean not null default true,created_at timestamptz not null default now());
alter table public.commercial_cut_reconnection_orders drop constraint if exists commercial_cut_reconnection_orders_brigade_id_fkey;
alter table public.commercial_cut_reconnection_orders add constraint commercial_cut_reconnection_orders_brigade_id_fkey foreign key(brigade_id) references public.commercial_brigades(id);
create table if not exists public.commercial_faults(id uuid primary key default gen_random_uuid(),fault_code text not null unique,customer_id uuid references public.commercial_customers(id),fault_type text not null,description text not null,zone text not null,latitude numeric(10,7),longitude numeric(10,7),priority text not null default 'Media',status text not null default 'REPORTADA',brigade_id uuid references public.commercial_brigades(id),affected_customers integer not null default 0,reported_at timestamptz not null default now(),resolved_at timestamptz,created_by uuid references public.app_users(id));
create table if not exists public.commercial_workflow_requests(id uuid primary key default gen_random_uuid(),entity_type text not null,entity_id uuid not null,action_type text not null,status text not null default 'REGISTRADA',requested_by uuid references public.app_users(id),reviewed_by uuid references public.app_users(id),approved_by uuid references public.app_users(id),observation text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.commercial_data_quality_issues(id uuid primary key default gen_random_uuid(),customer_id uuid references public.commercial_customers(id),meter_id uuid references public.commercial_meters(id),issue_code text not null,severity text not null,description text not null,status text not null default 'ABIERTA',detected_at timestamptz not null default now(),resolved_at timestamptz,resolved_by uuid references public.app_users(id));
create table if not exists public.commercial_accounting_batches(id uuid primary key default gen_random_uuid(),batch_date date not null,source_type text not null,total_amount numeric(18,2) not null,status text not null default 'BORRADOR',account_code text not null,bank_reference text not null default '',approved_by uuid references public.app_users(id),created_at timestamptz not null default now());
create table if not exists public.commercial_mobile_sync_queue(id uuid primary key default gen_random_uuid(),device_id text not null,employee_id uuid references public.hr_employees(id),operation_type text not null,payload jsonb not null,status text not null default 'PENDIENTE',attempts integer not null default 0,last_error text not null default '',created_at timestamptz not null default now(),synced_at timestamptz);
create table if not exists public.commercial_import_batches(id uuid primary key default gen_random_uuid(),source_name text not null,source_hash text not null unique,total_rows integer not null default 0,valid_rows integer not null default 0,rejected_rows integer not null default 0,status text not null default 'VALIDANDO',validation_result jsonb not null default '{}'::jsonb,created_by uuid references public.app_users(id),created_at timestamptz not null default now(),applied_at timestamptz);

do $$declare t text;begin foreach t in array array['commercial_customer_documents','commercial_contract_history','commercial_tariffs','commercial_billing_cycles','commercial_reading_routes','commercial_reading_incidents','commercial_credit_debit_notes','commercial_cash_registers','commercial_payment_agreements','commercial_brigades','commercial_faults','commercial_workflow_requests','commercial_data_quality_issues','commercial_accounting_batches','commercial_mobile_sync_queue','commercial_import_batches'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);end loop;end$$;

insert into public.commercial_tariffs(tariff_code,tariff_name,category,fixed_charge,unit_price,minimum_consumption) values
('RES-01','Residencial','Residencial',150,12,10),('COM-01','Comercial','Comercial',350,20,15),('IND-01','Industrial','Industrial',850,28,30),('OFI-01','Oficial','Oficial',0,15,10)
on conflict(tariff_code) do nothing;
insert into public.commercial_billing_cycles(cycle_code,cycle_name,reading_day,billing_day,due_days) values('CICLO-01','Ciclo general',20,25,20) on conflict(cycle_code) do nothing;

create or replace function public.list_commercial_advanced(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;result jsonb;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'ver_gestion_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 insert into public.commercial_data_quality_issues(customer_id,issue_code,severity,description)
 select c.id,'SIN_GEOREFERENCIA','MEDIA','Cliente sin coordenadas geográficas' from public.commercial_customers c where (c.latitude is null or c.longitude is null) and not exists(select 1 from public.commercial_data_quality_issues q where q.customer_id=c.id and q.issue_code='SIN_GEOREFERENCIA' and q.status='ABIERTA');
 select jsonb_build_object('success',true,
  'routes',(select coalesce(jsonb_agg(to_jsonb(x) order by scheduled_date desc),'[]'::jsonb) from(select r.*,e.full_name reader_name from public.commercial_reading_routes r left join public.hr_employees e on e.id=r.assigned_employee_id)x),
  'agreements',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]'::jsonb) from(select a.*,c.full_name customer_name,c.account_code from public.commercial_payment_agreements a join public.commercial_customers c on c.id=a.customer_id)x),
  'brigades',(select coalesce(jsonb_agg(to_jsonb(x) order by brigade_name),'[]'::jsonb) from(select b.*,e.full_name supervisor_name from public.commercial_brigades b left join public.hr_employees e on e.id=b.supervisor_employee_id)x),
  'faults',(select coalesce(jsonb_agg(to_jsonb(f) order by reported_at desc),'[]'::jsonb) from public.commercial_faults f),
  'qualityIssues',(select coalesce(jsonb_agg(to_jsonb(q) order by detected_at desc),'[]'::jsonb) from public.commercial_data_quality_issues q where q.status='ABIERTA'),
  'workflows',(select coalesce(jsonb_agg(to_jsonb(w) order by created_at desc),'[]'::jsonb) from public.commercial_workflow_requests w),
  'tariffs',(select coalesce(jsonb_agg(to_jsonb(t) order by tariff_name),'[]'::jsonb) from public.commercial_tariffs t where t.active),
  'metrics',jsonb_build_object(
   'activeCustomers',(select count(*) from public.commercial_customers where status='Activo'),
   'newContracts',(select count(*) from public.commercial_customers where contract_date>=date_trunc('month',current_date)),
   'billed',(select coalesce(sum(amount),0) from public.commercial_invoices where billing_period>=date_trunc('month',current_date)),
   'collected',(select coalesce(sum(amount),0) from public.commercial_payments where payment_date>=date_trunc('month',current_date)),
   'overdue',(select coalesce(sum(amount-(select coalesce(sum(p.amount),0) from public.commercial_payments p where p.invoice_id=i.id)),0) from public.commercial_invoices i where status in('Pendiente','Parcial','Vencida') and due_date<current_date),
   'completedReadings',(select count(*) from public.commercial_meter_readings where reading_date>=date_trunc('month',current_date)),
   'estimatedInvoices',(select count(*) from public.commercial_invoices where estimated and billing_period>=date_trunc('month',current_date)),
   'openOrders',(select count(*) from public.commercial_cut_reconnection_orders where status not in('Realizada','Cancelada')),
   'openRequests',(select count(*) from public.commercial_service_requests where status not in('Resuelta','Cerrada')),
   'openFaults',(select count(*) from public.commercial_faults where status<>'RESUELTA')
  )
 ) into result;return result;
end$$;

create or replace function public.manage_commercial_advanced(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;new_id uuid;code text;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'gestionar_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 if p_action='CREATE_ROUTE' then insert into public.commercial_reading_routes(route_code,route_name,municipality,sector,assigned_employee_id,scheduled_date,total_customers) values(p_data->>'route_code',p_data->>'route_name',p_data->>'municipality',p_data->>'sector',nullif(p_data->>'employee_id','')::uuid,nullif(p_data->>'scheduled_date','')::date,coalesce(nullif(p_data->>'total_customers','')::integer,0)) returning id into new_id;
 elsif p_action='CREATE_AGREEMENT' then code='AC-'||extract(year from current_date)::int||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0');insert into public.commercial_payment_agreements(customer_id,agreement_number,total_debt,initial_payment,installment_amount,installment_count,next_due_date,approved_by) values((p_data->>'customer_id')::uuid,code,(p_data->>'total_debt')::numeric,coalesce(nullif(p_data->>'initial_payment','')::numeric,0),(p_data->>'installment_amount')::numeric,(p_data->>'installment_count')::integer,(p_data->>'next_due_date')::date,u.id) returning id into new_id;
 elsif p_action='CREATE_BRIGADE' then insert into public.commercial_brigades(brigade_code,brigade_name,supervisor_employee_id,vehicle,zone) values(p_data->>'brigade_code',p_data->>'brigade_name',nullif(p_data->>'employee_id','')::uuid,coalesce(p_data->>'vehicle',''),coalesce(p_data->>'zone','')) returning id into new_id;
 elsif p_action='CREATE_FAULT' then code='AVE-'||extract(year from current_date)::int||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0');insert into public.commercial_faults(fault_code,customer_id,fault_type,description,zone,latitude,longitude,priority,affected_customers,created_by) values(code,nullif(p_data->>'customer_id','')::uuid,p_data->>'fault_type',p_data->>'description',p_data->>'zone',nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,coalesce(p_data->>'priority','Media'),coalesce(nullif(p_data->>'affected_customers','')::integer,0),u.id) returning id into new_id;
 elsif p_action='START_WORKFLOW' then insert into public.commercial_workflow_requests(entity_type,entity_id,action_type,requested_by,observation) values(p_data->>'entity_type',(p_data->>'entity_id')::uuid,p_data->>'action_type',u.id,coalesce(p_data->>'observation','')) returning id into new_id;
 else return jsonb_build_object('success',false,'error','Acción comercial avanzada no reconocida.');end if;
 return jsonb_build_object('success',true,'id',new_id,'code',code);
exception when others then return jsonb_build_object('success',false,'error',sqlerrm);end$$;

grant execute on function public.list_commercial_advanced(text),public.manage_commercial_advanced(text,text,jsonb) to anon,authenticated;
