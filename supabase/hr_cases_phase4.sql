-- Fase 4: consolidación de permisos, vacaciones y amonestaciones.
-- Mantiene una numeración independiente, flujo trazable, alcance jerárquico y sincronización
-- entre el expediente del empleado y el flujo de novedades.

alter table public.hr_novelties add column if not exists module_number bigint;
with numbered as (
 select id,row_number() over(partition by novelty_type order by created_at,novelty_number,id) module_number
 from public.hr_novelties
)
update public.hr_novelties n set module_number=x.module_number
from numbered x where x.id=n.id and n.module_number is null;
alter table public.hr_novelties alter column module_number set not null;
create unique index if not exists hr_novelties_type_number_uidx
on public.hr_novelties(novelty_type,module_number);

create or replace function public.assign_hr_novelty_module_number()
returns trigger language plpgsql set search_path=public as $$
begin
 if new.module_number is null then
  perform pg_advisory_xact_lock(hashtext('hr_novelties:'||new.novelty_type));
  select coalesce(max(module_number),0)+1 into new.module_number
  from public.hr_novelties where novelty_type=new.novelty_type;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_novelty_module_number on public.hr_novelties;
create trigger trg_hr_novelty_module_number before insert on public.hr_novelties
for each row execute function public.assign_hr_novelty_module_number();

create table if not exists public.hr_disciplinary_history(
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.hr_employee_cases(id) on delete cascade,
 from_status text,
 to_status text not null,
 observation text not null default '',
 document_url text not null default '',
 responsible_user_id uuid not null references public.app_users(id),
 created_at timestamptz not null default now()
);
create index if not exists hr_disciplinary_history_case_idx
on public.hr_disciplinary_history(case_id,created_at);
alter table public.hr_disciplinary_history enable row level security;
revoke all on public.hr_disciplinary_history from anon,authenticated;

-- Los registros históricos previos reciben su evento inicial sin duplicarlo al reejecutar.
insert into public.hr_disciplinary_history(case_id,to_status,observation,responsible_user_id,created_at)
select c.id,'REGISTRADA','Expediente incorporado al historial',c.created_by,c.created_at
from public.hr_employee_cases c
where c.case_type='AMONESTACION'
and not exists(select 1 from public.hr_disciplinary_history h where h.case_id=c.id);

create or replace function public.hr_sync_case_from_novelty()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.source_table='hr_employee_cases' and new.source_id is not null then
  update public.hr_employee_cases
  set status=case
    when new.status in('RECHAZADA','ANULADA') then 'RECHAZADO'
    when new.status in('APROBADA','APLICADA_NOMINA') then 'APROBADO'
    else 'SOLICITADO' end,
   updated_at=now()
  where id=new.source_id and case_type in('PERMISO','VACACION');
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_sync_case_from_novelty on public.hr_novelties;
create trigger trg_hr_sync_case_from_novelty after update of status on public.hr_novelties
for each row execute function public.hr_sync_case_from_novelty();

create or replace function public.transition_hr_novelty(p_token text,p_id uuid,p_action text,p_observation text,p_document_url text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_item public.hr_novelties;v_employee public.hr_employees;v_next text;v_permission text;
begin
 v_user:=public.hr_authenticated_user(p_token);
 select * into v_item from public.hr_novelties where id=p_id for update;
 if v_user.id is null or v_item.id is null then return jsonb_build_object('success',false,'error','Novedad no encontrada o sesión inválida.');end if;
 select * into v_employee from public.hr_employees where id=v_item.employee_id;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','La novedad no pertenece a su unidad organizacional autorizada.');end if;
 if trim(coalesce(p_observation,''))='' then return jsonb_build_object('success',false,'error','La observación es obligatoria en cada transición.');end if;
 if p_action in('RECHAZAR','DEVOLVER') then
  v_next:=case p_action when 'RECHAZAR' then 'RECHAZADA' else 'DEVUELTA' end;
 elsif p_action='AVANZAR' and v_item.status='DEVUELTA' then v_next:='REGISTRADA';
 elsif p_action='AVANZAR' then
  v_next:=case v_item.status when 'REGISTRADA' then 'REVISADA_ENCARGADO' when 'REVISADA_ENCARGADO' then 'VALIDADA_RRHH' when 'VALIDADA_RRHH' then 'APROBADA' when 'APROBADA' then 'APLICADA_NOMINA' end;
 else return jsonb_build_object('success',false,'error','Acción inválida.');end if;
 if v_next is null or v_item.status in('APLICADA_NOMINA','RECHAZADA','ANULADA') then return jsonb_build_object('success',false,'error','No se permite saltar ni repetir etapas.');end if;
 v_permission:=case when v_item.novelty_type='VACACION' then 'aprobar_vacaciones' when v_item.novelty_type='PERMISO' then 'aprobar_permisos_laborales' else 'aprobar_recursos_humanos' end;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para procesar esta novedad.');end if;
 if v_next='APLICADA_NOMINA' and v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'procesar_nomina')::boolean,false) then return jsonb_build_object('success',false,'error','La aplicación en nómina requiere el permiso Procesar nómina.');end if;
 if p_action='AVANZAR' and v_item.source_table='hr_employee_cases' and not public.hr_medical_document_is_valid(v_item.source_id) then return jsonb_build_object('success',false,'error','El documento médico debe ser validado antes de avanzar.');end if;
 if v_next not in('DEVUELTA','RECHAZADA','REGISTRADA') and nullif(trim(coalesce(p_document_url,'')),'') is null then return jsonb_build_object('success',false,'error','Adjunte el documento que sustenta esta transición.');end if;
 update public.hr_novelties set status=v_next,updated_at=now() where id=p_id;
 if v_next='APLICADA_NOMINA' and v_item.source_table='hr_employee_cases' then perform public.create_hr_permission_payroll_adjustment(v_item.source_id);end if;
 insert into public.hr_novelty_history(novelty_id,from_status,to_status,observation,document_url,responsible_user_id)
 values(p_id,v_item.status,v_next,trim(p_observation),coalesce(p_document_url,''),v_user.id);
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'TRANSICION_NOVEDAD','Recursos Humanos',jsonb_build_object('employee_id',v_item.employee_id,'novelty_id',p_id,'from',v_item.status,'to',v_next,'observation',p_observation));
 return jsonb_build_object('success',true,'status',v_next);
