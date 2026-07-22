-- Gestión de viáticos conforme a la Resolución MAP núm. 173-2025.
create table if not exists public.hr_travel_allowance_rates(
 id uuid primary key default gen_random_uuid(), category text not null, daily_amount numeric(12,2) not null check(daily_amount>=0),
 legal_basis text not null, effective_from date not null, effective_to date, active boolean not null default true,
 unique(category,effective_from), check(effective_to is null or effective_to>=effective_from)
);
insert into public.hr_travel_allowance_rates(category,daily_amount,legal_basis,effective_from) values
('MINISTROS',7950,'Resolución MAP núm. 173-2025','2025-07-09'),
('VICEMINISTROS',7350,'Resolución MAP núm. 173-2025','2025-07-09'),
('DIRECTORES GENERALES, NACIONALES, EJECUTIVOS Y EQUIVALENTES',6950,'Resolución MAP núm. 173-2025','2025-07-09'),
('SUBDIRECTORES GENERALES, NACIONALES Y EQUIVALENTES',6550,'Resolución MAP núm. 173-2025','2025-07-09'),
('DIRECTORES DE ÁREAS',6150,'Resolución MAP núm. 173-2025','2025-07-09'),
('ENCARGADOS DE DEPARTAMENTOS, DIVISIONES Y COORDINADORES',5750,'Resolución MAP núm. 173-2025','2025-07-09'),
('ENCARGADOS DE SECCIONES Y COORDINADORES',5250,'Resolución MAP núm. 173-2025','2025-07-09'),
('PROFESIONALES',4750,'Resolución MAP núm. 173-2025','2025-07-09'),
('TÉCNICOS',4100,'Resolución MAP núm. 173-2025','2025-07-09'),
('OTROS PUESTOS',3900,'Resolución MAP núm. 173-2025','2025-07-09')
on conflict(category,effective_from) do update set daily_amount=excluded.daily_amount,legal_basis=excluded.legal_basis;

create table if not exists public.hr_travel_allowances(
 id uuid primary key default gen_random_uuid(), request_number bigint generated always as identity, employee_id uuid not null references public.hr_employees(id),
 rate_id uuid not null references public.hr_travel_allowance_rates(id), destination text not null, purpose text not null,
 departure_at timestamptz not null, return_at timestamptz not null, days integer not null check(days>0), daily_rate numeric(12,2) not null,
 allowance_amount numeric(14,2) not null, transport_mode text not null check(transport_mode in ('INSTITUCIONAL','PROPIO','PUBLICO')),
 transport_amount numeric(14,2) not null default 0, toll_amount numeric(14,2) not null default 0, total_amount numeric(14,2) not null,
 support_url text not null default '', observations text not null default '', legal_basis text not null,
 status text not null default 'REGISTRADA' check(status in ('REGISTRADA','APROBADA','RECHAZADA','PAGADA','ANULADA')),
 created_by uuid not null references public.app_users(id), approved_by uuid references public.app_users(id), paid_by uuid references public.app_users(id),
 approved_at timestamptz, paid_at timestamptz, decision_notes text not null default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(return_at>departure_at)
);
create index if not exists hr_travel_allowances_year_idx on public.hr_travel_allowances(departure_at,status);
alter table public.hr_travel_allowance_rates enable row level security;alter table public.hr_travel_allowances enable row level security;
revoke all on public.hr_travel_allowance_rates,public.hr_travel_allowances from anon,authenticated;

create or replace function public.list_hr_travel_allowances(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar viáticos.');end if;
 return jsonb_build_object('success',true,
 'rates',coalesce((select jsonb_agg(to_jsonb(r) order by daily_amount desc) from public.hr_travel_allowance_rates r where active and effective_from<=make_date(p_year,12,31) and (effective_to is null or effective_to>=make_date(p_year,1,1))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.departure_at desc) from(select t.*,e.full_name employee_name,e.employee_code,e.position_name,r.category,((select count(*) from generate_series(t.created_at::date,(t.departure_at::date-1),'1 day') d where extract(isodow from d)<6)<10) advance_warning from public.hr_travel_allowances t join public.hr_employees e on e.id=t.employee_id join public.hr_travel_allowance_rates r on r.id=t.rate_id where extract(year from t.departure_at)=p_year)x),'[]'::jsonb));end $$;

