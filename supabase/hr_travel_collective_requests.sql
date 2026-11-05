-- Solicitudes colectivas de viaticos: un encabezado de comision con varios participantes.
create table if not exists public.hr_travel_requests(
 id uuid primary key default gen_random_uuid(),
 request_number bigint generated always as identity,
 destination text not null,
 purpose text not null,
 departure_at timestamptz not null,
 return_at timestamptz not null,
 support_url text not null default '',
 observations text not null default '',
 status text not null default 'REGISTRADA' check(status in('REGISTRADA','PARCIAL','APROBADA','RECHAZADA','PAGADA','ANULADA')),
 created_by uuid not null references public.app_users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(return_at>departure_at)
);
alter table public.hr_travel_allowances add column if not exists request_id uuid references public.hr_travel_requests(id) on delete restrict;
create index if not exists hr_travel_requests_period_idx on public.hr_travel_requests(departure_at,status);
create index if not exists hr_travel_allowances_request_idx on public.hr_travel_allowances(request_id);
alter table public.hr_travel_requests enable row level security;
revoke all on public.hr_travel_requests from anon,authenticated;

create or replace function public.save_hr_travel_request(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
 v_user public.app_users;v_request_id uuid;v_request_number bigint;v_participant jsonb;v_rate public.hr_travel_allowance_rates;
 v_departure timestamptz;v_return timestamptz;v_days integer;v_allowance_id uuid;v_transport numeric;v_tolls numeric;
 v_allowance numeric;v_detail record;v_concept public.hr_travel_allowance_concepts;v_quantity integer;v_tourist boolean;v_multiplier numeric;
 v_employee uuid;v_count integer:=0;v_total numeric:=0;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para registrar viáticos.');
 end if;
 v_departure:=(p_data->>'departure_at')::timestamptz;v_return:=(p_data->>'return_at')::timestamptz;
 if v_return<=v_departure then return jsonb_build_object('success',false,'error','El regreso debe ser posterior a la salida.');end if;
 if jsonb_array_length(coalesce(p_data->'participants','[]'::jsonb))=0 then return jsonb_build_object('success',false,'error','Agregue por lo menos un participante.');end if;
 if exists(select 1 from jsonb_array_elements(p_data->'participants') a group by a->>'employee_id' having count(*)>1) then
  return jsonb_build_object('success',false,'error','Un empleado no puede aparecer dos veces en la misma solicitud.');
 end if;
 insert into public.hr_travel_requests(destination,purpose,departure_at,return_at,support_url,observations,created_by)
 values(trim(p_data->>'destination'),trim(p_data->>'purpose'),v_departure,v_return,coalesce(p_data->>'support_url',''),coalesce(p_data->>'observations',''),v_user.id)
 returning id,request_number into v_request_id,v_request_number;
 for v_participant in select value from jsonb_array_elements(p_data->'participants') loop
  v_employee:=(v_participant->>'employee_id')::uuid;
  if not exists(select 1 from public.hr_employees where id=v_employee and active) then raise exception 'El participante seleccionado no es un empleado activo.';end if;
  if (select count(*) from public.hr_travel_allowances where employee_id=v_employee and date_trunc('month',departure_at)=date_trunc('month',v_departure) and status not in('RECHAZADA','ANULADA'))>=5 then
   raise exception 'Uno de los colaboradores ya posee cinco solicitudes activas en este mes.';
  end if;
  select * into v_rate from public.hr_travel_allowance_rates where id=(v_participant->>'rate_id')::uuid and active;
  if v_rate.id is null or v_departure<v_rate.effective_from or (v_rate.effective_to is not null and v_departure::date>v_rate.effective_to) then raise exception 'La tarifa de un participante no está vigente.';end if;
  v_days:=greatest(1,ceil(extract(epoch from(v_return-v_departure))/86400.0)::integer);
  v_transport:=greatest(0,coalesce((v_participant->>'transport_amount')::numeric,0));v_tolls:=greatest(0,coalesce((v_participant->>'toll_amount')::numeric,0));
  v_tourist:=coalesce((v_participant->>'tourist_destination')::boolean,false);v_multiplier:=case when v_tourist then 1.05 else 1 end;v_allowance:=0;
  for v_detail in select * from jsonb_to_recordset(coalesce(v_participant->'concepts','[]'::jsonb)) as x(code text,quantity integer) loop
   select * into v_concept from public.hr_travel_allowance_concepts where code=v_detail.code and active;v_quantity:=greatest(0,least(31,coalesce(v_detail.quantity,0)));
   if v_concept.code is not null and v_quantity>0 then v_allowance:=v_allowance+round(v_rate.daily_amount*v_multiplier*v_concept.rate_percent/100,2)*v_quantity;end if;
  end loop;
  if v_allowance<=0 then raise exception 'Cada participante debe tener por lo menos un concepto de viático.';end if;
  insert into public.hr_travel_allowances(request_id,employee_id,rate_id,destination,purpose,departure_at,return_at,days,daily_rate,allowance_amount,transport_mode,transport_amount,toll_amount,total_amount,support_url,observations,legal_basis,tourist_destination,uplift_percent,created_by)
  values(v_request_id,v_employee,v_rate.id,trim(p_data->>'destination'),trim(p_data->>'purpose'),v_departure,v_return,v_days,round(v_rate.daily_amount*v_multiplier,2),v_allowance,coalesce(v_participant->>'transport_mode','INSTITUCIONAL'),v_transport,v_tolls,v_allowance+v_transport+v_tolls,coalesce(p_data->>'support_url',''),coalesce(v_participant->>'observations',''),v_rate.legal_basis,v_tourist,case when v_tourist then 5 else 0 end,v_user.id)
  returning id into v_allowance_id;
  for v_detail in select * from jsonb_to_recordset(coalesce(v_participant->'concepts','[]'::jsonb)) as x(code text,quantity integer) loop
   select * into v_concept from public.hr_travel_allowance_concepts where code=v_detail.code and active;v_quantity:=greatest(0,least(31,coalesce(v_detail.quantity,0)));
   if v_concept.code is not null and v_quantity>0 then insert into public.hr_travel_allowance_details(allowance_id,concept_code,quantity,rate_percent,unit_amount,total_amount) values(v_allowance_id,v_concept.code,v_quantity,v_concept.rate_percent,round(v_rate.daily_amount*v_multiplier*v_concept.rate_percent/100,2),round(v_rate.daily_amount*v_multiplier*v_concept.rate_percent/100,2)*v_quantity);end if;
  end loop;
  v_count:=v_count+1;v_total:=v_total+v_allowance+v_transport+v_tolls;
 end loop;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'REGISTRAR_SOLICITUD_COLECTIVA_VIATICOS','Recursos Humanos',jsonb_build_object('entity_type','hr_travel_requests','entity_id',v_request_id,'request_number',v_request_number,'participants',v_count,'total',v_total));
 return jsonb_build_object('success',true,'id',v_request_id,'request_number',v_request_number,'participants',v_count,'total',v_total);
