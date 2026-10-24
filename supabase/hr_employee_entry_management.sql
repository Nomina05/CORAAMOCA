-- Ingreso de empleados por creación o sustitución de una vacante existente.
alter table public.hr_employees add column if not exists entry_type text not null default 'CREACION'
 check(entry_type in('CREACION','SUSTITUCION'));
alter table public.hr_employees add column if not exists entry_vacancy_id uuid references public.hr_vacancies(id);
alter table public.hr_employees add column if not exists referred_by_internal text not null default '';
create index if not exists hr_employees_entry_vacancy_idx on public.hr_employees(entry_vacancy_id) where entry_vacancy_id is not null;

create or replace function public.save_hr_employee_profile_with_entry(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_result jsonb;v_employee_id uuid;v_vacancy public.hr_vacancies;v_entry text:=upper(coalesce(nullif(p_data->>'entry_type',''),'CREACION'));v_is_new boolean:=nullif(p_data->>'id','') is null;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 if v_entry not in('CREACION','SUSTITUCION') then return jsonb_build_object('success',false,'error','Seleccione si el ingreso corresponde a creación o sustitución.');end if;
 if v_is_new and v_entry='SUSTITUCION' then
  if nullif(p_data->>'entry_vacancy_id','') is null then return jsonb_build_object('success',false,'error','Seleccione la vacante que ocupará el nuevo empleado.');end if;
  select * into v_vacancy from public.hr_vacancies where id=(p_data->>'entry_vacancy_id')::uuid and status='VACANTE' for update;
  if v_vacancy.id is null then return jsonb_build_object('success',false,'error','La vacante seleccionada ya no está disponible. Actualice la lista e intente nuevamente.');end if;
  p_data:=p_data||jsonb_build_object(
   'position_name',v_vacancy.position_name,'direction_name',v_vacancy.direction_name,'department_name',v_vacancy.department_name,
   'division_name',v_vacancy.division_name,'section_name',v_vacancy.section_name,'center_name',v_vacancy.center_name,
   'monthly_salary',case when coalesce((p_data->>'monthly_salary')::numeric,0)>0 then (p_data->>'monthly_salary')::numeric else v_vacancy.monthly_amount end
  );
 end if;
 v_result:=public.save_hr_employee_profile(p_token,p_data);
 if not coalesce((v_result->>'success')::boolean,false) then return v_result;end if;
 v_employee_id:=(v_result->>'id')::uuid;
 update public.hr_employees set entry_type=v_entry,entry_vacancy_id=case when v_entry='SUSTITUCION' then nullif(p_data->>'entry_vacancy_id','')::uuid else null end,
  referred_by_internal=trim(coalesce(p_data->>'referred_by_internal','')),updated_by=v_user.id,updated_at=now() where id=v_employee_id;
 if v_is_new and v_entry='SUSTITUCION' then
  update public.hr_vacancies set status='OCUPADA',filled_by_employee_id=v_employee_id,filled_at=now(),updated_at=now() where id=v_vacancy.id and status='VACANTE';
  if not found then raise exception 'La vacante fue ocupada por otro proceso.';end if;
 end if;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'REGISTRAR_TIPO_INGRESO','Recursos Humanos',jsonb_build_object('employee_id',v_employee_id,'entry_type',v_entry,'vacancy_id',case when v_entry='SUSTITUCION' then p_data->>'entry_vacancy_id' else null end,'has_internal_referral',nullif(trim(coalesce(p_data->>'referred_by_internal','')),'') is not null));
 return v_result||jsonb_build_object('entry_type',v_entry);
end $$;

revoke all on function public.save_hr_employee_profile_with_entry(text,jsonb) from public;
grant execute on function public.save_hr_employee_profile_with_entry(text,jsonb) to anon,authenticated;