end $$;

-- La creación de vacaciones valida disponibilidad anual, solapamientos y días laborables.
create or replace function public.save_hr_novelty(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_type text:=p_data->>'novelty_type';v_start date;v_end date;v_request date;v_days integer;v_id uuid;v_case_id uuid;v_acquired integer;v_reserved integer;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida.');end if;
 if v_type not in('PERMISO','VACACION','VIATICO','HORAS_EXTRAS','PRIMA_TRANSPORTE') then return jsonb_build_object('success',false,'error','Tipo de novedad inválido.');end if;
 if v_user.role<>'Administrador' and not(case when v_type='VACACION' then coalesce((v_user.permissions->>'registrar_vacaciones')::boolean,false) when v_type='PERMISO' then coalesce((v_user.permissions->>'registrar_permisos_laborales')::boolean,false) else coalesce((v_user.permissions->>'crear_recursos_humanos')::boolean,false) end) then return jsonb_build_object('success',false,'error','No posee permiso para registrar esta novedad.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid and employment_status<>'Desvinculado';
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado activo no encontrado.');end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','El empleado no pertenece a su unidad autorizada.');end if;
 v_request:=(p_data->>'request_date')::date;v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);
 if v_request is null or v_start is null or v_end<v_start then return jsonb_build_object('success',false,'error','Revise la fecha de solicitud y el período indicado.');end if;
 v_days:=public.hr_business_days(v_start,v_end);
 if v_days<1 then return jsonb_build_object('success',false,'error','El período no contiene días laborables.');end if;
 if exists(select 1 from public.hr_novelties where employee_id=v_employee.id and novelty_type in('PERMISO','VACACION') and status not in('RECHAZADA','ANULADA','DEVUELTA') and daterange(start_date,end_date,'[]')&&daterange(v_start,v_end,'[]')) then return jsonb_build_object('success',false,'error','El empleado ya posee una ausencia que coincide con este período.');end if;
 if v_type='VACACION' then
  v_acquired:=case when v_employee.hire_date is null or age(v_start,v_employee.hire_date)<interval '1 year' then 0 when age(v_start,v_employee.hire_date)>=interval '5 years' then 18 else 14 end;
  select coalesce(sum(work_days),0)::integer into v_reserved from public.hr_novelties where employee_id=v_employee.id and novelty_type='VACACION' and extract(year from start_date)=extract(year from v_start) and status not in('RECHAZADA','ANULADA','DEVUELTA');
  if v_days>greatest(v_acquired-v_reserved,0) then return jsonb_build_object('success',false,'error','La solicitud excede el balance de vacaciones disponible.');end if;
  if exists(select 1 from public.hr_novelties n join public.hr_employees e on e.id=n.employee_id where n.novelty_type='VACACION' and n.status not in('RECHAZADA','ANULADA','DEVUELTA') and daterange(n.start_date,n.end_date,'[]')&&daterange(v_start,v_end,'[]') and e.organization_unit_id=v_employee.organization_unit_id) then return jsonb_build_object('success',false,'error','Existe otra ausencia programada en la misma unidad para esas fechas.');end if;
 end if;
 if v_type='VACACION' then
  insert into public.hr_employee_cases(employee_id,case_type,request_date,category,start_date,end_date,day_count,paid,reason,observations,status,created_by)
  values(v_employee.id,'VACACION',v_request,'Vacaciones',v_start,v_end,v_days,true,trim(p_data->>'description'),'','SOLICITADO',v_user.id)
  returning id into v_case_id;
 end if;
 insert into public.hr_novelties(employee_id,novelty_type,request_date,start_date,end_date,work_days,amount,description,document_url,source_table,source_id,created_by)
 values(v_employee.id,v_type,v_request,v_start,v_end,v_days,greatest(0,coalesce(nullif(p_data->>'amount','')::numeric,0)),trim(p_data->>'description'),coalesce(p_data->>'document_url',''),case when v_case_id is not null then 'hr_employee_cases' end,v_case_id,v_user.id) returning id into v_id;
 insert into public.hr_novelty_history(novelty_id,to_status,observation,document_url,responsible_user_id)
 values(v_id,'REGISTRADA','Registro inicial',coalesce(p_data->>'document_url',''),v_user.id);
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'REGISTRAR_NOVEDAD','Recursos Humanos',jsonb_build_object('employee_id',v_employee.id,'novelty_id',v_id,'type',v_type,'work_days',v_days));
 return jsonb_build_object('success',true,'id',v_id);
