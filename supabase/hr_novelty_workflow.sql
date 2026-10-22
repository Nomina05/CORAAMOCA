-- Flujo unificado de novedades y control automático de vacaciones.
create table if not exists public.hr_holidays(
 id uuid primary key default gen_random_uuid(),holiday_date date not null unique,name text not null,active boolean not null default true,created_at timestamptz not null default now()
);
insert into public.hr_holidays(holiday_date,name) values
('2026-01-01','Año Nuevo'),('2026-01-06','Día de Reyes'),('2026-01-21','Nuestra Señora de la Altagracia'),('2026-01-26','Día de Duarte'),('2026-02-27','Independencia Nacional'),('2026-04-03','Viernes Santo'),('2026-05-01','Día del Trabajo'),('2026-06-04','Corpus Christi'),('2026-08-16','Restauración'),('2026-09-24','Nuestra Señora de las Mercedes'),('2026-11-06','Día de la Constitución'),('2026-12-25','Navidad') on conflict(holiday_date) do update set name=excluded.name;

create table if not exists public.hr_novelties(
 id uuid primary key default gen_random_uuid(),novelty_number bigint generated always as identity,employee_id uuid not null references public.hr_employees(id),
 novelty_type text not null check(novelty_type in('PERMISO','VACACION','VIATICO','HORAS_EXTRAS','PRIMA_TRANSPORTE')),
 request_date date not null default current_date,start_date date not null,end_date date not null,work_days integer not null default 0,
 amount numeric(18,2) not null default 0,description text not null,document_url text not null default '',
 status text not null default 'REGISTRADA' check(status in('REGISTRADA','REVISADA_ENCARGADO','VALIDADA_RRHH','APROBADA','APLICADA_NOMINA','DEVUELTA','RECHAZADA','ANULADA')),
 source_table text,source_id uuid,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(end_date>=start_date),unique(source_table,source_id)
);
create table if not exists public.hr_novelty_history(
 id uuid primary key default gen_random_uuid(),novelty_id uuid not null references public.hr_novelties(id) on delete cascade,
 from_status text,to_status text not null,observation text not null default '',document_url text not null default '',responsible_user_id uuid not null references public.app_users(id),created_at timestamptz not null default now()
);
create index if not exists hr_novelties_employee_date_idx on public.hr_novelties(employee_id,start_date,end_date);
create index if not exists hr_novelties_status_idx on public.hr_novelties(status,novelty_type);
alter table public.hr_holidays enable row level security;alter table public.hr_novelties enable row level security;alter table public.hr_novelty_history enable row level security;
revoke all on public.hr_holidays,public.hr_novelties,public.hr_novelty_history from anon,authenticated;

create or replace function public.hr_business_days(p_start date,p_end date) returns integer language sql stable set search_path=public as $$
 select count(*)::integer from generate_series(p_start,p_end,'1 day') d
 where extract(isodow from d)<6 and not exists(select 1 from public.hr_holidays h where h.active and h.holiday_date=d::date)
$$;

