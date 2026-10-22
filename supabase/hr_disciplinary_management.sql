-- Gestión disciplinaria confidencial vinculada al expediente del colaborador.
create table if not exists public.hr_disciplinary_offense_types(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,default_severity text not null check(default_severity in('LEVE','MODERADA','GRAVE','MUY_GRAVE')),
 description text not null default '',active boolean not null default true,created_at timestamptz not null default now()
);
insert into public.hr_disciplinary_offense_types(code,name,default_severity,description) values
('INASISTENCIA','Inasistencia injustificada','MODERADA','Ausencia sin autorización ni soporte'),('TARDANZA','Incumplimiento de horario','LEVE','Tardanzas o salida anticipada'),
('INCUMPLIMIENTO','Incumplimiento de funciones','MODERADA','Incumplimiento de responsabilidades asignadas'),('NEGLIGENCIA','Negligencia en el servicio','GRAVE','Actuación negligente que afecta el servicio'),
('CONDUCTA','Conducta inadecuada','MODERADA','Incumplimiento de normas de conducta'),('INSUBORDINACION','Insubordinación','GRAVE','Desobediencia a instrucciones legítimas'),
('OTRA','Otra falta disciplinaria','LEVE','Clasificación definida por Recursos Humanos') on conflict(code) do update set name=excluded.name,default_severity=excluded.default_severity,description=excluded.description;

alter table public.hr_employee_cases add column if not exists offense_type_id uuid references public.hr_disciplinary_offense_types(id);
alter table public.hr_employee_cases add column if not exists recurrence_count integer not null default 0;
alter table public.hr_employee_cases add column if not exists employee_statement text not null default '';
alter table public.hr_employee_cases add column if not exists statement_received_at timestamptz;
alter table public.hr_employee_cases add column if not exists disciplinary_measure text not null default '';
alter table public.hr_employee_cases add column if not exists follow_up_notes text not null default '';
alter table public.hr_employee_cases add column if not exists follow_up_date date;
alter table public.hr_employee_cases add column if not exists close_date date;
alter table public.hr_employee_cases add column if not exists disciplinary_status text not null default 'REGISTRADA' check(disciplinary_status in('REGISTRADA','NOTIFICADA','DESCARGO_RECIBIDO','MEDIDA_APLICADA','EN_SEGUIMIENTO','CERRADA','ANULADA'));
alter table public.hr_employee_cases add column if not exists confidential boolean not null default true;

create table if not exists public.hr_disciplinary_evidence(
 id uuid primary key default gen_random_uuid(),case_id uuid not null references public.hr_employee_cases(id) on delete cascade,evidence_name text not null,evidence_url text not null,
 description text not null default '',uploaded_by uuid not null references public.app_users(id),created_at timestamptz not null default now()
);
create index if not exists hr_disciplinary_evidence_case_idx on public.hr_disciplinary_evidence(case_id,created_at desc);
alter table public.hr_disciplinary_offense_types enable row level security;alter table public.hr_disciplinary_evidence enable row level security;
revoke all on public.hr_disciplinary_offense_types,public.hr_disciplinary_evidence from anon,authenticated;

create or replace function public.list_hr_disciplinary_cases(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_amonestaciones')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee autorización para consultar expedientes disciplinarios confidenciales.');end if;
 return jsonb_build_object('success',true,
 'types',coalesce((select jsonb_agg(to_jsonb(t) order by t.name) from public.hr_disciplinary_offense_types t where t.active),'[]'::jsonb),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'direction_name',e.direction_name,'department_name',e.department_name) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.created_at desc) from(
  select c.*,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,t.code offense_code,t.name offense_name,t.default_severity,
   coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'evidence_name',d.evidence_name,'evidence_url',d.evidence_url,'description',d.description,'uploaded_by_name',u.full_name,'created_at',d.created_at) order by d.created_at desc) from public.hr_disciplinary_evidence d join public.app_users u on u.id=d.uploaded_by where d.case_id=c.id),'[]'::jsonb) evidence,
   count(*) over(partition by c.employee_id,extract(year from c.start_date)) annual_case_count
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id left join public.hr_disciplinary_offense_types t on t.id=c.offense_type_id
  where c.case_type='AMONESTACION' and extract(year from c.start_date)=p_year and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x),'[]'::jsonb));end $$;