create or replace function public.save_hr_travel_allowance(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_rate public.hr_travel_allowance_rates;v_departure timestamptz;v_return timestamptz;v_days integer;v_id uuid;v_number bigint;v_transport numeric;v_tolls numeric;begin
 v_user:=public.hr_authenticated_user(p_token);if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar viáticos.');end if;
 select * into v_rate from public.hr_travel_allowance_rates where id=(p_data->>'rate_id')::uuid and active;v_departure:=(p_data->>'departure_at')::timestamptz;v_return:=(p_data->>'return_at')::timestamptz;
 if v_rate.id is null or v_departure<v_rate.effective_from or (v_rate.effective_to is not null and v_departure::date>v_rate.effective_to) then return jsonb_build_object('success',false,'error','La tarifa no está vigente para la fecha seleccionada.');end if;if v_return<=v_departure then return jsonb_build_object('success',false,'error','El regreso debe ser posterior a la salida.');end if;
 v_days:=greatest(1,ceil(extract(epoch from(v_return-v_departure))/86400.0)::integer);v_transport:=greatest(0,coalesce((p_data->>'transport_amount')::numeric,0));v_tolls:=greatest(0,coalesce((p_data->>'toll_amount')::numeric,0));
 insert into public.hr_travel_allowances(employee_id,rate_id,destination,purpose,departure_at,return_at,days,daily_rate,allowance_amount,transport_mode,transport_amount,toll_amount,total_amount,support_url,observations,legal_basis,created_by)
 values((p_data->>'employee_id')::uuid,v_rate.id,trim(p_data->>'destination'),trim(p_data->>'purpose'),v_departure,v_return,v_days,v_rate.daily_amount,v_days*v_rate.daily_amount,coalesce(p_data->>'transport_mode','INSTITUCIONAL'),v_transport,v_tolls,v_days*v_rate.daily_amount+v_transport+v_tolls,coalesce(p_data->>'support_url',''),coalesce(p_data->>'observations',''),v_rate.legal_basis,v_user.id) returning id,request_number into v_id,v_number;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'REGISTRAR_VIATICO','Recursos Humanos',jsonb_build_object('entity_type','hr_travel_allowances','entity_id',v_id,'request_number',v_number,'employee_id',p_data->>'employee_id','total',v_days*v_rate.daily_amount+v_transport+v_tolls));return jsonb_build_object('success',true,'id',v_id,'request_number',v_number);
 exception when others then return jsonb_build_object('success',false,'error','No fue posible registrar la solicitud: '||sqlerrm);end $$;

create or replace function public.transition_hr_travel_allowance(p_token text,p_id uuid,p_status text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_item public.hr_travel_allowances;begin v_user:=public.hr_authenticated_user(p_token);if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'aprobar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para aprobar o pagar viáticos.');end if;select * into v_item from public.hr_travel_allowances where id=p_id for update;if v_item.id is null then return jsonb_build_object('success',false,'error','Solicitud no encontrada.');end if;
 if not((v_item.status='REGISTRADA' and p_status in('APROBADA','RECHAZADA'))or(v_item.status='APROBADA' and p_status='PAGADA'))then return jsonb_build_object('success',false,'error','La transición solicitada no está permitida.');end if;if p_status='RECHAZADA' and trim(coalesce(p_notes,''))='' then return jsonb_build_object('success',false,'error','El motivo del rechazo es obligatorio.');end if;
 update public.hr_travel_allowances set status=p_status,decision_notes=coalesce(p_notes,''),approved_by=case when p_status in('APROBADA','RECHAZADA') then v_user.id else approved_by end,approved_at=case when p_status in('APROBADA','RECHAZADA') then now() else approved_at end,paid_by=case when p_status='PAGADA' then v_user.id else paid_by end,paid_at=case when p_status='PAGADA' then now() else paid_at end,updated_at=now() where id=p_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail)values(v_user.id,'CAMBIAR_ESTADO_VIATICO','Recursos Humanos',jsonb_build_object('entity_type','hr_travel_allowances','entity_id',p_id,'from',v_item.status,'to',p_status,'notes',p_notes));return jsonb_build_object('success',true,'status',p_status);end $$;
grant execute on function public.list_hr_travel_allowances(text,integer),public.save_hr_travel_allowance(text,jsonb),public.transition_hr_travel_allowance(text,uuid,text,text) to anon,authenticated;
