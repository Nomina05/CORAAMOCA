-- Responsabilidades operativas y permisos individuales para reportes oficiales de RR. HH.
update public.app_users
set permissions=coalesce(permissions,'{}'::jsonb)||jsonb_build_object(
 'ver_registro_empleados_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_registro_empleados_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_acciones_personal_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_acciones_personal_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_vacantes_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_vacantes_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_reclutamiento_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_reclutamiento_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_desempeno_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_desempeno_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_capacitacion_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_capacitacion_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_asistencia_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_asistencia_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_nomina_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_nomina_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_presupuesto_nomina_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_presupuesto_nomina_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'ver_reportes_oficiales_rrhh',case when role='Administrador' then true else coalesce((permissions->>'ver_reportes_oficiales_rrhh')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_nomina',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_nomina')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_prima_transporte',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_prima_transporte')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_viaticos',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_viaticos')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_horas_extras',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_horas_extras')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_otros_descuentos',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_otros_descuentos')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_entradas_salidas',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_entradas_salidas')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_vacaciones',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_vacaciones')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_permisos',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_permisos')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_amonestaciones',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_amonestaciones')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_vacantes',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_vacantes')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end,
 'reporte_rrhh_presupuesto',case when role='Administrador' then true else coalesce((permissions->>'reporte_rrhh_presupuesto')::boolean,(permissions->>'ver_recursos_humanos')::boolean,false) end
),permissions_version=permissions_version+1,updated_at=now();

create or replace function public.list_hr_official_report(p_token text,p_year integer,p_month integer,p_report_type text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_permission text;v_source jsonb;v_key text;
begin
 v_user:=public.hr_authenticated_user(p_token);
 v_permission:=case upper(p_report_type)
  when 'NOMINA' then 'reporte_rrhh_nomina' when 'PRIMA_TRANSPORTE' then 'reporte_rrhh_prima_transporte'
  when 'VIATICOS' then 'reporte_rrhh_viaticos' when 'HORAS_EXTRAS' then 'reporte_rrhh_horas_extras'
  when 'OTROS_DESCUENTOS' then 'reporte_rrhh_otros_descuentos' when 'ENTRADAS_SALIDAS' then 'reporte_rrhh_entradas_salidas'
  when 'VACACION' then 'reporte_rrhh_vacaciones' when 'PERMISO' then 'reporte_rrhh_permisos'
  when 'AMONESTACION' then 'reporte_rrhh_amonestaciones' when 'VACANTES' then 'reporte_rrhh_vacantes'
  when 'PRESUPUESTO' then 'reporte_rrhh_presupuesto' else null end;
 if v_user.id is null or v_permission is null then return jsonb_build_object('success',false,'error','Reporte oficial inválido.');end if;
 if v_user.role<>'Administrador' and (not coalesce((v_user.permissions->>'ver_reportes_oficiales_rrhh')::boolean,false) or not coalesce((v_user.permissions->>v_permission)::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar este reporte oficial.');end if;
 v_source:=public.list_hr_official_reports(p_token,p_year,p_month);
 if not coalesce((v_source->>'success')::boolean,false) then return v_source;end if;
 v_key:=case when upper(p_report_type) in('NOMINA','PRIMA_TRANSPORTE','VIATICOS','HORAS_EXTRAS','OTROS_DESCUENTOS') then 'payroll' when upper(p_report_type) in('VACACION','PERMISO','AMONESTACION') then 'cases' when upper(p_report_type)='ENTRADAS_SALIDAS' then 'movements' when upper(p_report_type)='VACANTES' then 'vacancies' else 'budget' end;
 return jsonb_build_object('success',true,'year',p_year,'month',p_month,'report_type',upper(p_report_type),'rows',coalesce(v_source->v_key,'[]'::jsonb));
end $$;
grant execute on function public.list_hr_official_report(text,integer,integer,text) to anon,authenticated;
