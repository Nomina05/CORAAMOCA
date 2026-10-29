-- Indicadores georreferenciados de averías comerciales.
alter table public.commercial_service_requests
 add column if not exists latitude numeric(10,7),
 add column if not exists longitude numeric(10,7),
 add column if not exists fault_priority text not null default 'Media';
alter table public.commercial_faults add column if not exists service_request_id uuid references public.commercial_service_requests(id);
create unique index if not exists commercial_fault_service_request_uq on public.commercial_faults(service_request_id) where service_request_id is not null;

create or replace function public.commercial_sync_reported_fault()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_lat numeric;v_lng numeric;v_code text;
begin
 if lower(new.category) not in('avería','averia','fuga') then return new;end if;
 select coalesce(new.latitude,c.latitude),coalesce(new.longitude,c.longitude) into v_lat,v_lng from public.commercial_customers c where c.id=new.customer_id;
 v_code:='AVE-'||extract(year from new.created_at)::int||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0');
 insert into public.commercial_faults(fault_code,service_request_id,customer_id,fault_type,description,zone,latitude,longitude,priority,status,created_by,reported_at,resolved_at)
 values(v_code,new.id,new.customer_id,new.category,new.description,new.zone,v_lat,v_lng,new.fault_priority,case when new.status in('Resuelta','Cerrada') then 'RESUELTA' else 'REPORTADA' end,new.created_by,new.created_at,case when new.status in('Resuelta','Cerrada') then coalesce(new.resolved_at,now()) end)
 on conflict(service_request_id) where service_request_id is not null do update set description=excluded.description,zone=excluded.zone,latitude=excluded.latitude,longitude=excluded.longitude,priority=excluded.priority,status=excluded.status,resolved_at=excluded.resolved_at;
 return new;
end$$;
drop trigger if exists trg_commercial_sync_reported_fault on public.commercial_service_requests;
create trigger trg_commercial_sync_reported_fault after insert or update of category,description,zone,latitude,longitude,fault_priority,status on public.commercial_service_requests for each row execute function public.commercial_sync_reported_fault();

insert into public.commercial_faults(fault_code,service_request_id,customer_id,fault_type,description,zone,latitude,longitude,priority,status,created_by,reported_at,resolved_at)
select 'AVE-'||extract(year from r.created_at)::int||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0'),r.id,r.customer_id,r.category,r.description,r.zone,coalesce(r.latitude,c.latitude),coalesce(r.longitude,c.longitude),r.fault_priority,case when r.status in('Resuelta','Cerrada') then 'RESUELTA' else 'REPORTADA' end,r.created_by,r.created_at,case when r.status in('Resuelta','Cerrada') then coalesce(r.resolved_at,r.updated_at) end
from public.commercial_service_requests r join public.commercial_customers c on c.id=r.customer_id
where lower(r.category) in('avería','averia','fuga') and not exists(select 1 from public.commercial_faults f where f.service_request_id=r.id);