exception when others then return jsonb_build_object('success',false,'error','No fue posible registrar la solicitud colectiva: '||sqlerrm);end $$;

create or replace function public.sync_hr_travel_request_status(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_total integer;v_paid integer;v_approved integer;v_rejected integer;begin
 if p_request_id is null then return;end if;
 select count(*),count(*) filter(where status='PAGADA'),count(*) filter(where status='APROBADA'),count(*) filter(where status in('RECHAZADA','ANULADA')) into v_total,v_paid,v_approved,v_rejected from public.hr_travel_allowances where request_id=p_request_id;
 update public.hr_travel_requests set status=case when v_paid=v_total then 'PAGADA' when v_rejected=v_total then 'RECHAZADA' when v_approved=v_total then 'APROBADA' when v_paid+v_approved+v_rejected>0 then 'PARCIAL' else 'REGISTRADA' end,updated_at=now() where id=p_request_id;
end $$;

-- Amplía el listado existente con el número colectivo sin romper solicitudes históricas.
create or replace function public.list_hr_travel_allowances(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar viáticos.');end if;
 return jsonb_build_object('success',true,
 'rates',coalesce((select jsonb_agg(to_jsonb(r) order by daily_amount desc) from public.hr_travel_allowance_rates r where active and effective_from<=make_date(p_year,12,31) and (effective_to is null or effective_to>=make_date(p_year,1,1))),'[]'::jsonb),
 'concepts',coalesce((select jsonb_agg(to_jsonb(c) order by c.display_order) from public.hr_travel_allowance_concepts c where c.active),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.departure_at desc,x.collective_request_number,x.employee_name) from(select t.*,q.request_number collective_request_number,e.full_name employee_name,e.employee_code,e.position_name,r.category,((select count(*) from generate_series(t.created_at::date,(t.departure_at::date-1),'1 day') d where extract(isodow from d)<6)<10) advance_warning,coalesce((select jsonb_agg(jsonb_build_object('code',d.concept_code,'name',c.name,'quantity',d.quantity,'unit_amount',d.unit_amount,'total_amount',d.total_amount) order by c.display_order) from public.hr_travel_allowance_details d join public.hr_travel_allowance_concepts c on c.code=d.concept_code where d.allowance_id=t.id),'[]'::jsonb) details from public.hr_travel_allowances t left join public.hr_travel_requests q on q.id=t.request_id join public.hr_employees e on e.id=t.employee_id join public.hr_travel_allowance_rates r on r.id=t.rate_id where extract(year from t.departure_at)=p_year)x),'[]'::jsonb));end $$;

