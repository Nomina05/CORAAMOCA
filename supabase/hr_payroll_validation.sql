-- Validación y cierre controlado de nómina integrada.
alter table public.hr_employee_benefits add column if not exists taxable boolean not null default false;
alter table public.hr_payroll_batches add column if not exists validation_status text not null default 'PENDIENTE' check(validation_status in('PENDIENTE','CON_ERRORES','CON_ADVERTENCIAS','LISTA'));
alter table public.hr_payroll_batches add column if not exists validated_at timestamptz;
alter table public.hr_payroll_batches add column if not exists validated_by uuid references public.app_users(id);
alter table public.hr_payroll_batches add column if not exists closed_at timestamptz;
alter table public.hr_payroll_batches add column if not exists closed_by uuid references public.app_users(id);

create table if not exists public.hr_payroll_validation_results(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.hr_payroll_batches(id) on delete cascade,
 severity text not null check(severity in('ERROR','ADVERTENCIA','DIFERENCIA','INFORMACION')),code text not null,
 employee_id uuid references public.hr_employees(id),employee_name text not null default '',message text not null,
 current_value numeric(18,2),previous_value numeric(18,2),detail jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create index if not exists hr_payroll_validation_batch_idx on public.hr_payroll_validation_results(batch_id,severity,created_at);
alter table public.hr_payroll_validation_results enable row level security;
revoke all on public.hr_payroll_validation_results from anon,authenticated;

create or replace function public.validate_hr_payroll_batch(p_token text,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_batch public.hr_payroll_batches;v_start date;v_end date;v_previous uuid;v_errors integer;v_warnings integer;v_differences integer;v_status text;
begin
 v_user:=public.hr_authenticated_user(p_token);select * into v_batch from public.hr_payroll_batches where id=p_batch_id for update;
 if v_user.id is null or v_batch.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'procesar_nomina')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso específico para validar esta nómina.');end if;
 if v_batch.status='CERRADA' then return jsonb_build_object('success',false,'error','La nómina ya está cerrada.');end if;
 v_start:=make_date(v_batch.payroll_year,v_batch.payroll_month,1);v_end:=(v_start+interval '1 month - 1 day')::date;
 select id into v_previous from public.hr_payroll_batches where payroll_type=v_batch.payroll_type and program=v_batch.program and (payroll_year*100+payroll_month)<(v_batch.payroll_year*100+v_batch.payroll_month) order by payroll_year desc,payroll_month desc limit 1;
 delete from public.hr_payroll_validation_results where batch_id=p_batch_id;
 if not exists(select 1 from public.hr_payroll_batch_lines where batch_id=p_batch_id) then insert into public.hr_payroll_validation_results(batch_id,severity,code,message) values(p_batch_id,'ERROR','SIN_EMPLEADOS','La nómina no contiene empleados.');end if;
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,current_value,detail)
 select p_batch_id,'ERROR','DATOS_INCOMPLETOS',l.employee_id,l.employee_name,'Falta cédula, cuenta presupuestaria o salario válido.',l.gross_salary,jsonb_build_object('document_number',l.document_number,'account_code',l.account_code)
 from public.hr_payroll_batch_lines l where l.batch_id=p_batch_id and (trim(l.document_number)='' or nullif(trim(l.account_code),'') is null or l.gross_salary<=0);
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,current_value)
 select p_batch_id,'ERROR','NETO_INVALIDO',l.employee_id,l.employee_name,'El total de descuentos supera el ingreso bruto.',l.net_amount from public.hr_payroll_batch_lines l where l.batch_id=p_batch_id and l.net_amount<0;
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,detail)
 select p_batch_id,'ADVERTENCIA','ACCION_PENDIENTE',a.employee_id,e.full_name,'Existe una acción de personal con fecha efectiva dentro del período que aún no está aprobada.',jsonb_build_object('action_type',a.action_type,'effective_date',a.effective_date,'status',a.status)
 from public.hr_personnel_actions a join public.hr_employees e on e.id=a.employee_id where a.status not in('APROBADA','ANULADA') and a.effective_date between v_start and v_end;
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,detail)
 select p_batch_id,'ADVERTENCIA','MOVIMIENTO_PERIODO',e.id,e.full_name,case when e.hire_date between v_start and v_end then 'Empleado con entrada durante el período.' else 'Empleado con salida durante el período.' end,jsonb_build_object('hire_date',e.hire_date,'termination_date',e.termination_date)
 from public.hr_employees e join public.hr_payroll_batch_lines l on l.employee_id=e.id and l.batch_id=p_batch_id where e.hire_date between v_start and v_end or e.termination_date between v_start and v_end;
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,current_value,detail)
 select p_batch_id,'INFORMACION','PERMISO_NO_REMUNERADO',a.employee_id,l.employee_name,'Descuento por permiso no remunerado integrado en la nómina.',a.amount,jsonb_build_object('source_case_id',a.source_case_id,'status',a.status)
 from public.hr_payroll_adjustments a join public.hr_payroll_batch_lines l on l.employee_id=a.employee_id and l.batch_id=p_batch_id where a.payroll_year=v_batch.payroll_year and a.payroll_month=v_batch.payroll_month and a.status<>'ANULADO';
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,current_value,previous_value,detail)
 select p_batch_id,'DIFERENCIA','VARIACION_MES_ANTERIOR',c.employee_id,c.employee_name,'Variación superior al 10 % respecto a la nómina anterior.',c.net_amount,p.net_amount,jsonb_build_object('gross_current',c.gross_salary,'gross_previous',p.gross_salary,'variation_percent',round((c.net_amount-p.net_amount)/nullif(p.net_amount,0)*100,2))
 from public.hr_payroll_batch_lines c join public.hr_payroll_batch_lines p on p.batch_id=v_previous and p.employee_id=c.employee_id where c.batch_id=p_batch_id and p.net_amount<>0 and abs(c.net_amount-p.net_amount)/abs(p.net_amount)>.10;
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,current_value)
 select p_batch_id,'DIFERENCIA','NUEVO_EN_NOMINA',c.employee_id,c.employee_name,'Empleado no presente en la nómina anterior.',c.net_amount from public.hr_payroll_batch_lines c where c.batch_id=p_batch_id and v_previous is not null and not exists(select 1 from public.hr_payroll_batch_lines p where p.batch_id=v_previous and p.employee_id=c.employee_id);
 insert into public.hr_payroll_validation_results(batch_id,severity,code,employee_id,employee_name,message,previous_value)
 select p_batch_id,'DIFERENCIA','SALIDA_DE_NOMINA',p.employee_id,p.employee_name,'Empleado presente el mes anterior y ausente en esta nómina.',p.net_amount from public.hr_payroll_batch_lines p where p.batch_id=v_previous and not exists(select 1 from public.hr_payroll_batch_lines c where c.batch_id=p_batch_id and c.employee_id=p.employee_id);
 select count(*) filter(where severity='ERROR'),count(*) filter(where severity='ADVERTENCIA'),count(*) filter(where severity='DIFERENCIA') into v_errors,v_warnings,v_differences from public.hr_payroll_validation_results where batch_id=p_batch_id;
 v_status:=case when v_errors>0 then 'CON_ERRORES' when v_warnings>0 or v_differences>0 then 'CON_ADVERTENCIAS' else 'LISTA' end;
 update public.hr_payroll_batches set validation_status=v_status,validated_at=now(),validated_by=v_user.id,status=case when v_errors=0 then 'VALIDADA' else 'BORRADOR' end where id=p_batch_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'VALIDAR_NOMINA','Recursos Humanos',jsonb_build_object('batch_id',p_batch_id,'status',v_status,'errors',v_errors,'warnings',v_warnings,'differences',v_differences));
 return jsonb_build_object('success',true,'status',v_status,'errors',v_errors,'warnings',v_warnings,'differences',v_differences);
