-- Fase 6: motor de nómina segmentado, validado, bloqueado y auditable.

alter table public.hr_payroll_batches add column if not exists subproduct integer not null default 0;
alter table public.hr_payroll_batches add column if not exists activity integer not null default 1;
alter table public.hr_payroll_batches add column if not exists reopened_at timestamptz;
alter table public.hr_payroll_batches add column if not exists reopened_by uuid references public.app_users(id);
alter table public.hr_payroll_batches add column if not exists reopen_reason text;

update public.hr_payroll_batches b set
 subproduct=coalesce((select min(l.subproduct) from public.hr_payroll_batch_lines l where l.batch_id=b.id),b.subproduct),
 activity=coalesce((select min(l.activity) from public.hr_payroll_batch_lines l where l.batch_id=b.id),b.activity),
 account_code=coalesce(nullif(b.account_code,''),(select min(l.account_code) from public.hr_payroll_batch_lines l where l.batch_id=b.id));

alter table public.hr_payroll_batches drop constraint if exists hr_payroll_batches_type_period_program_key;
create unique index if not exists hr_payroll_batches_engine_unique
 on public.hr_payroll_batches(payroll_type,payroll_year,payroll_month,execution_fund,program,subproduct,activity,coalesce(account_code,''));

alter table public.hr_payroll_adjustments add column if not exists applied_batch_id uuid references public.hr_payroll_batches(id);

create or replace function public.hr_apply_payroll_adjustments()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_permission numeric:=0;v_attendance numeric:=0;v_amount numeric:=0;v_batch public.hr_payroll_batches;
begin
 select * into v_batch from public.hr_payroll_batches where id=new.batch_id;
 if v_batch.payroll_type not in('NOMINA','NOMINA_FIJA') then return new;end if;
 select coalesce(sum(a.amount),0) into v_permission from public.hr_payroll_adjustments a
  where a.employee_id=new.employee_id and a.payroll_year=v_batch.payroll_year and a.payroll_month=v_batch.payroll_month
   and a.status<>'ANULADO' and (a.applied_batch_id is null or a.applied_batch_id=new.batch_id);
 if to_regclass('public.hr_attendance_payroll_novelties') is not null then
  select coalesce(sum(a.discount_amount),0) into v_attendance from public.hr_attendance_payroll_novelties a
   where a.employee_id=new.employee_id and a.payroll_year=v_batch.payroll_year and a.payroll_month=v_batch.payroll_month and a.status in('APROBADA','APLICADA');
 end if;
 v_amount:=least(v_permission+v_attendance,new.net_amount);
 if v_amount>0 then
  update public.hr_payroll_batch_lines set other_deductions=other_deductions+v_amount,total_deductions=total_deductions+v_amount,net_amount=greatest(net_amount-v_amount,0) where id=new.id;
  update public.hr_payroll_adjustments set status='APLICADO',applied_at=now(),applied_batch_id=new.batch_id
   where employee_id=new.employee_id and payroll_year=v_batch.payroll_year and payroll_month=v_batch.payroll_month and status='PENDIENTE';
  update public.hr_attendance_payroll_novelties set status='APLICADA',applied_at=now()
   where employee_id=new.employee_id and payroll_year=v_batch.payroll_year and payroll_month=v_batch.payroll_month and status='APROBADA';
 end if;
 return new;
end $$;

