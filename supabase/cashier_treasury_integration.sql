-- Cajas institucionales: DAF/Tesorería comparte cobros con Dirección Comercial.
create sequence if not exists public.financial_cash_register_code_seq;
create table if not exists public.financial_cash_locations(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,location_type text not null check(location_type in('OFICINA PRINCIPAL','CENTRO DE SERVICIO')),
 municipality text not null default 'Moca',district text not null default '',address text not null default '',active boolean not null default true,created_at timestamptz not null default now()
);
insert into public.financial_cash_locations(code,name,location_type,municipality) values('OP-MOCA','Oficina principal','OFICINA PRINCIPAL','Moca') on conflict(code) do nothing;

alter table public.commercial_cash_registers
 add column if not exists register_code text,
 add column if not exists location_id uuid references public.financial_cash_locations(id),
 add column if not exists cashier_employee_id uuid references public.hr_employees(id),
 add column if not exists closed_by uuid references public.app_users(id),
 add column if not exists closing_comment text not null default '';
create unique index if not exists commercial_cash_register_code_uq on public.commercial_cash_registers(register_code) where register_code is not null;
alter table public.commercial_payments
 add column if not exists cash_register_id uuid references public.commercial_cash_registers(id),
 add column if not exists cashier_user_id uuid references public.app_users(id),
 add column if not exists service_location_id uuid references public.financial_cash_locations(id);
alter table public.financial_cash_locations enable row level security;
revoke all on public.financial_cash_locations from anon,authenticated;

create or replace function public.list_cashier_treasury(p_token text,p_year integer default null,p_month integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;y integer:=coalesce(p_year,extract(year from current_date)::int);m integer:=coalesce(p_month,extract(month from current_date)::int);result jsonb;
begin
 u:=public.hr_authenticated_user(p_token);
 if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'ver_cajas_tesoreria')::boolean,false) and not coalesce((u.permissions->>'registrar_cobros_caja')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar cajas y recaudación.');end if;
 select jsonb_build_object('success',true,
  'locations',coalesce((select jsonb_agg(to_jsonb(l) order by l.name) from public.financial_cash_locations l where l.active),'[]'::jsonb),
  'cashiers',coalesce((select jsonb_agg(to_jsonb(x) order by x.full_name) from(select au.id user_id,e.id employee_id,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,e.section_name from public.app_users au join public.hr_employees e on e.id=au.employee_id where au.active and e.employment_status='Activo' and (lower(e.position_name) like '%cajer%' or coalesce((au.permissions->>'registrar_cobros_caja')::boolean,false)))x),'[]'::jsonb),
  'customers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'account_code',c.account_code,'full_name',c.full_name) order by c.full_name) from public.commercial_customers c where c.status='Activo'),'[]'::jsonb),
  'invoices',coalesce((select jsonb_agg(to_jsonb(x) order by x.due_date) from(select i.id,i.invoice_number,i.customer_id,i.amount,i.due_date,i.status,c.full_name customer_name,coalesce((select sum(p.amount) from public.commercial_payments p where p.invoice_id=i.id),0) paid_amount from public.commercial_invoices i join public.commercial_customers c on c.id=i.customer_id where i.status not in('Pagada','Anulada'))x),'[]'::jsonb),
  'registers',coalesce((select jsonb_agg(to_jsonb(x) order by x.opened_at desc) from(select r.*,l.name location_name,l.location_type,e.full_name cashier_name,e.employee_code,(select coalesce(sum(p.amount),0) from public.commercial_payments p where p.cash_register_id=r.id) collected_amount,(select count(*) from public.commercial_payments p where p.cash_register_id=r.id) receipt_count from public.commercial_cash_registers r left join public.financial_cash_locations l on l.id=r.location_id left join public.hr_employees e on e.id=r.cashier_employee_id where extract(year from r.opened_at)=y and extract(month from r.opened_at)=m)x),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select p.*,c.account_code,c.full_name customer_name,l.name location_name,e.full_name cashier_name,r.register_code from public.commercial_payments p join public.commercial_customers c on c.id=p.customer_id left join public.financial_cash_locations l on l.id=p.service_location_id left join public.commercial_cash_registers r on r.id=p.cash_register_id left join public.app_users au on au.id=p.cashier_user_id left join public.hr_employees e on e.id=au.employee_id where extract(year from p.payment_date)=y and extract(month from p.payment_date)=m)x),'[]'::jsonb),
  'metrics',jsonb_build_object('collected',(select coalesce(sum(amount),0) from public.commercial_payments where extract(year from payment_date)=y and extract(month from payment_date)=m),'cashPayments',(select coalesce(sum(amount),0) from public.commercial_payments where extract(year from payment_date)=y and extract(month from payment_date)=m and cash_register_id is not null),'openRegisters',(select count(*) from public.commercial_cash_registers where status='ABIERTA'),'differences',(select coalesce(sum(abs(difference_amount)),0) from public.commercial_cash_registers where extract(year from opened_at)=y and extract(month from opened_at)=m and status='CERRADA'))
 ) into result;return result;