exception when invalid_text_representation or not_null_violation then return jsonb_build_object('success',false,'error','Complete correctamente los campos obligatorios.');
end $$;

-- Añade el historial disciplinario completo a la consulta y garantiza transiciones ordenadas.
create or replace function public.list_hr_disciplinary_cases(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'consultar_expedientes_disciplinarios')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee autorización para consultar expedientes disciplinarios.');end if;
 return jsonb_build_object('success',true,
 'types',coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from public.hr_disciplinary_offense_types t where t.active),'[]'::jsonb),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'direction_name',e.direction_name,'department_name',e.department_name) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.module_number desc) from(
  select c.*,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,t.code offense_code,t.name offense_name,t.default_severity,
   coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'evidence_name',d.evidence_name,'evidence_url',d.evidence_url,'description',d.description,'uploaded_by_name',u.full_name,'created_at',d.created_at) order by d.created_at desc) from public.hr_disciplinary_evidence d join public.app_users u on u.id=d.uploaded_by where d.case_id=c.id),'[]'::jsonb) evidence,
   coalesce((select jsonb_agg(jsonb_build_object('from_status',h.from_status,'to_status',h.to_status,'observation',h.observation,'document_url',h.document_url,'responsible_name',u.full_name,'created_at',h.created_at) order by h.created_at) from public.hr_disciplinary_history h join public.app_users u on u.id=h.responsible_user_id where h.case_id=c.id),'[]'::jsonb) history,
   count(*) over(partition by c.employee_id,extract(year from c.start_date)) annual_case_count
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id left join public.hr_disciplinary_offense_types t on t.id=c.offense_type_id
  where c.case_type='AMONESTACION' and extract(year from c.start_date)=p_year and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x),'[]'::jsonb));end $$;

create or replace function public.hr_record_disciplinary_history()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_actor uuid;
begin
 if new.case_type='AMONESTACION' and (tg_op='INSERT' or old.disciplinary_status is distinct from new.disciplinary_status) then
  v_actor:=coalesce(nullif(current_setting('app.hr_actor_id',true),'')::uuid,new.created_by);
  insert into public.hr_disciplinary_history(case_id,from_status,to_status,observation,responsible_user_id)
  values(new.id,case when tg_op='UPDATE' then old.disciplinary_status else null end,new.disciplinary_status,
   coalesce(nullif(new.follow_up_notes,''),nullif(new.disciplinary_measure,''),nullif(new.employee_statement,''),nullif(new.observations,''),''),v_actor);
 end if;
 return new;
end $$;

-- Se registra el historial explícitamente desde la función existente mediante un disparador sencillo.
drop trigger if exists trg_hr_record_disciplinary_history on public.hr_employee_cases;
drop trigger if exists trg_hr_record_disciplinary_history_insert on public.hr_employee_cases;
create trigger trg_hr_record_disciplinary_history after update of disciplinary_status on public.hr_employee_cases
for each row execute function public.hr_record_disciplinary_history();
create trigger trg_hr_record_disciplinary_history_insert after insert on public.hr_employee_cases
for each row execute function public.hr_record_disciplinary_history();

grant execute on function public.transition_hr_novelty(text,uuid,text,text,text),public.save_hr_novelty(text,jsonb),public.list_hr_disciplinary_cases(text,integer) to anon,authenticated;