drop function if exists public.list_hr_payroll_processing(text,integer,integer,text,integer);
create or replace function public.list_hr_payroll_processing(p_token text,p_year integer,p_month integer,p_type text default 'NOMINA',p_program integer default 1,p_execution_fund text default null,p_subproduct integer default null,p_activity integer default null,p_account_code text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_batch uuid;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar nómina.');end if;
 select b.id into v_batch from public.hr_payroll_batches b where b.payroll_year=p_year and b.payroll_month=p_month and b.payroll_type=p_type and b.program=p_program
  and (p_execution_fund is null or b.execution_fund=p_execution_fund) and (p_subproduct is null or b.subproduct=p_subproduct) and (p_activity is null or b.activity=p_activity) and (p_account_code is null or b.account_code=p_account_code)
  order by b.created_at desc limit 1;
 return jsonb_build_object('success',true,
  'batch',(select to_jsonb(b) from public.hr_payroll_batches b where b.id=v_batch),
  'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.employee_name) from public.hr_payroll_batch_lines l where l.batch_id=v_batch),'[]'::jsonb),
  'configurations',coalesce((select jsonb_agg(to_jsonb(c) order by c.program,c.subproduct,c.activity,c.execution_fund,c.account_code) from(
    select distinct coalesce(a.execution_fund,e.execution_fund,'30') execution_fund,coalesce(a.program,e.program,1) program,coalesce(a.subproduct,e.subproduct,0) subproduct,coalesce(a.activity,e.activity,1) activity,
     coalesce(a.account_code,case p_type when 'NOMINA' then '2.1.1.1.01' when 'NOMINA_FIJA' then '2.1.1.1.01' when 'SUPLENCIA' then '2.1.1.2.03' when 'INTERINATO' then '2.1.1.2.11' when 'TEMPORAL' then '2.1.1.2.08' when 'PRIMA_TRANSPORTE' then '2.1.2.2.04' when 'HORAS_EXTRAS' then '2.1.2.2.03' when 'VIATICOS' then '2.2.3.1.01' end) account_code
    from public.hr_employees e
    left join public.hr_employee_payroll_assignments a on a.employee_id=e.id and a.active and a.payroll_type=case p_type when 'NOMINA' then 'FIJA' when 'NOMINA_FIJA' then 'FIJA' else p_type end
    where coalesce(e.payroll_status,e.employment_status,'') not in('INACTIVO','Inactivo','DESVINCULADO','Desvinculado')
     and ((p_type in('NOMINA','NOMINA_FIJA') and coalesce(a.gross_amount,e.monthly_salary,0)>0) or (p_type in('SUPLENCIA','INTERINATO','TEMPORAL') and coalesce(a.gross_amount,0)>0) or (p_type in('PRIMA_TRANSPORTE','VIATICOS','HORAS_EXTRAS') and exists(select 1 from public.hr_employee_benefits eb where eb.employee_id=e.id and eb.active and eb.benefit_type=p_type)))
  )c),'[]'::jsonb),
  'accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.code) from public.hr_payroll_account_catalog a where a.active),'[]'::jsonb));
end $$;

drop function if exists public.generate_hr_payroll(text,integer,integer,text,text,integer);
create or replace function public.generate_hr_payroll(p_token text,p_year integer,p_month integer,p_type text,p_account_code text,p_program integer,p_execution_fund text,p_subproduct integer,p_activity integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_batch uuid;v_date date:=make_date(p_year,p_month,1);v_ep numeric;v_epr numeric;v_es numeric;v_esr numeric;v_lr numeric;v_pc numeric;v_sc numeric;v_lc numeric;v_closed boolean;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'procesar_nomina')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso específico para procesar nómina.');end if;
 if nullif(trim(p_account_code),'') is null then return jsonb_build_object('success',false,'error','Seleccione una cuenta presupuestaria.');end if;
 select exists(select 1 from public.hr_payroll_batches where payroll_type=p_type and payroll_year=p_year and payroll_month=p_month and execution_fund=p_execution_fund and program=p_program and subproduct=p_subproduct and activity=p_activity and coalesce(account_code,'')=p_account_code and status='CERRADA') into v_closed;
 if v_closed then return jsonb_build_object('success',false,'error','La nómina está cerrada. Debe reabrirla con autorización y motivo antes de modificarla.');end if;
 select value into v_ep from public.hr_payroll_parameters where code='EMPLOYEE_PENSION_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_epr from public.hr_payroll_parameters where code='EMPLOYER_PENSION_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_es from public.hr_payroll_parameters where code='EMPLOYEE_SFS_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_esr from public.hr_payroll_parameters where code='EMPLOYER_SFS_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_lr from public.hr_payroll_parameters where code='EMPLOYER_LABOR_RISK_RATE' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_pc from public.hr_payroll_parameters where code='PENSION_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_sc from public.hr_payroll_parameters where code='SFS_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 select value into v_lc from public.hr_payroll_parameters where code='LABOR_RISK_CAP' and effective_from<=v_date order by effective_from desc limit 1;
 insert into public.hr_payroll_batches(payroll_type,payroll_year,payroll_month,account_code,program,execution_fund,subproduct,activity,created_by)
 values(p_type,p_year,p_month,p_account_code,p_program,p_execution_fund,p_subproduct,p_activity,v_user.id)
 on conflict(payroll_type,payroll_year,payroll_month,execution_fund,program,subproduct,activity,(coalesce(account_code,''))) do update set validation_status='PENDIENTE',validated_at=null,validated_by=null,status='BORRADOR'
 returning id into v_batch;
 update public.hr_payroll_adjustments set status='PENDIENTE',applied_at=null,applied_batch_id=null where applied_batch_id=v_batch;
 delete from public.hr_payroll_batch_lines where batch_id=v_batch;
 insert into public.hr_payroll_batch_lines(batch_id,employee_id,employee_code,document_number,employee_name,position_name,execution_fund,program,subproduct,activity,account_code,gross_salary,isr,insurance,employee_pension,employee_sfs,employer_pension,employer_sfs,employer_labor_risk,other_deductions,total_deductions,net_amount,calculation_snapshot)
 select v_batch,e.id,e.employee_code,coalesce(e.document_number,''),e.full_name,coalesce(a.position_name,e.position_name),p_execution_fund,p_program,p_subproduct,p_activity,p_account_code,g.gross,t.isr,0,
  case when p_type in('NOMINA','NOMINA_FIJA','SUPLENCIA','INTERINATO','TEMPORAL') then round(least(g.gross,v_pc)*v_ep,2) else 0 end,
  case when p_type in('NOMINA','NOMINA_FIJA','SUPLENCIA','INTERINATO','TEMPORAL') then round(least(g.gross,v_sc)*v_es,2) else 0 end,
  round(least(g.gross,v_pc)*v_epr,2),round(least(g.gross,v_sc)*v_esr,2),round(least(g.gross,v_lc)*v_lr,2),
  case when p_type in('NOMINA','NOMINA_FIJA','SUPLENCIA','INTERINATO','TEMPORAL') then coalesce(d.amount,0) else 0 end,
  t.isr+case when p_type in('NOMINA','NOMINA_FIJA','SUPLENCIA','INTERINATO','TEMPORAL') then round(least(g.gross,v_pc)*v_ep+least(g.gross,v_sc)*v_es,2)+coalesce(d.amount,0) else 0 end,
  g.gross-(t.isr+case when p_type in('NOMINA','NOMINA_FIJA','SUPLENCIA','INTERINATO','TEMPORAL') then round(least(g.gross,v_pc)*v_ep+least(g.gross,v_sc)*v_es,2)+coalesce(d.amount,0) else 0 end),
  jsonb_build_object('isr_method','ACUMULADO_MENSUAL_INCREMENTAL','employee_pension_rate',v_ep,'employee_sfs_rate',v_es,'employer_pension_rate',v_epr,'employer_sfs_rate',v_esr,'labor_risk_rate',v_lr,'pension_cap',v_pc,'sfs_cap',v_sc,'labor_risk_cap',v_lc,'other_deductions_detail',coalesce(d.detail,'{}'::jsonb))
 from public.hr_employees e
 left join lateral(select pa.* from public.hr_employee_payroll_assignments pa where pa.employee_id=e.id and pa.active and pa.payroll_type=case p_type when 'NOMINA' then 'FIJA' when 'NOMINA_FIJA' then 'FIJA' else p_type end and pa.execution_fund=p_execution_fund and pa.program=p_program and pa.subproduct=p_subproduct and pa.activity=p_activity and coalesce(pa.account_code,p_account_code)=p_account_code and (pa.start_date is null or pa.start_date<=v_date) and (pa.end_date is null or pa.end_date>=(v_date+interval '1 month - 1 day')::date) limit 1)a on true
 cross join lateral(select case when p_type in('NOMINA','NOMINA_FIJA') then coalesce(a.gross_amount,e.monthly_salary,0) when p_type in('SUPLENCIA','INTERINATO','TEMPORAL') then coalesce(a.gross_amount,0) else coalesce((select b.default_amount from public.hr_employee_benefits b where b.employee_id=e.id and b.active and b.benefit_type=p_type),0) end gross)g
 cross join lateral(select public.hr_calculate_incremental_isr_2026(e.id,v_date,p_type) isr)t
 left join lateral(select sum(z.amount) amount,jsonb_object_agg(z.deduction_type,z.amount) detail from(select ed.deduction_type,sum(ed.monthly_amount) amount from public.hr_employee_deductions ed where ed.employee_id=e.id and ed.active group by ed.deduction_type)z)d on true
 where coalesce(e.payroll_status,e.employment_status,'') not in('INACTIVO','Inactivo','DESVINCULADO','Desvinculado') and g.gross>0
  and coalesce(a.execution_fund,e.execution_fund,'30')=p_execution_fund and coalesce(a.program,e.program,1)=p_program and coalesce(a.subproduct,e.subproduct,0)=p_subproduct and coalesce(a.activity,e.activity,1)=p_activity;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'GENERAR_NOMINA','Recursos Humanos',jsonb_build_object('batch_id',v_batch,'type',p_type,'year',p_year,'month',p_month,'fund',p_execution_fund,'program',p_program,'subproduct',p_subproduct,'activity',p_activity,'account',p_account_code));
 return jsonb_build_object('success',true,'id',v_batch);
end $$;

create or replace function public.reopen_hr_payroll_batch(p_token text,p_batch_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_batch public.hr_payroll_batches;
begin
 v_user:=public.hr_authenticated_user(p_token);select * into v_batch from public.hr_payroll_batches where id=p_batch_id for update;
 if v_user.id is null or v_batch.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'reabrir_nomina')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso específico para reabrir nóminas.');end if;
 if v_batch.status<>'CERRADA' then return jsonb_build_object('success',false,'error','Solo se pueden reabrir nóminas cerradas.');end if;
 if length(trim(coalesce(p_reason,'')))<10 then return jsonb_build_object('success',false,'error','Indique un motivo de reapertura de al menos 10 caracteres.');end if;
 update public.hr_payroll_batches set status='BORRADOR',validation_status='PENDIENTE',validated_at=null,validated_by=null,reopened_at=now(),reopened_by=v_user.id,reopen_reason=trim(p_reason) where id=p_batch_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'REABRIR_NOMINA','Recursos Humanos',jsonb_build_object('batch_id',p_batch_id,'reason',trim(p_reason),'previous_closed_at',v_batch.closed_at,'previous_closed_by',v_batch.closed_by));
 return jsonb_build_object('success',true);