end$$;

create or replace function public.manage_cashier_treasury(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;new_id uuid;code text;reg public.commercial_cash_registers;total numeric;paid numeric;v_invoice_id uuid;customer_id uuid;expected numeric;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null then return jsonb_build_object('success',false,'error','Sesión no válida.');end if;
 if p_action in('CREATE_LOCATION','OPEN_REGISTER','CLOSE_REGISTER') and u.role<>'Administrador' and not coalesce((u.permissions->>'gestionar_cajas_tesoreria')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso de Tesorería para esta operación.');end if;
 if p_action='REGISTER_PAYMENT' and u.role<>'Administrador' and not coalesce((u.permissions->>'registrar_cobros_caja')::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para registrar cobros de caja.');end if;
 if p_action='CREATE_LOCATION' then insert into public.financial_cash_locations(code,name,location_type,municipality,district,address) values(upper(trim(p_data->>'code')),trim(p_data->>'name'),p_data->>'location_type',coalesce(p_data->>'municipality','Moca'),coalesce(p_data->>'district',''),coalesce(p_data->>'address','')) returning id into new_id;
 elsif p_action='OPEN_REGISTER' then
  if exists(select 1 from public.commercial_cash_registers where cashier_user_id=(p_data->>'cashier_user_id')::uuid and status='ABIERTA') then return jsonb_build_object('success',false,'error','La cajera ya posee un turno de caja abierto.');end if;
  code:='CAJ-'||extract(year from current_date)::int||'-'||lpad(nextval('public.financial_cash_register_code_seq')::text,6,'0');
  insert into public.commercial_cash_registers(register_code,cashier_user_id,cashier_employee_id,location_id,opening_amount) values(code,(p_data->>'cashier_user_id')::uuid,(select employee_id from public.app_users where id=(p_data->>'cashier_user_id')::uuid),(p_data->>'location_id')::uuid,coalesce(nullif(p_data->>'opening_amount','')::numeric,0)) returning id into new_id;
 elsif p_action='REGISTER_PAYMENT' then
  select * into reg from public.commercial_cash_registers where id=(p_data->>'cash_register_id')::uuid and status='ABIERTA' for update;if reg.id is null then return jsonb_build_object('success',false,'error','Seleccione una caja abierta.');end if;
  if u.role<>'Administrador' and reg.cashier_user_id<>u.id then return jsonb_build_object('success',false,'error','Este turno pertenece a otra cajera.');end if;
  customer_id:=(p_data->>'customer_id')::uuid;v_invoice_id:=nullif(p_data->>'invoice_id','')::uuid;code:='REC-'||extract(year from current_date)::int||'-'||lpad(nextval('public.commercial_receipt_number_seq')::text,6,'0');
  insert into public.commercial_payments(receipt_number,customer_id,invoice_id,amount,payment_date,channel,reference,created_by,cash_register_id,cashier_user_id,service_location_id) values(code,customer_id,v_invoice_id,(p_data->>'amount')::numeric,coalesce(nullif(p_data->>'payment_date','')::date,current_date),'Caja',coalesce(p_data->>'reference',''),u.id,reg.id,u.id,reg.location_id) returning id into new_id;
  if v_invoice_id is not null then select i.amount,coalesce((select sum(p.amount) from public.commercial_payments p where p.invoice_id=v_invoice_id),0) into total,paid from public.commercial_invoices i where i.id=v_invoice_id;update public.commercial_invoices set status=case when paid>=total then 'Pagada' when paid>0 then 'Parcial' else status end,updated_at=now() where id=v_invoice_id;end if;
 elsif p_action='CLOSE_REGISTER' then
  select * into reg from public.commercial_cash_registers where id=(p_data->>'id')::uuid and status='ABIERTA' for update;if reg.id is null then return jsonb_build_object('success',false,'error','La caja ya fue cerrada o no existe.');end if;
  expected:=reg.opening_amount+coalesce((select sum(amount) from public.commercial_payments where cash_register_id=reg.id),0);
  update public.commercial_cash_registers set closed_at=now(),expected_amount=expected,counted_amount=(p_data->>'counted_amount')::numeric,difference_amount=(p_data->>'counted_amount')::numeric-expected,status='CERRADA',closed_by=u.id,closing_comment=coalesce(p_data->>'comment','') where id=reg.id returning id into new_id;
 else return jsonb_build_object('success',false,'error','Operación de caja no reconocida.');end if;
 return jsonb_build_object('success',true,'id',new_id,'code',code);
exception when others then return jsonb_build_object('success',false,'error',sqlerrm);end$$;

grant execute on function public.list_cashier_treasury(text,integer,integer),public.manage_cashier_treasury(text,text,jsonb) to anon,authenticated;
