-- Control institucional de permisos y licencias, límites, soportes y descuentos de nómina.
create table if not exists public.hr_permission_types(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,category text not null check(category in('PERMISO','LICENCIA')),
 paid boolean not null default true,requires_medical_document boolean not null default false,max_days_per_request numeric(8,2),max_days_per_year numeric(8,2),max_requests_per_year integer,
 consecutive_window_days integer not null default 7,active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
insert into public.hr_permission_types(code,name,category,paid,requires_medical_document,max_days_per_request,max_days_per_year,max_requests_per_year) values
('PER_PERSONAL','Diligencia personal','PERMISO',true,false,1,6,6),('PER_ESTUDIOS','Permiso por estudios','PERMISO',true,false,2,10,6),
('LIC_MEDICA','Licencia médica','LICENCIA',true,true,30,null,null),('LIC_MATERNIDAD','Licencia por maternidad','LICENCIA',true,true,null,null,null),
('LIC_PATERNIDAD','Licencia por paternidad','LICENCIA',true,true,2,2,1),('LIC_MATRIMONIO','Licencia por matrimonio','LICENCIA',true,true,5,5,1),
('LIC_DUELO','Licencia por fallecimiento familiar','LICENCIA',true,true,3,9,3),('PER_SIN_SUELDO','Permiso sin disfrute de salario','PERMISO',false,false,30,60,4)
on conflict(code) do update set name=excluded.name,category=excluded.category,paid=excluded.paid,requires_medical_document=excluded.requires_medical_document,max_days_per_request=excluded.max_days_per_request,max_days_per_year=excluded.max_days_per_year,max_requests_per_year=excluded.max_requests_per_year;

alter table public.hr_employee_cases add column if not exists permission_type_id uuid references public.hr_permission_types(id);
alter table public.hr_employee_cases add column if not exists requested_hours numeric(8,2) not null default 0;
alter table public.hr_employee_cases add column if not exists medical_document_url text not null default '';
alter table public.hr_employee_cases add column if not exists medical_document_status text not null default 'NO_APLICA' check(medical_document_status in('NO_APLICA','PENDIENTE','VALIDADO','RECHAZADO'));
alter table public.hr_employee_cases add column if not exists medical_validated_by uuid references public.app_users(id);
alter table public.hr_employee_cases add column if not exists medical_validated_at timestamptz;
alter table public.hr_employee_cases add column if not exists payroll_discount_amount numeric(18,2) not null default 0;

create table if not exists public.hr_payroll_adjustments(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),source_case_id uuid not null unique references public.hr_employee_cases(id),
 payroll_year integer not null,payroll_month integer not null check(payroll_month between 1 and 12),adjustment_type text not null default 'PERMISO_SIN_SUELDO',amount numeric(18,2) not null check(amount>=0),
 status text not null default 'PENDIENTE' check(status in('PENDIENTE','APLICADO','ANULADO')),created_at timestamptz not null default now(),applied_at timestamptz
);
alter table public.hr_permission_types enable row level security;alter table public.hr_payroll_adjustments enable row level security;
revoke all on public.hr_permission_types,public.hr_payroll_adjustments from anon,authenticated;

create or replace function public.hr_apply_payroll_adjustments() returns trigger language plpgsql security definer set search_path=public as $$
declare v_amount numeric;begin
 select coalesce(sum(a.amount),0) into v_amount from public.hr_payroll_adjustments a join public.hr_payroll_batches b on b.payroll_year=a.payroll_year and b.payroll_month=a.payroll_month
 where a.employee_id=new.employee_id and b.id=new.batch_id and a.status<>'ANULADO';
 if v_amount>0 then v_amount:=least(v_amount,new.net_amount);update public.hr_payroll_batch_lines set other_deductions=other_deductions+v_amount,total_deductions=total_deductions+v_amount,net_amount=greatest(net_amount-v_amount,0) where id=new.id;
  update public.hr_payroll_adjustments a set status='APLICADO',applied_at=now() from public.hr_payroll_batches b where b.id=new.batch_id and a.employee_id=new.employee_id and a.payroll_year=b.payroll_year and a.payroll_month=b.payroll_month and a.status='PENDIENTE';end if;return new;end $$;