create or replace function public.list_hr_novelty_workflow(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not(coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false) or coalesce((v_user.permissions->>'ver_vacaciones')::boolean,false))) then return jsonb_build_object('success',false,'error','No posee permiso para consultar novedades.');end if;
 return jsonb_build_object('success',true,
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
  select n.*,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,
   coalesce((select jsonb_agg(jsonb_build_object('from_status',h.from_status,'to_status',h.to_status,'observation',h.observation,'document_url',h.document_url,'responsible_name',u.full_name,'created_at',h.created_at) order by h.created_at) from public.hr_novelty_history h join public.app_users u on u.id=h.responsible_user_id where h.novelty_id=n.id),'[]'::jsonb) history
  from public.hr_novelties n join public.hr_employees e on e.id=n.employee_id where extract(year from n.request_date)=p_year and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x),'[]'::jsonb),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'direction_name',e.direction_name,'department_name',e.department_name) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
 'vacation_balances',coalesce((select jsonb_agg(to_jsonb(x) order by x.alert_level desc,x.full_name) from(
  select e.id employee_id,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,e.monthly_salary,e.hire_date,
   case when e.hire_date is null then 0 when age(make_date(p_year,12,31),e.hire_date)<interval '1 year' then round(least(12,greatest(0,extract(year from age(make_date(p_year,12,31),e.hire_date))*12+extract(month from age(make_date(p_year,12,31),e.hire_date))))*14/12.0)::integer when age(make_date(p_year,12,31),e.hire_date)>=interval '5 years' then 18 else 14 end acquired_days,
   coalesce(sum(n.work_days) filter(where n.novelty_type='VACACION' and n.status='APLICADA_NOMINA' and extract(year from n.start_date)=p_year),0)::integer used_days,
   coalesce(sum(n.work_days) filter(where n.novelty_type='VACACION' and n.status in('REGISTRADA','REVISADA_ENCARGADO','VALIDADA_RRHH','APROBADA') and extract(year from n.start_date)=p_year),0)::integer pending_days,
   case when e.hire_date is not null and current_date>make_date(p_year,12,31) and coalesce(sum(n.work_days) filter(where n.novelty_type='VACACION' and n.status='APLICADA_NOMINA' and extract(year from n.start_date)=p_year),0)=0 then 'VENCIDA' when coalesce(sum(n.work_days) filter(where n.novelty_type='VACACION' and n.status='APLICADA_NOMINA' and extract(year from n.start_date)=p_year),0)=0 then 'ACUMULADA' else 'NORMAL' end alert_level
  from public.hr_employees e left join public.hr_novelties n on n.employee_id=e.id where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e)) group by e.id
 )x),'[]'::jsonb),
 'holidays',coalesce((select jsonb_agg(to_jsonb(h) order by h.holiday_date) from public.hr_holidays h where h.active and extract(year from h.holiday_date)=p_year),'[]'::jsonb));end $$;

create or replace function public.save_hr_novelty(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_type text:=p_data->>'novelty_type';v_start date;v_end date;v_days integer;v_id uuid;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not(coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false) or coalesce((v_user.permissions->>'registrar_vacaciones')::boolean,false) or coalesce((v_user.permissions->>'registrar_permisos_laborales')::boolean,false))) then return jsonb_build_object('success',false,'error','No posee permiso para registrar novedades.');end if;
 if v_type not in('PERMISO','VACACION','VIATICO','HORAS_EXTRAS','PRIMA_TRANSPORTE') then return jsonb_build_object('success',false,'error','Tipo de novedad inválido.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado no encontrado.');end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','El empleado no pertenece a su unidad autorizada.');end if;
 v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);v_days:=public.hr_business_days(v_start,v_end);
 if v_days<1 then return jsonb_build_object('success',false,'error','El período no contiene días laborables.');end if;
 if v_type='VACACION' and exists(select 1 from public.hr_novelties n join public.hr_employees e on e.id=n.employee_id where n.novelty_type='VACACION' and n.status not in('RECHAZADA','ANULADA','DEVUELTA') and daterange(n.start_date,n.end_date,'[]')&&daterange(v_start,v_end,'[]') and (coalesce(e.department_name,e.direction_name)=coalesce(v_employee.department_name,v_employee.direction_name))) then return jsonb_build_object('success',false,'error','Existe otra ausencia programada en la misma unidad para esas fechas.');end if;
 insert into public.hr_novelties(employee_id,novelty_type,request_date,start_date,end_date,work_days,amount,description,document_url,created_by)
 values(v_employee.id,v_type,coalesce(nullif(p_data->>'request_date','')::date,current_date),v_start,v_end,v_days,greatest(0,coalesce(nullif(p_data->>'amount','')::numeric,0)),trim(p_data->>'description'),coalesce(p_data->>'document_url',''),v_user.id) returning id into v_id;
 insert into public.hr_novelty_history(novelty_id,to_status,observation,document_url,responsible_user_id) values(v_id,'REGISTRADA','Registro inicial',coalesce(p_data->>'document_url',''),v_user.id);
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'REGISTRAR_NOVEDAD','Recursos Humanos',jsonb_build_object('employee_id',v_employee.id,'novelty_id',v_id,'type',v_type));return jsonb_build_object('success',true,'id',v_id);end $$;