end $$;

create or replace function public.list_hr_payroll_validation(p_token text,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;v_batch public.hr_payroll_batches;begin v_user:=public.hr_authenticated_user(p_token);select * into v_batch from public.hr_payroll_batches where id=p_batch_id;
 if v_user.id is null or v_batch.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar la validación.');end if;
 return jsonb_build_object('success',true,'batch',to_jsonb(v_batch),'issues',coalesce((select jsonb_agg(to_jsonb(r) order by case r.severity when 'ERROR' then 1 when 'ADVERTENCIA' then 2 when 'DIFERENCIA' then 3 else 4 end,r.employee_name) from public.hr_payroll_validation_results r where r.batch_id=p_batch_id),'[]'::jsonb),'sources',jsonb_build_array('Salario vigente','Asignaciones, interinatos y suplencias','Prima de transporte y viáticos gravados','Descuentos adicionales','ISR acumulado mensual','TSS y SFS','Entradas y salidas','Acciones de personal aprobadas','Permisos no remunerados'));
end $$;

create or replace function public.close_hr_payroll_batch(p_token text,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;v_batch public.hr_payroll_batches;begin v_user:=public.hr_authenticated_user(p_token);select * into v_batch from public.hr_payroll_batches where id=p_batch_id for update;
 if v_user.id is null or v_batch.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'cerrar_nomina')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso específico para cerrar esta nómina.');end if;
 if v_batch.validation_status not in('LISTA','CON_ADVERTENCIAS') or v_batch.validated_at is null then return jsonb_build_object('success',false,'error','Debe validar la nómina y corregir todos los errores antes de cerrarla.');end if;
 if exists(select 1 from public.hr_payroll_validation_results where batch_id=p_batch_id and severity='ERROR') then return jsonb_build_object('success',false,'error','La nómina conserva errores críticos.');end if;
 update public.hr_payroll_batches set status='CERRADA',closed_at=now(),closed_by=v_user.id where id=p_batch_id;insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CERRAR_NOMINA','Recursos Humanos',jsonb_build_object('batch_id',p_batch_id,'validation_status',v_batch.validation_status));return jsonb_build_object('success',true);
end $$;

create or replace function public.hr_invalidate_payroll_validation() returns trigger language plpgsql security definer set search_path=public as $$declare v_batch uuid:=coalesce(new.batch_id,old.batch_id);begin update public.hr_payroll_batches set validation_status='PENDIENTE',validated_at=null,validated_by=null,status=case when status='CERRADA' then status else 'BORRADOR' end where id=v_batch and status<>'CERRADA';return null;end $$;
drop trigger if exists trg_hr_invalidate_payroll_validation on public.hr_payroll_batch_lines;
create trigger trg_hr_invalidate_payroll_validation after insert or update or delete on public.hr_payroll_batch_lines for each row execute function public.hr_invalidate_payroll_validation();

grant execute on function public.validate_hr_payroll_batch(text,uuid),public.list_hr_payroll_validation(text,uuid),public.close_hr_payroll_batch(text,uuid) to anon,authenticated;
