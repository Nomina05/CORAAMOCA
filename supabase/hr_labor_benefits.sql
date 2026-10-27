-- Cálculo y flujo de prestaciones laborales y derechos adquiridos.
-- Las cifras son preliminares hasta completar revisión y aprobación institucional.

create sequence if not exists public.hr_labor_benefit_number_seq start 1;

create table if not exists public.hr_labor_benefit_calculations(
 id uuid primary key default gen_random_uuid(),
 calculation_number bigint not null unique default nextval('public.hr_labor_benefit_number_seq'),
 employee_id uuid not null references public.hr_employees(id),
 entry_date date not null,
 exit_date date not null,
 termination_reason text not null,
 calculation_type text not null default 'ORDINARIO' check(calculation_type in ('ORDINARIO','INTERMITENTE')),
 monthly_salary numeric(16,2) not null check(monthly_salary>0),
 annual_earned_salary numeric(16,2) not null default 0 check(annual_earned_salary>=0),
 daily_salary numeric(16,2) not null default 0,
 service_days integer not null default 0,
 notice_included boolean not null default true,
 notice_given boolean not null default false,
 notice_days numeric(8,2) not null default 0,
 notice_amount numeric(16,2) not null default 0,
 severance_included boolean not null default true,
 severance_days numeric(8,2) not null default 0,
 severance_amount numeric(16,2) not null default 0,
 vacation_taken boolean not null default false,
 vacation_days numeric(8,2) not null default 0,
 vacation_amount numeric(16,2) not null default 0,
 christmas_included boolean not null default true,
 christmas_amount numeric(16,2) not null default 0,
 other_income numeric(16,2) not null default 0,
 isr_withholding numeric(16,2) not null default 0,
 other_deductions numeric(16,2) not null default 0,
 gross_total numeric(16,2) not null default 0,
 net_total numeric(16,2) not null default 0,
 status text not null default 'BORRADOR' check(status in ('BORRADOR','REVISADA','APROBADA','PAGADA','ANULADA')),
 notes text not null default '',
 created_by uuid not null references public.app_users(id),
 reviewed_by uuid references public.app_users(id),
 approved_by uuid references public.app_users(id),
 paid_by uuid references public.app_users(id),
 reviewed_at timestamptz,
 approved_at timestamptz,
 paid_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(exit_date>=entry_date),
 check(net_total>=0)
);
create index if not exists hr_labor_benefit_employee_idx on public.hr_labor_benefit_calculations(employee_id,created_at desc);
alter table public.hr_labor_benefit_calculations enable row level security;
revoke all on public.hr_labor_benefit_calculations from anon,authenticated;

create table if not exists public.hr_labor_benefit_audit(
 id bigint generated always as identity primary key,
 calculation_id uuid not null references public.hr_labor_benefit_calculations(id) on delete cascade,
 action text not null,
 from_status text,
 to_status text,
 comments text not null default '',
 actor_user_id uuid not null references public.app_users(id),
 created_at timestamptz not null default now()
);
alter table public.hr_labor_benefit_audit enable row level security;
revoke all on public.hr_labor_benefit_audit from anon,authenticated;

create or replace function public.hr_benefit_notice_days(p_service_days integer)
returns numeric language sql immutable as $$select case when p_service_days<90 then 0 when p_service_days<180 then 7 when p_service_days<365 then 14 else 28 end::numeric$$;

create or replace function public.hr_benefit_severance_days(p_entry date,p_exit date)
returns numeric language plpgsql immutable as $$
declare v_years integer;v_anniversary date;v_remaining integer;v_days numeric:=0;
begin
 if p_exit<p_entry or p_exit-p_entry<90 then return 0;end if;
 v_years:=extract(year from age(p_exit,p_entry));
 if v_years>0 then v_days:=v_years*(case when v_years>5 then 23 else 21 end);end if;
 v_anniversary:=p_entry+(v_years||' years')::interval;
 v_remaining:=p_exit-v_anniversary::date;
 if v_remaining>=180 then v_days:=v_days+13;elsif v_remaining>=90 then v_days:=v_days+6;end if;
 return v_days;
end$$;

create or replace function public.list_hr_labor_benefits(p_token text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_items jsonb;v_employees jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_prestaciones_laborales')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar prestaciones laborales.');end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'direction_name',coalesce(o.unit_name,''),'department_name',coalesce(e.department_name,''),'hire_date',e.hire_date,'termination_date',e.termination_date,'termination_type',e.termination_type,'monthly_salary',case when v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_salarios')::boolean,false) then e.monthly_salary else null end) order by e.full_name),'[]'::jsonb) into v_employees
 from public.hr_employees e left join public.organization_units o on o.id=e.organization_unit_id where public.hr_employee_in_user_scope(v_user,e);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from(
  select c.*,e.employee_code,e.full_name,e.position_name,coalesce(o.unit_name,'') direction_name,
   creator.full_name created_by_name,reviewer.full_name reviewed_by_name,approver.full_name approved_by_name,payer.full_name paid_by_name,
   coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from (select au.action,au.from_status,au.to_status,au.comments,u.full_name actor_name,au.created_at from public.hr_labor_benefit_audit au join public.app_users u on u.id=au.actor_user_id where au.calculation_id=c.id order by au.created_at)a),'[]'::jsonb) audit
  from public.hr_labor_benefit_calculations c join public.hr_employees e on e.id=c.employee_id left join public.organization_units o on o.id=e.organization_unit_id
  join public.app_users creator on creator.id=c.created_by left join public.app_users reviewer on reviewer.id=c.reviewed_by left join public.app_users approver on approver.id=c.approved_by left join public.app_users payer on payer.id=c.paid_by
  where (p_year is null or extract(year from c.exit_date)=p_year) and public.hr_employee_in_user_scope(v_user,e)
 )x;
 return jsonb_build_object('success',true,'items',v_items,'employees',v_employees);