end $$;

create or replace function public.hr_protect_closed_payroll_line()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_batch uuid:=coalesce(new.batch_id,old.batch_id);
begin if exists(select 1 from public.hr_payroll_batches where id=v_batch and status='CERRADA') then raise exception 'La nómina está cerrada y no admite modificaciones.';end if;if tg_op='DELETE' then return old;end if;return new;end $$;
drop trigger if exists trg_hr_protect_closed_payroll_line on public.hr_payroll_batch_lines;
create trigger trg_hr_protect_closed_payroll_line before insert or update or delete on public.hr_payroll_batch_lines for each row execute function public.hr_protect_closed_payroll_line();

create or replace function public.hr_phase6_validation_extensions()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.execution_fund is null or trim(new.execution_fund)='' or new.program<0 or new.subproduct<0 or new.activity<0 or nullif(trim(new.account_code),'') is null then raise exception 'La línea requiere fondo, programa, subproducto, actividad y cuenta presupuestaria.';end if;
 if new.gross_salary<0 or new.total_deductions<0 or new.net_amount<0 then raise exception 'Los importes de la nómina no pueden ser negativos.';end if;return new;end $$;
drop trigger if exists trg_hr_phase6_validation_extensions on public.hr_payroll_batch_lines;
create trigger trg_hr_phase6_validation_extensions before insert or update on public.hr_payroll_batch_lines for each row execute function public.hr_phase6_validation_extensions();

grant execute on function public.list_hr_payroll_processing(text,integer,integer,text,integer,text,integer,integer,text),public.generate_hr_payroll(text,integer,integer,text,text,integer,text,integer,integer),public.reopen_hr_payroll_batch(text,uuid,text) to anon,authenticated;