drop trigger if exists trg_hr_apply_payroll_adjustments on public.hr_payroll_batch_lines;
create trigger trg_hr_apply_payroll_adjustments after insert on public.hr_payroll_batch_lines for each row execute function public.hr_apply_payroll_adjustments();

create or replace function public.list_hr_permission_control(p_token text,p_year integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$ declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_permisos_laborales')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar permisos y licencias.');end if;
 return jsonb_build_object('success',true,
 'types',coalesce((select jsonb_agg(to_jsonb(t) order by t.category,t.name) from public.hr_permission_types t where t.active),'[]'::jsonb),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'direction_name',e.direction_name,'department_name',e.department_name) order by e.full_name) from public.hr_employees e where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.request_date desc,x.created_at desc) from(
  select c.*,e.employee_code,e.full_name,e.position_name,e.direction_name,e.department_name,t.code type_code,t.name type_name,t.category type_category,t.paid type_paid,t.requires_medical_document,
   count(*) over(partition by c.employee_id,c.permission_type_id,extract(year from c.request_date)) annual_frequency,
   coalesce(sum(c.day_count+c.requested_hours/8.0) over(partition by c.employee_id,c.permission_type_id,extract(year from c.request_date)),0) annual_days,
   case when lag(c.end_date) over(partition by c.employee_id,c.permission_type_id order by c.start_date) is not null and c.start_date<=lag(c.end_date) over(partition by c.employee_id,c.permission_type_id order by c.start_date)+t.consecutive_window_days then true else false end consecutive_request
  from public.hr_employee_cases c join public.hr_employees e on e.id=c.employee_id left join public.hr_permission_types t on t.id=c.permission_type_id
  where c.case_type='PERMISO' and extract(year from c.request_date)=p_year and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))
 )x),'[]'::jsonb));end $$;

create or replace function public.save_hr_permission_request(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_type public.hr_permission_types;v_start date;v_end date;v_hours numeric;v_days integer;v_id uuid;v_novelty uuid;v_used numeric;v_count integer;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'registrar_permisos_laborales')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar solicitudes.');end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;select * into v_type from public.hr_permission_types where id=(p_data->>'permission_type_id')::uuid and active;
 if v_employee.id is null or v_type.id is null then return jsonb_build_object('success',false,'error','Empleado o tipo de permiso inválido.');end if;if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Empleado fuera de su unidad autorizada.');end if;
 v_start:=(p_data->>'start_date')::date;v_end:=coalesce(nullif(p_data->>'end_date','')::date,v_start);v_hours:=greatest(0,coalesce(nullif(p_data->>'requested_hours','')::numeric,0));v_days:=case when v_hours>0 then 0 else public.hr_business_days(v_start,v_end) end;
 if v_hours>8 then return jsonb_build_object('success',false,'error','Las horas solicitadas no pueden superar ocho por día.');end if;if v_days=0 and v_hours=0 then return jsonb_build_object('success',false,'error','Indique días laborables u horas de permiso.');end if;
 if v_type.requires_medical_document and coalesce(p_data->>'medical_document_url','')!~*'^https?://' then return jsonb_build_object('success',false,'error','Este tipo de licencia requiere un documento médico válido.');end if;
 select coalesce(sum(day_count+requested_hours/8.0),0),count(*) into v_used,v_count from public.hr_employee_cases where employee_id=v_employee.id and permission_type_id=v_type.id and status not in('RECHAZADO','ANULADA') and extract(year from request_date)=extract(year from (p_data->>'request_date')::date);
 if v_type.max_days_per_request is not null and v_days+v_hours/8.0>v_type.max_days_per_request then return jsonb_build_object('success',false,'error','La solicitud supera el límite permitido por evento.');end if;
 if v_type.max_days_per_year is not null and v_used+v_days+v_hours/8.0>v_type.max_days_per_year then return jsonb_build_object('success',false,'error','El empleado supera el límite anual de este tipo.');end if;
 if v_type.max_requests_per_year is not null and v_count>=v_type.max_requests_per_year then return jsonb_build_object('success',false,'error','El empleado alcanzó el máximo anual de solicitudes de este tipo.');end if;
 insert into public.hr_employee_cases(employee_id,case_type,request_date,category,start_date,end_date,day_count,paid,reason,observations,status,created_by,permission_type_id,requested_hours,medical_document_url,medical_document_status)
 values(v_employee.id,'PERMISO',(p_data->>'request_date')::date,v_type.name,v_start,v_end,v_days,v_type.paid,trim(p_data->>'reason'),coalesce(p_data->>'observations',''),'SOLICITADO',v_user.id,v_type.id,v_hours,coalesce(p_data->>'medical_document_url',''),case when v_type.requires_medical_document then 'PENDIENTE' else 'NO_APLICA' end) returning id into v_id;
 insert into public.hr_novelties(employee_id,novelty_type,request_date,start_date,end_date,work_days,description,document_url,source_table,source_id,created_by) values(v_employee.id,'PERMISO',(p_data->>'request_date')::date,v_start,v_end,v_days,trim(p_data->>'reason'),coalesce(p_data->>'medical_document_url',''),'hr_employee_cases',v_id,v_user.id) returning id into v_novelty;
 insert into public.hr_novelty_history(novelty_id,to_status,observation,document_url,responsible_user_id) values(v_novelty,'REGISTRADA','Solicitud registrada',coalesce(p_data->>'medical_document_url',''),v_user.id);
 return jsonb_build_object('success',true,'id',v_id,'novelty_id',v_novelty);end $$;