end$$;

create or replace function public.save_hr_labor_benefit(p_token text,p_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_previous public.hr_labor_benefit_calculations;v_id uuid;v_entry date;v_exit date;v_salary numeric;v_daily numeric;v_service integer;v_notice_days numeric;v_severance_days numeric;v_vacation_days numeric;v_notice numeric;v_severance numeric;v_vacation numeric;v_christmas numeric;v_other numeric;v_isr numeric;v_deductions numeric;v_gross numeric;v_net numeric;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'calcular_prestaciones_laborales')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para calcular prestaciones laborales.');end if;
 select * into v_employee from public.hr_employees where id=nullif(p_data->>'employee_id','')::uuid;
 if v_employee.id is null or not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Empleado no encontrado o fuera de su alcance.');end if;
 if p_id is not null then select * into v_previous from public.hr_labor_benefit_calculations where id=p_id for update;if v_previous.id is null then return jsonb_build_object('success',false,'error','Cálculo no encontrado.');end if;if v_previous.status<>'BORRADOR' then return jsonb_build_object('success',false,'error','Solo puede modificar cálculos en borrador.');end if;end if;
 v_entry:=coalesce(nullif(p_data->>'entry_date','')::date,v_employee.hire_date);v_exit:=nullif(p_data->>'exit_date','')::date;v_salary:=coalesce(nullif(p_data->>'monthly_salary','')::numeric,v_employee.monthly_salary,0);
 if v_entry is null or v_exit is null or v_exit<v_entry or v_salary<=0 then return jsonb_build_object('success',false,'error','Revise fecha de entrada, fecha de salida y salario mensual.');end if;
 v_service:=v_exit-v_entry;v_daily:=round(v_salary/23.83,2);
 v_notice_days:=case when coalesce((p_data->>'notice_included')::boolean,true) and not coalesce((p_data->>'notice_given')::boolean,false) then public.hr_benefit_notice_days(v_service) else 0 end;
 v_severance_days:=case when coalesce((p_data->>'severance_included')::boolean,true) then public.hr_benefit_severance_days(v_entry,v_exit) else 0 end;
 v_vacation_days:=case when coalesce((p_data->>'vacation_taken')::boolean,false) then 0 else coalesce(nullif(p_data->>'vacation_days','')::numeric,case when v_service>=1825 then 18 when v_service>=365 then 14 else round(14*v_service/365.0,2) end) end;
 v_notice:=round(v_daily*v_notice_days,2);v_severance:=round(v_daily*v_severance_days,2);v_vacation:=round(v_daily*v_vacation_days,2);
 v_christmas:=case when coalesce((p_data->>'christmas_included')::boolean,true) then round(coalesce(nullif(p_data->>'annual_earned_salary','')::numeric,0)/12,2) else 0 end;
 v_other:=greatest(coalesce(nullif(p_data->>'other_income','')::numeric,0),0);v_isr:=greatest(coalesce(nullif(p_data->>'isr_withholding','')::numeric,0),0);v_deductions:=greatest(coalesce(nullif(p_data->>'other_deductions','')::numeric,0),0);
 v_gross:=v_notice+v_severance+v_vacation+v_christmas+v_other;v_net:=greatest(v_gross-v_isr-v_deductions,0);
 if p_id is null then insert into public.hr_labor_benefit_calculations(employee_id,entry_date,exit_date,termination_reason,calculation_type,monthly_salary,annual_earned_salary,daily_salary,service_days,notice_included,notice_given,notice_days,notice_amount,severance_included,severance_days,severance_amount,vacation_taken,vacation_days,vacation_amount,christmas_included,christmas_amount,other_income,isr_withholding,other_deductions,gross_total,net_total,notes,created_by)
  values(v_employee.id,v_entry,v_exit,trim(coalesce(p_data->>'termination_reason','No especificada')),coalesce(nullif(p_data->>'calculation_type',''),'ORDINARIO'),v_salary,coalesce(nullif(p_data->>'annual_earned_salary','')::numeric,0),v_daily,v_service,coalesce((p_data->>'notice_included')::boolean,true),coalesce((p_data->>'notice_given')::boolean,false),v_notice_days,v_notice,coalesce((p_data->>'severance_included')::boolean,true),v_severance_days,v_severance,coalesce((p_data->>'vacation_taken')::boolean,false),v_vacation_days,v_vacation,coalesce((p_data->>'christmas_included')::boolean,true),v_christmas,v_other,v_isr,v_deductions,v_gross,v_net,coalesce(p_data->>'notes',''),v_user.id) returning id into v_id;
 else v_id:=p_id;update public.hr_labor_benefit_calculations set entry_date=v_entry,exit_date=v_exit,termination_reason=trim(coalesce(p_data->>'termination_reason','No especificada')),calculation_type=coalesce(nullif(p_data->>'calculation_type',''),'ORDINARIO'),monthly_salary=v_salary,annual_earned_salary=coalesce(nullif(p_data->>'annual_earned_salary','')::numeric,0),daily_salary=v_daily,service_days=v_service,notice_included=coalesce((p_data->>'notice_included')::boolean,true),notice_given=coalesce((p_data->>'notice_given')::boolean,false),notice_days=v_notice_days,notice_amount=v_notice,severance_included=coalesce((p_data->>'severance_included')::boolean,true),severance_days=v_severance_days,severance_amount=v_severance,vacation_taken=coalesce((p_data->>'vacation_taken')::boolean,false),vacation_days=v_vacation_days,vacation_amount=v_vacation,christmas_included=coalesce((p_data->>'christmas_included')::boolean,true),christmas_amount=v_christmas,other_income=v_other,isr_withholding=v_isr,other_deductions=v_deductions,gross_total=v_gross,net_total=v_net,notes=coalesce(p_data->>'notes',''),updated_at=now() where id=v_id;end if;
 insert into public.hr_labor_benefit_audit(calculation_id,action,from_status,to_status,comments,actor_user_id)values(v_id,case when p_id is null then 'CREAR' else 'MODIFICAR' end,'BORRADOR','BORRADOR',coalesce(p_data->>'notes',''),v_user.id);
 return jsonb_build_object('success',true,'id',v_id,'gross_total',v_gross,'net_total',v_net);