create or replace function public.transition_hr_novelty(p_token text,p_id uuid,p_action text,p_observation text,p_document_url text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_item public.hr_novelties;v_next text;begin v_user:=public.hr_authenticated_user(p_token);select * into v_item from public.hr_novelties where id=p_id for update;
 if v_user.id is null or v_item.id is null then return jsonb_build_object('success',false,'error','Novedad no encontrada o sesión inválida.');end if;
 if p_action in('RECHAZAR','DEVOLVER') then if trim(coalesce(p_observation,''))='' then return jsonb_build_object('success',false,'error','La observación es obligatoria para rechazar o devolver.');end if;v_next:=case p_action when 'RECHAZAR' then 'RECHAZADA' else 'DEVUELTA' end;
 elsif v_item.status='DEVUELTA' then v_next:='REGISTRADA';
 else v_next:=case v_item.status when 'REGISTRADA' then 'REVISADA_ENCARGADO' when 'REVISADA_ENCARGADO' then 'VALIDADA_RRHH' when 'VALIDADA_RRHH' then 'APROBADA' when 'APROBADA' then 'APLICADA_NOMINA' end;end if;
 if v_next is null or v_item.status in('APLICADA_NOMINA','RECHAZADA','ANULADA') then return jsonb_build_object('success',false,'error','La transición solicitada no está permitida.');end if;
 if v_user.role<>'Administrador' and not(coalesce((v_user.permissions->>'aprobar_recursos_humanos')::boolean,false) or (v_item.novelty_type='VACACION' and coalesce((v_user.permissions->>'aprobar_vacaciones')::boolean,false)) or (v_item.novelty_type='PERMISO' and coalesce((v_user.permissions->>'aprobar_permisos_laborales')::boolean,false))) then return jsonb_build_object('success',false,'error','No posee permiso para procesar esta etapa.');end if;
 if v_next not in('DEVUELTA','RECHAZADA','REGISTRADA') and nullif(trim(coalesce(p_document_url,'')),'') is null then return jsonb_build_object('success',false,'error','Adjunte el enlace del documento que sustenta esta transición.');end if;
 update public.hr_novelties set status=v_next,updated_at=now() where id=p_id;
 insert into public.hr_novelty_history(novelty_id,from_status,to_status,observation,document_url,responsible_user_id) values(p_id,v_item.status,v_next,coalesce(p_observation,''),coalesce(p_document_url,''),v_user.id);
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'TRANSICION_NOVEDAD','Recursos Humanos',jsonb_build_object('employee_id',v_item.employee_id,'novelty_id',p_id,'from',v_item.status,'to',v_next,'observation',p_observation));
 insert into public.app_notifications(user_id,notification_type,severity,event_key,title,message,action_section)
 select u.id,'DOCUMENTO','medium','NOVEDAD:'||p_id||':'||v_next,'Novedad pendiente de intervención','La novedad No. '||v_item.novelty_number||' avanzó a '||replace(v_next,'_',' ')||'.','Flujo de Novedades' from public.app_users u where u.active and u.suspended_at is null and (u.role='Administrador' or coalesce((u.permissions->>'aprobar_recursos_humanos')::boolean,false)) on conflict(user_id,event_key) where event_key is not null do update set message=excluded.message,read_at=null,created_at=now();
 return jsonb_build_object('success',true,'status',v_next);end $$;

grant execute on function public.hr_business_days(date,date),public.list_hr_novelty_workflow(text,integer),public.save_hr_novelty(text,jsonb),public.transition_hr_novelty(text,uuid,text,text,text) to anon,authenticated;
