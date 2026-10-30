-- Base operativa de la Dirección Comercial.
create sequence if not exists public.commercial_invoice_number_seq;
create sequence if not exists public.commercial_receipt_number_seq;
create sequence if not exists public.commercial_operation_code_seq;
create sequence if not exists public.commercial_work_order_code_seq;

create table if not exists public.commercial_customers(
 id uuid primary key default gen_random_uuid(), account_code text not null unique,
 full_name text not null, document_number text not null default '', phone text not null default '',
 address text not null default '', sector text not null default '', status text not null default 'Activo' check(status in ('Activo','Suspendido','Inactivo')),
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.commercial_customers add column if not exists customer_category text not null default 'Residencial';
alter table public.commercial_customers add column if not exists latitude numeric(10,7);
alter table public.commercial_customers add column if not exists longitude numeric(10,7);
alter table public.commercial_customers add column if not exists contract_date date not null default current_date;
alter table public.commercial_customers add column if not exists metering_status text not null default 'No medido' check(metering_status in ('Medido','No medido'));
alter table public.commercial_customers add column if not exists municipality text not null default '';
alter table public.commercial_customers add column if not exists district text not null default '';

create table if not exists public.commercial_meters(
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.commercial_customers(id),
 meter_number text not null unique, latitude numeric(10,7), longitude numeric(10,7),
 status text not null default 'Activo' check(status in ('Activo','Inactivo','Retirado')),
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.commercial_meter_readings(
 id uuid primary key default gen_random_uuid(), meter_id uuid not null references public.commercial_meters(id),
 reading_date date not null default current_date, reading_value numeric(18,3) not null check(reading_value>=0),
 applied_to_billing boolean not null default false, notes text not null default '',
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(),
 unique(meter_id,reading_date)
);
create table if not exists public.commercial_cut_reconnection_orders(
 id uuid primary key default gen_random_uuid(), code text not null unique,
 customer_id uuid not null references public.commercial_customers(id), meter_id uuid references public.commercial_meters(id),
 order_type text not null check(order_type in ('Corte','Reconexión')), reason text not null,
 status text not null default 'Solicitada' check(status in ('Solicitada','Asignada','Realizada','Cancelada')),
 requested_by_unit text not null default 'Micro-Medición', completed_at timestamptz,
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.commercial_invoices(
 id uuid primary key default gen_random_uuid(), invoice_number text not null unique,
 customer_id uuid not null references public.commercial_customers(id), billing_period date not null,
 amount numeric(18,2) not null check(amount>=0), due_date date not null,
 status text not null default 'Pendiente' check(status in ('Pendiente','Parcial','Pagada','Vencida','Anulada')),
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.commercial_payments(
 id uuid primary key default gen_random_uuid(), receipt_number text not null unique,
 customer_id uuid not null references public.commercial_customers(id), invoice_id uuid references public.commercial_invoices(id),
 amount numeric(18,2) not null check(amount>0), payment_date date not null default current_date,
 channel text not null default 'Caja', reference text not null default '',
 created_by uuid not null references public.app_users(id), created_at timestamptz not null default now()
);
create table if not exists public.commercial_service_requests(
 id uuid primary key default gen_random_uuid(), code text not null unique,
 customer_id uuid not null references public.commercial_customers(id), category text not null,
 description text not null, status text not null default 'Registrada' check(status in ('Registrada','En proceso','Resuelta','Cerrada')),
 assigned_unit text not null default 'Atención al Cliente', created_by uuid not null references public.app_users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.commercial_service_requests add column if not exists service_channel text not null default 'Presencial';
alter table public.commercial_service_requests add column if not exists zone text not null default '';
create index if not exists commercial_invoices_customer_idx on public.commercial_invoices(customer_id,billing_period desc);
create index if not exists commercial_payments_customer_idx on public.commercial_payments(customer_id,payment_date desc);
create index if not exists commercial_requests_customer_idx on public.commercial_service_requests(customer_id,created_at desc);
create index if not exists commercial_meters_customer_idx on public.commercial_meters(customer_id);
create index if not exists commercial_readings_meter_idx on public.commercial_meter_readings(meter_id,reading_date desc);
create index if not exists commercial_orders_customer_idx on public.commercial_cut_reconnection_orders(customer_id,created_at desc);
alter table public.commercial_customers enable row level security;
alter table public.commercial_invoices enable row level security;
alter table public.commercial_payments enable row level security;
alter table public.commercial_service_requests enable row level security;
alter table public.commercial_meters enable row level security;
alter table public.commercial_meter_readings enable row level security;
alter table public.commercial_cut_reconnection_orders enable row level security;
revoke all on public.commercial_customers,public.commercial_invoices,public.commercial_payments,public.commercial_service_requests,public.commercial_meters,public.commercial_meter_readings,public.commercial_cut_reconnection_orders from anon,authenticated;

create or replace function public.list_commercial_dashboard(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_customers jsonb;v_invoices jsonb;v_payments jsonb;v_requests jsonb;v_meters jsonb;v_readings jsonb;v_orders jsonb;v_hr_employees jsonb;v_hr_vacancies jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_gestion_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar Gestión Comercial.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_customers from(select c.*,(select coalesce(sum(i.amount),0)-coalesce(sum((select coalesce(sum(p.amount),0) from public.commercial_payments p where p.invoice_id=i.id)),0) from public.commercial_invoices i where i.customer_id=c.id and i.status<>'Anulada') balance from public.commercial_customers c)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_invoices from(select i.*,c.account_code,c.full_name customer_name,c.customer_category,c.metering_status,coalesce((select sum(p.amount) from public.commercial_payments p where p.invoice_id=i.id),0) paid_amount from public.commercial_invoices i join public.commercial_customers c on c.id=i.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_payments from(select p.*,c.account_code,c.full_name customer_name from public.commercial_payments p join public.commercial_customers c on c.id=p.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_requests from(select r.*,c.account_code,c.full_name customer_name from public.commercial_service_requests r join public.commercial_customers c on c.id=r.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_meters from(select m.*,c.account_code,c.full_name customer_name,c.municipality,c.district,c.sector,(select mr.reading_value from public.commercial_meter_readings mr where mr.meter_id=m.id order by mr.reading_date desc limit 1) last_reading,(select mr.reading_date from public.commercial_meter_readings mr where mr.meter_id=m.id order by mr.reading_date desc limit 1) last_reading_date from public.commercial_meters m join public.commercial_customers c on c.id=m.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.reading_date desc),'[]'::jsonb) into v_readings from(select r.*,m.meter_number,c.full_name customer_name,c.account_code from public.commercial_meter_readings r join public.commercial_meters m on m.id=r.meter_id join public.commercial_customers c on c.id=m.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_orders from(select o.*,c.account_code,c.full_name customer_name,m.meter_number from public.commercial_cut_reconnection_orders o join public.commercial_customers c on c.id=o.customer_id left join public.commercial_meters m on m.id=o.meter_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.department_name,x.section_name,x.full_name),'[]'::jsonb) into v_hr_employees from(
  select e.id,e.employee_code,e.full_name,e.position_name,e.employment_status,e.direction_name,e.department_name,e.division_name,e.section_name,e.center_name,
   count(c.id) filter(where c.case_type='PERMISO' and c.status not in('RECHAZADO','ANULADA'))::integer permission_count,
   exists(select 1 from public.hr_employee_cases m where m.employee_id=e.id and m.case_type='PERMISO' and m.status in('SOLICITADO','APROBADO') and current_date between m.start_date and m.end_date and (lower(m.category) like '%médic%' or lower(m.category) like '%medic%' or lower(m.category) like '%licencia%' or lower(m.category) like '%enfermedad%')) medical_leave_active,
   exists(select 1 from public.hr_employee_cases va where va.employee_id=e.id and va.case_type='VACACION' and va.status in('SOLICITADO','APROBADO') and current_date between va.start_date and va.end_date) vacation_active
  from public.hr_employees e left join public.hr_employee_cases c on c.employee_id=e.id
  where e.employment_status<>'Desvinculado' and lower(trim(e.direction_name)) in('dirección comercial','direccion comercial')
  group by e.id
 )x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.department_name,x.section_name,x.position_name),'[]'::jsonb) into v_hr_vacancies from(
  select v.id,v.position_name,v.direction_name,v.department_name,v.division_name,v.section_name,v.center_name,v.status,v.available_from,v.monthly_amount,
   coalesce(e.full_name,'Plaza de nueva creación') previous_employee_name
  from public.hr_vacancies v left join public.hr_employees e on e.id=v.source_employee_id
  where v.status in('VACANTE','CON_RECLUTAMIENTO') and lower(trim(v.direction_name)) in('dirección comercial','direccion comercial')
 )x;
 return jsonb_build_object('success',true,'customers',v_customers,'invoices',v_invoices,'payments',v_payments,'requests',v_requests,'meters',v_meters,'readings',v_readings,'orders',v_orders,'commercial_employees',v_hr_employees,'commercial_vacancies',v_hr_vacancies);
end $$;

create or replace function public.manage_commercial_record(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_id uuid;v_customer uuid;v_invoice uuid;v_total numeric;v_paid numeric;v_code text;v_previous jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'gestionar_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar operaciones comerciales.');end if;
 if p_action='CUSTOMER' then
  insert into public.commercial_customers(account_code,full_name,document_number,phone,address,municipality,district,sector,customer_category,metering_status,latitude,longitude,contract_date,created_by) values(trim(p_data->>'account_code'),trim(p_data->>'full_name'),coalesce(p_data->>'document_number',''),coalesce(p_data->>'phone',''),coalesce(p_data->>'address',''),coalesce(p_data->>'municipality',''),coalesce(p_data->>'district',''),coalesce(p_data->>'sector',''),coalesce(nullif(p_data->>'customer_category',''),'Residencial'),coalesce(nullif(p_data->>'metering_status',''),'No medido'),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,coalesce(nullif(p_data->>'contract_date','')::date,current_date),v_user.id) returning id into v_id;
 elsif p_action='UPDATE_CUSTOMER' then
  select to_jsonb(c),c.id into v_previous,v_id from public.commercial_customers c where c.id=(p_data->>'id')::uuid for update;
  if v_id is null then return jsonb_build_object('success',false,'error','No se encontró el cliente que desea modificar.');end if;
  update public.commercial_customers set account_code=trim(p_data->>'account_code'),full_name=trim(p_data->>'full_name'),document_number=coalesce(p_data->>'document_number',''),phone=coalesce(p_data->>'phone',''),address=coalesce(p_data->>'address',''),municipality=coalesce(p_data->>'municipality',''),district=coalesce(p_data->>'district',''),sector=coalesce(p_data->>'sector',''),customer_category=coalesce(nullif(p_data->>'customer_category',''),'Residencial'),metering_status=coalesce(nullif(p_data->>'metering_status',''),'No medido'),latitude=nullif(p_data->>'latitude','')::numeric,longitude=nullif(p_data->>'longitude','')::numeric,contract_date=coalesce(nullif(p_data->>'contract_date','')::date,contract_date),status=coalesce(nullif(p_data->>'status',''),status),updated_at=now() where id=v_id;
  insert into public.commercial_contract_history(customer_id,action_type,previous_value,new_value,reason,created_by) select v_id,'MODIFICACION_CLIENTE',v_previous,to_jsonb(c),coalesce(p_data->>'reason','Actualización desde Catastro de Usuarios'),v_user.id from public.commercial_customers c where c.id=v_id;
 elsif p_action='INVOICE' then
  v_code:='FAC-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_invoice_number_seq')::text,6,'0');
  insert into public.commercial_invoices(invoice_number,customer_id,billing_period,amount,due_date,created_by) values(v_code,(p_data->>'customer_id')::uuid,((p_data->>'billing_period')||'-01')::date,(p_data->>'amount')::numeric,(p_data->>'due_date')::date,v_user.id) returning id into v_id;
 elsif p_action='PAYMENT' then
  v_customer:=(p_data->>'customer_id')::uuid;v_invoice:=nullif(p_data->>'invoice_id','')::uuid;
  v_code:='REC-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_receipt_number_seq')::text,6,'0');
  insert into public.commercial_payments(receipt_number,customer_id,invoice_id,amount,payment_date,channel,reference,created_by) values(v_code,v_customer,v_invoice,(p_data->>'amount')::numeric,coalesce(nullif(p_data->>'payment_date','')::date,current_date),coalesce(p_data->>'channel','Caja'),coalesce(p_data->>'reference',''),v_user.id) returning id into v_id;
  if v_invoice is not null then select amount,coalesce((select sum(amount) from public.commercial_payments where invoice_id=v_invoice),0) into v_total,v_paid from public.commercial_invoices where id=v_invoice;update public.commercial_invoices set status=case when v_paid>=v_total then 'Pagada' when v_paid>0 then 'Parcial' else status end,updated_at=now() where id=v_invoice;end if;
 elsif p_action='REQUEST' then
  v_code:='OP-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0');
  insert into public.commercial_service_requests(code,customer_id,category,description,assigned_unit,service_channel,zone,created_by) values(v_code,(p_data->>'customer_id')::uuid,trim(p_data->>'category'),trim(p_data->>'description'),coalesce(p_data->>'assigned_unit','Centro de Servicio al Cliente'),coalesce(p_data->>'service_channel','Presencial'),coalesce(p_data->>'zone',''),v_user.id) returning id into v_id;
 elsif p_action='METER' then
  insert into public.commercial_meters(customer_id,meter_number,latitude,longitude,created_by) values((p_data->>'customer_id')::uuid,trim(p_data->>'meter_number'),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,v_user.id) returning id into v_id;
  update public.commercial_customers set metering_status='Medido',updated_at=now() where id=(p_data->>'customer_id')::uuid;
 elsif p_action='READING' then
  insert into public.commercial_meter_readings(meter_id,reading_date,reading_value,applied_to_billing,notes,created_by) values((p_data->>'meter_id')::uuid,coalesce(nullif(p_data->>'reading_date','')::date,current_date),(p_data->>'reading_value')::numeric,coalesce((p_data->>'applied_to_billing')::boolean,false),coalesce(p_data->>'notes',''),v_user.id) returning id into v_id;
 elsif p_action='CUT_ORDER' then
  v_code:='OCR-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_work_order_code_seq')::text,6,'0');
  insert into public.commercial_cut_reconnection_orders(code,customer_id,meter_id,order_type,reason,requested_by_unit,created_by) values(v_code,(p_data->>'customer_id')::uuid,nullif(p_data->>'meter_id','')::uuid,p_data->>'order_type',trim(p_data->>'reason'),coalesce(p_data->>'requested_by_unit','Micro-Medición'),v_user.id) returning id into v_id;
 elsif p_action='COMPLETE_CUT_ORDER' then
  update public.commercial_cut_reconnection_orders set status='Realizada',completed_at=now(),updated_at=now() where id=(p_data->>'id')::uuid returning id,code into v_id,v_code;
 else return jsonb_build_object('success',false,'error','Operación comercial no reconocida.');end if;
 return jsonb_build_object('success',true,'id',v_id,'code',v_code);
exception when unique_violation then return jsonb_build_object('success',false,'error','El código indicado ya se encuentra registrado.');when others then return jsonb_build_object('success',false,'error',sqlerrm);end $$;
grant execute on function public.list_commercial_dashboard(text),public.manage_commercial_record(text,text,jsonb) to anon,authenticated;