create or replace function public.validate_hr_medical_document(p_token text,p_case_id uuid,p_valid boolean,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$ declare v_user public.app_users;v_case public.hr_employee_cases;begin v_user:=public.hr_authenticated_user(p_token);select * into v_case from public.hr_employee_cases where id=p_case_id for update;
 if v_user.id is null or v_case.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'aprobar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para validar documentos médicos.');end if;
 update public.hr_employee_cases set medical_document_status=case when p_valid then 'VALIDADO' else 'RECHAZADO' end,medical_validated_by=v_user.id,medical_validated_at=now(),decision_notes=coalesce(p_notes,''),updated_at=now() where id=p_case_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'VALIDAR_DOCUMENTO_MEDICO','Recursos Humanos',jsonb_build_object('employee_id',v_case.employee_id,'case_id',p_case_id,'valid',p_valid,'notes',p_notes));return jsonb_build_object('success',true);end $$;

create or replace function public.create_hr_permission_payroll_adjustment(p_case_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_case public.hr_employee_cases;v_employee public.hr_employees;v_amount numeric;begin select * into v_case from public.hr_employee_cases where id=p_case_id;if v_case.id is null or v_case.paid then return;end if;select * into v_employee from public.hr_employees where id=v_case.employee_id;
 v_amount:=round((v_employee.monthly_salary/23.83)*(v_case.day_count+v_case.requested_hours/8.0),2);update public.hr_employee_cases set payroll_discount_amount=v_amount where id=v_case.id;
 insert into public.hr_payroll_adjustments(employee_id,source_case_id,payroll_year,payroll_month,amount) values(v_case.employee_id,v_case.id,extract(year from v_case.start_date)::integer,extract(month from v_case.start_date)::integer,v_amount) on conflict(source_case_id) do update set amount=excluded.amount,status='PENDIENTE';end $$;

create or replace function public.hr_medical_document_is_valid(p_case_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select not coalesce(t.requires_medical_document,false) or c.medical_document_status='VALIDADO' from public.hr_employee_cases c left join public.hr_permission_types t on t.id=c.permission_type_id where c.id=p_case_id
$$;

grant execute on function public.list_hr_permission_control(text,integer),public.save_hr_permission_request(text,jsonb),public.validate_hr_medical_document(text,uuid,boolean,text) to anon,authenticated;
