-- Registro y validación con permisos independientes para Licencias Médicas.
create or replace function public.save_hr_permission_request(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_type public.hr_permission_types;v_start date;v_end date;v_hours numeric;v_days integer;v_id uuid;v_novelty uuid;v_used numeric;v_count integer;
begin
 v_user:=public.hr_authenticated_user(p_token);
 select * into v_type from public.hr_permission_types where id=(p_data->>'permission_type_id')::uuid and active;
 if v_user.id is null or v_type.id is null then return jsonb_build_object('success',false,'error','Sesión o tipo de licencia inválido.');end if;
 if v_user.role<>'Administrador' and (
   (v_type.requires_medical_document and not coalesce((v_user.permissions->>'registrar_licencias_medicas')::boolean,false))
   or
   (not v_type.requires_medical_document and not coalesce((v_user.permissions->>'registrar_permisos_laborales')::boolean,false))
 ) then return jsonb_build_object('success',false,'error','No posee permiso para registrar esta solicitud.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;
 if v_employee.id is null then return jsonb_build_object('success',false,'error','Empleado inválido.');end if;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Empleado fuera de su unidad autorizada.');end if;
 v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);v_hours:=greatest(0,coalesce(nullif(p_data->>'requested_hours','')::numeric,0));v_days:=case when v_hours>0 then 0 else public.hr_business_days(v_start,v_end) end;
 if v_hours>8 then return jsonb_build_object('success',false,'error','Las horas solicitadas no pueden superar ocho por día.');end if;
 if v_days=0 and v_hours=0 then return jsonb_build_object('success',false,'error','Indique días laborables u horas de permiso.');end if;
 if v_type.requires_medical_document and coalesce(p_data->>'medical_document_url','')!~*'^https?://' then return jsonb_build_object('success',false,'error','Este tipo de licencia requiere un documento médico válido.');end if;
 select coalesce(sum(day_count+requested_hours/8.0),0),count(*) into v_used,v_count from public.hr_employee_cases where employee_id=v_employee.id and permission_type_id=v_type.id and status not in('RECHAZADO','ANULADA') and extract(year from request_date)=extract(year from (p_data->>'request_date')::date);
 if v_type.max_days_per_request is not null and v_days+v_hours/8.0>v_type.max_days_per_request then return jsonb_build_object('success',false,'error','La solicitud supera el límite permitido por evento.');end if;
 if v_type.max_days_per_year is not null and v_used+v_days+v_hours/8.0>v_type.max_days_per_year then return jsonb_build_object('success',false,'error','El empleado supera el límite anual de este tipo.');end if;
 if v_type.max_requests_per_year is not null and v_count>=v_type.max_requests_per_year then return jsonb_build_object('success',false,'error','El empleado alcanzó el máximo anual de solicitudes de este tipo.');end if;
 insert into public.hr_employee_cases(employee_id,case_type,request_date,category,start_date,end_date,day_count,paid,reason,observations,status,created_by,permission_type_id,requested_hours,medical_document_url,medical_document_status)
 values(v_employee.id,'PERMISO',(p_data->>'request_date')::date,v_type.name,v_start,v_end,v_days,v_type.paid,trim(p_data->>'reason'),coalesce(p_data->>'observations',''),'SOLICITADO',v_user.id,v_type.id,v_hours,coalesce(p_data->>'medical_document_url',''),case when v_type.requires_medical_document then 'PENDIENTE' else 'NO_APLICA' end) returning id into v_id;
 insert into public.hr_novelties(employee_id,novelty_type,request_date,start_date,end_date,work_days,description,document_url,source_table,source_id,created_by) values(v_employee.id,'PERMISO',(p_data->>'request_date')::date,v_start,v_end,v_days,trim(p_data->>'reason'),coalesce(p_data->>'medical_document_url',''),'hr_employee_cases',v_id,v_user.id) returning id into v_novelty;
 insert into public.hr_novelty_history(novelty_id,to_status,observation,document_url,responsible_user_id) values(v_novelty,'REGISTRADA','Licencia médica registrada',coalesce(p_data->>'medical_document_url',''),v_user.id);
 return jsonb_build_object('success',true,'id',v_id,'novelty_id',v_novelty);
end $$;

create or replace function public.validate_hr_medical_document(p_token text,p_case_id uuid,p_valid boolean,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_case public.hr_employee_cases;
begin
 v_user:=public.hr_authenticated_user(p_token);
 select * into v_case from public.hr_employee_cases where id=p_case_id for update;
 if v_user.id is null or v_case.id is null or not exists(
   select 1 from public.hr_permission_types t where t.id=v_case.permission_type_id and t.requires_medical_document
 ) or (
   v_user.role<>'Administrador'
   and not coalesce((v_user.permissions->>'validar_licencias_medicas')::boolean,false)
 ) then
  return jsonb_build_object('success',false,'error','No posee permiso para validar documentos médicos.');
 end if;
 update public.hr_employee_cases
 set medical_document_status=case when p_valid then 'VALIDADO' else 'RECHAZADO' end,
     medical_validated_by=v_user.id,medical_validated_at=now(),decision_notes=coalesce(p_notes,''),updated_at=now()
 where id=p_case_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'VALIDAR_DOCUMENTO_MEDICO','Recursos Humanos',jsonb_build_object('employee_id',v_case.employee_id,'case_id',p_case_id,'valid',p_valid,'notes',p_notes));
 return jsonb_build_object('success',true);
end $$;

grant execute on function public.save_hr_permission_request(text,jsonb),public.validate_hr_medical_document(text,uuid,boolean,text) to anon,authenticated;