end$$;

create or replace function public.advance_hr_labor_benefit(p_token text,p_id uuid,p_action text,p_comments text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_item public.hr_labor_benefit_calculations;v_next text;v_permission text;
begin
 v_user:=public.hr_authenticated_user(p_token);select * into v_item from public.hr_labor_benefit_calculations where id=p_id for update;
 if v_user.id is null or v_item.id is null then return jsonb_build_object('success',false,'error','Registro o sesión no válida.');end if;
 v_next:=case when p_action='REVISAR' and v_item.status='BORRADOR' then 'REVISADA' when p_action='APROBAR' and v_item.status='REVISADA' then 'APROBADA' when p_action='PAGAR' and v_item.status='APROBADA' then 'PAGADA' when p_action='ANULAR' and v_item.status in ('BORRADOR','REVISADA','APROBADA') then 'ANULADA' end;
 if v_next is null then return jsonb_build_object('success',false,'error','La transición solicitada no corresponde al estado actual.');end if;
 v_permission:=case p_action when 'REVISAR' then 'revisar_prestaciones_laborales' when 'APROBAR' then 'aprobar_prestaciones_laborales' when 'PAGAR' then 'pagar_prestaciones_laborales' else 'aprobar_prestaciones_laborales' end;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para esta transición.');end if;
 if p_action='ANULAR' and trim(coalesce(p_comments,''))='' then return jsonb_build_object('success',false,'error','Debe indicar el motivo de anulación.');end if;
 update public.hr_labor_benefit_calculations set status=v_next,reviewed_by=case when p_action='REVISAR' then v_user.id else reviewed_by end,reviewed_at=case when p_action='REVISAR' then now() else reviewed_at end,approved_by=case when p_action='APROBAR' then v_user.id else approved_by end,approved_at=case when p_action='APROBAR' then now() else approved_at end,paid_by=case when p_action='PAGAR' then v_user.id else paid_by end,paid_at=case when p_action='PAGAR' then now() else paid_at end,updated_at=now() where id=p_id;
 insert into public.hr_labor_benefit_audit(calculation_id,action,from_status,to_status,comments,actor_user_id)values(p_id,p_action,v_item.status,v_next,coalesce(p_comments,''),v_user.id);
 return jsonb_build_object('success',true,'status',v_next);
end$$;

grant execute on function public.hr_benefit_notice_days(integer),public.hr_benefit_severance_days(date,date),public.list_hr_labor_benefits(text,integer),public.save_hr_labor_benefit(text,uuid,jsonb),public.advance_hr_labor_benefit(text,uuid,text,text) to anon,authenticated;

update public.app_users set permissions=permissions||jsonb_build_object('ver_prestaciones_laborales',true,'calcular_prestaciones_laborales',true,'revisar_prestaciones_laborales',true,'aprobar_prestaciones_laborales',true,'pagar_prestaciones_laborales',true),permissions_version=permissions_version+1 where role='Administrador';