-- Extiende el registro comercial para conservar las coordenadas del reporte.
create or replace function public.manage_commercial_record(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_id uuid;v_customer uuid;v_invoice uuid;v_total numeric;v_paid numeric;v_code text;
begin
 v_user:=public.hr_authenticated_user(p_token);if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'gestionar_comercial')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar operaciones comerciales.');end if;
 if p_action='CUSTOMER' then insert into public.commercial_customers(account_code,full_name,document_number,phone,address,sector,customer_category,latitude,longitude,contract_date,created_by) values(trim(p_data->>'account_code'),trim(p_data->>'full_name'),coalesce(p_data->>'document_number',''),coalesce(p_data->>'phone',''),coalesce(p_data->>'address',''),coalesce(p_data->>'sector',''),coalesce(nullif(p_data->>'customer_category',''),'Residencial'),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,coalesce(nullif(p_data->>'contract_date','')::date,current_date),v_user.id) returning id into v_id;
 elsif p_action='INVOICE' then v_code:='FAC-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_invoice_number_seq')::text,6,'0');insert into public.commercial_invoices(invoice_number,customer_id,billing_period,amount,due_date,created_by) values(v_code,(p_data->>'customer_id')::uuid,((p_data->>'billing_period')||'-01')::date,(p_data->>'amount')::numeric,(p_data->>'due_date')::date,v_user.id) returning id into v_id;
 elsif p_action='PAYMENT' then v_customer:=(p_data->>'customer_id')::uuid;v_invoice:=nullif(p_data->>'invoice_id','')::uuid;v_code:='REC-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_receipt_number_seq')::text,6,'0');insert into public.commercial_payments(receipt_number,customer_id,invoice_id,amount,payment_date,channel,reference,created_by) values(v_code,v_customer,v_invoice,(p_data->>'amount')::numeric,coalesce(nullif(p_data->>'payment_date','')::date,current_date),coalesce(p_data->>'channel','Caja'),coalesce(p_data->>'reference',''),v_user.id) returning id into v_id;if v_invoice is not null then select amount,coalesce((select sum(amount) from public.commercial_payments where invoice_id=v_invoice),0) into v_total,v_paid from public.commercial_invoices where id=v_invoice;update public.commercial_invoices set status=case when v_paid>=v_total then 'Pagada' when v_paid>0 then 'Parcial' else status end,updated_at=now() where id=v_invoice;end if;
 elsif p_action='REQUEST' then v_code:='OP-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_operation_code_seq')::text,6,'0');insert into public.commercial_service_requests(code,customer_id,category,description,assigned_unit,service_channel,zone,latitude,longitude,fault_priority,created_by) values(v_code,(p_data->>'customer_id')::uuid,trim(p_data->>'category'),trim(p_data->>'description'),coalesce(p_data->>'assigned_unit','Centro de Servicio al Cliente'),coalesce(p_data->>'service_channel','Presencial'),coalesce(p_data->>'zone',''),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,coalesce(p_data->>'fault_priority','Media'),v_user.id) returning id into v_id;
 elsif p_action='METER' then insert into public.commercial_meters(customer_id,meter_number,latitude,longitude,created_by) values((p_data->>'customer_id')::uuid,trim(p_data->>'meter_number'),nullif(p_data->>'latitude','')::numeric,nullif(p_data->>'longitude','')::numeric,v_user.id) returning id into v_id;
 elsif p_action='READING' then insert into public.commercial_meter_readings(meter_id,reading_date,reading_value,applied_to_billing,notes,created_by) values((p_data->>'meter_id')::uuid,coalesce(nullif(p_data->>'reading_date','')::date,current_date),(p_data->>'reading_value')::numeric,coalesce((p_data->>'applied_to_billing')::boolean,false),coalesce(p_data->>'notes',''),v_user.id) returning id into v_id;
 elsif p_action='CUT_ORDER' then v_code:='OCR-'||extract(year from current_date)::integer||'-'||lpad(nextval('public.commercial_work_order_code_seq')::text,6,'0');insert into public.commercial_cut_reconnection_orders(code,customer_id,meter_id,order_type,reason,requested_by_unit,created_by) values(v_code,(p_data->>'customer_id')::uuid,nullif(p_data->>'meter_id','')::uuid,p_data->>'order_type',trim(p_data->>'reason'),coalesce(p_data->>'requested_by_unit','Micro-Medición'),v_user.id) returning id into v_id;
 elsif p_action='COMPLETE_CUT_ORDER' then update public.commercial_cut_reconnection_orders set status='Realizada',completed_at=now(),updated_at=now() where id=(p_data->>'id')::uuid returning id,code into v_id,v_code;
 else return jsonb_build_object('success',false,'error','Operación comercial no reconocida.');end if;
 return jsonb_build_object('success',true,'id',v_id,'code',v_code);
exception when unique_violation then return jsonb_build_object('success',false,'error','El código indicado ya se encuentra registrado.');when others then return jsonb_build_object('success',false,'error',sqlerrm);end$$;
grant execute on function public.manage_commercial_record(text,text,jsonb) to anon,authenticated;