create or replace function public.save_hr_disciplinary_case(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;v_employee public.hr_employees;v_type public.hr_disciplinary_offense_types;v_id uuid;v_recurrence integer;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'registrar_amonestaciones')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar expedientes disciplinarios.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;select * into v_type from public.hr_disciplinary_offense_types where id=(p_data->>'offense_type_id')::uuid and active;
 if v_employee.id is null or v_type.id is null then return jsonb_build_object('success',false,'error','Empleado o tipo de falta inválido.');end if;if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Empleado fuera de su unidad autorizada.');end if;
 select count(*)::integer into v_recurrence from public.hr_employee_cases where employee_id=v_employee.id and case_type='AMONESTACION' and offense_type_id=v_type.id and disciplinary_status<>'ANULADA';
 insert into public.hr_employee_cases(employee_id,case_type,request_date,category,start_date,end_date,day_count,severity,reason,observations,status,created_by,offense_type_id,recurrence_count,disciplinary_status,confidential)
 values(v_employee.id,'AMONESTACION',(p_data->>'incident_date')::date,v_type.name,(p_data->>'incident_date')::date,(p_data->>'incident_date')::date,1,coalesce(nullif(p_data->>'severity',''),v_type.default_severity),trim(p_data->>'reason'),coalesce(p_data->>'observations',''),'REGISTRADA',v_user.id,v_type.id,v_recurrence,'REGISTRADA',true) returning id into v_id;
 if coalesce(p_data->>'evidence_url','')~*'^https?://' then insert into public.hr_disciplinary_evidence(case_id,evidence_name,evidence_url,description,uploaded_by) values(v_id,coalesce(nullif(p_data->>'evidence_name',''),'Evidencia inicial'),p_data->>'evidence_url',coalesce(p_data->>'observations',''),v_user.id);end if;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_EXPEDIENTE_DISCIPLINARIO','Recursos Humanos',jsonb_build_object('employee_id',v_employee.id,'case_id',v_id,'offense_type',v_type.code,'severity',coalesce(nullif(p_data->>'severity',''),v_type.default_severity),'confidential',true));return jsonb_build_object('success',true,'id',v_id,'recurrence_count',v_recurrence);end $$;

create or replace function public.update_hr_disciplinary_case(p_token text,p_case_id uuid,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;v_case public.hr_employee_cases;v_employee public.hr_employees;v_status text;begin v_user:=public.hr_authenticated_user(p_token);select * into v_case from public.hr_employee_cases where id=p_case_id and case_type='AMONESTACION' for update;
 if v_user.id is null or v_case.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'notificar_amonestaciones')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para gestionar este expediente confidencial.');end if;select * into v_employee from public.hr_employees where id=v_case.employee_id;if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Expediente fuera de su unidad autorizada.');end if;
 if p_action='NOTIFICAR' then v_status:='NOTIFICADA';elsif p_action='DESCARGO' then if trim(coalesce(p_data->>'employee_statement',''))='' then return jsonb_build_object('success',false,'error','El descargo del empleado es obligatorio.');end if;v_status:='DESCARGO_RECIBIDO';
 elsif p_action='MEDIDA' then if trim(coalesce(p_data->>'disciplinary_measure',''))='' then return jsonb_build_object('success',false,'error','Indique la medida disciplinaria aplicada.');end if;v_status:='MEDIDA_APLICADA';
 elsif p_action='SEGUIMIENTO' then v_status:='EN_SEGUIMIENTO';elsif p_action='CERRAR' then if trim(coalesce(p_data->>'follow_up_notes',''))='' then return jsonb_build_object('success',false,'error','Documente el resultado del seguimiento antes de cerrar.');end if;v_status:='CERRADA';else return jsonb_build_object('success',false,'error','Acción disciplinaria inválida.');end if;
 update public.hr_employee_cases set disciplinary_status=v_status,status=case when v_status='NOTIFICADA' then 'NOTIFICADA' else status end,employee_statement=case when p_action='DESCARGO' then p_data->>'employee_statement' else employee_statement end,statement_received_at=case when p_action='DESCARGO' then now() else statement_received_at end,disciplinary_measure=case when p_action='MEDIDA' then p_data->>'disciplinary_measure' else disciplinary_measure end,follow_up_notes=case when p_action in('SEGUIMIENTO','CERRAR') then coalesce(p_data->>'follow_up_notes','') else follow_up_notes end,follow_up_date=case when p_action='SEGUIMIENTO' then coalesce(nullif(p_data->>'follow_up_date','')::date,current_date) else follow_up_date end,close_date=case when p_action='CERRAR' then current_date else close_date end,updated_at=now() where id=p_case_id;
 if coalesce(p_data->>'evidence_url','')~*'^https?://' then insert into public.hr_disciplinary_evidence(case_id,evidence_name,evidence_url,description,uploaded_by) values(p_case_id,coalesce(nullif(p_data->>'evidence_name',''),'Soporte de '||lower(v_status)),p_data->>'evidence_url',coalesce(p_data->>'follow_up_notes',p_data->>'employee_statement',''),v_user.id);end if;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'ACTUALIZAR_EXPEDIENTE_DISCIPLINARIO','Recursos Humanos',jsonb_build_object('employee_id',v_case.employee_id,'case_id',p_case_id,'from',v_case.disciplinary_status,'to',v_status,'confidential',true));return jsonb_build_object('success',true,'status',v_status);end $$;

grant execute on function public.list_hr_disciplinary_cases(text,integer),public.save_hr_disciplinary_case(text,jsonb),public.update_hr_disciplinary_case(text,uuid,text,jsonb) to anon,authenticated;