create or replace function public.transition_hr_travel_allowance(p_token text,p_id uuid,p_status text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_item public.hr_travel_allowances;begin v_user:=public.hr_authenticated_user(p_token);if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'aprobar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para aprobar o pagar viáticos.');end if;select * into v_item from public.hr_travel_allowances where id=p_id for update;if v_item.id is null then return jsonb_build_object('success',false,'error','Participante no encontrado.');end if;
 if not((v_item.status='REGISTRADA' and p_status in('APROBADA','RECHAZADA'))or(v_item.status='APROBADA' and p_status='PAGADA'))then return jsonb_build_object('success',false,'error','La transición solicitada no está permitida.');end if;if p_status='RECHAZADA' and trim(coalesce(p_notes,''))='' then return jsonb_build_object('success',false,'error','El motivo del rechazo es obligatorio.');end if;
 update public.hr_travel_allowances set status=p_status,decision_notes=coalesce(p_notes,''),approved_by=case when p_status in('APROBADA','RECHAZADA') then v_user.id else approved_by end,approved_at=case when p_status in('APROBADA','RECHAZADA') then now() else approved_at end,paid_by=case when p_status='PAGADA' then v_user.id else paid_by end,paid_at=case when p_status='PAGADA' then now() else paid_at end,updated_at=now() where id=p_id;
 perform public.sync_hr_travel_request_status(v_item.request_id);
 insert into public.security_audit_log(actor_user_id,action,module,detail)values(v_user.id,'CAMBIAR_ESTADO_VIATICO','Recursos Humanos',jsonb_build_object('entity_type','hr_travel_allowances','entity_id',p_id,'request_id',v_item.request_id,'from',v_item.status,'to',p_status,'notes',p_notes));return jsonb_build_object('success',true,'status',p_status);end $$;
grant execute on function public.save_hr_travel_request(text,jsonb),public.list_hr_travel_allowances(text,integer),public.transition_hr_travel_allowance(text,uuid,text,text) to anon,authenticated;
