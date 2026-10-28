-- Base operativa de la Dirección Comercial.
create sequence if not exists public.commercial_invoice_number_seq;
create sequence if not exists public.commercial_receipt_number_seq;
create sequence if not exists public.commercial_operation_code_seq;

create table if not exists public.commercial_customers(
 id uuid primary key default gen_random_uuid(), account_code text not null unique,
 full_name text not null, document_number text not null default '', phone text not null default '',
 address text not null default '', sector text not null default '', status text not null default 'Activo' check(status in ('Activo','Suspendido','Inactivo')),
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
create index if not exists commercial_invoices_customer_idx on public.commercial_invoices(customer_id,billing_period desc);
create index if not exists commercial_payments_customer_idx on public.commercial_payments(customer_id,payment_date desc);
create index if not exists commercial_requests_customer_idx on public.commercial_service_requests(customer_id,created_at desc);
alter table public.commercial_customers enable row level security;
alter table public.commercial_invoices enable row level security;
alter table public.commercial_payments enable row level security;
alter table public.commercial_service_requests enable row level security;
revoke all on public.commercial_customers,public.commercial_invoices,public.commercial_payments,public.commercial_service_requests from anon,authenticated;

create or replace function public.list_commercial_dashboard(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_customers jsonb;v_invoices jsonb;v_payments jsonb;v_requests jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_gestion_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar Gestión Comercial.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_customers from(select c.*,(select coalesce(sum(i.amount),0)-coalesce(sum((select coalesce(sum(p.amount),0) from public.commercial_payments p where p.invoice_id=i.id)),0) from public.commercial_invoices i where i.customer_id=c.id and i.status<>'Anulada') balance from public.commercial_customers c)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_invoices from(select i.*,c.account_code,c.full_name customer_name,coalesce((select sum(p.amount) from public.commercial_payments p where p.invoice_id=i.id),0) paid_amount from public.commercial_invoices i join public.commercial_customers c on c.id=i.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_payments from(select p.*,c.account_code,c.full_name customer_name from public.commercial_payments p join public.commercial_customers c on c.id=p.customer_id)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_requests from(select r.*,c.account_code,c.full_name customer_name from public.commercial_service_requests r join public.commercial_customers c on c.id=r.customer_id)x;
 return jsonb_build_object('success',true,'customers',v_customers,'invoices',v_invoices,'payments',v_payments,'requests',v_requests);
end $$;

create or replace function public.manage_commercial_record(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_id uuid;v_customer uuid;v_invoice uuid;v_total numeric;v_paid numeric;v_code text;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'gestionar_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar operaciones comerciales.');end if;
 if p_action='CUSTOMER' then
  insert into public.commercial_customers(account_code,full_name,document_number,phone,address,sector,created_by) values(trim(p_data->>'account_code'),trim(p_data->>'full_name'),coalesce(p_data->>'document_number',''),coalesce(p_data->>'phone',''),coalesce(p_data->>'address',''),coalesce(p_data->>'sector',''),v_user.id) returning id into v_id;
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
  insert into public.commercial_service_requests(code,customer_id,category,description,assigned_unit,created_by) values(v_code,(p_data->>'customer_id')::uuid,trim(p_data->>'category'),trim(p_data->>'description'),coalesce(p_data->>'assigned_unit','Centro de Servicio al Cliente'),v_user.id) returning id into v_id;
 else return jsonb_build_object('success',false,'error','Operación comercial no reconocida.');end if;
 return jsonb_build_object('success',true,'id',v_id,'code',v_code);
exception when unique_violation then return jsonb_build_object('success',false,'error','El código indicado ya se encuentra registrado.');when others then return jsonb_build_object('success',false,'error',sqlerrm);end $$;
grant execute on function public.list_commercial_dashboard(text),public.manage_commercial_record(text,text,jsonb) to anon,authenticated;
