-- Fase 1: fuente maestra, catálogos normalizados y relaciones de Recursos Humanos.

create table if not exists public.hr_employment_status_catalog(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null unique,active boolean not null default true,sort_order integer not null default 0
);
create table if not exists public.hr_occupational_group_catalog(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null,active boolean not null default true,sort_order integer not null default 0
);
create table if not exists public.hr_exit_cause_catalog(
 id uuid primary key default gen_random_uuid(),code text not null unique,name text not null unique,action_type text not null,active boolean not null default true
);
insert into public.hr_employment_status_catalog(code,name,sort_order) values
 ('ACTIVO','Activo',1),('FIJO','Fijo',2),('CARRERA_ADMINISTRATIVA','Carrera Administrativa',3),('TEMPORAL','Temporal',4),('INTERINO','Interino',5),('ESTATUTO_SIMPLIFICADO','Estatuto Simplificado',6),('LICENCIA','Licencia',7),('SUSPENDIDO','Suspendido',8),('DESVINCULADO','Desvinculado',9)
on conflict(code) do update set name=excluded.name,sort_order=excluded.sort_order,active=true;
insert into public.hr_occupational_group_catalog(code,name,sort_order) values('I','Grupo Ocupacional I',1),('II','Grupo Ocupacional II',2),('III','Grupo Ocupacional III',3),('IV','Grupo Ocupacional IV',4),('V','Grupo Ocupacional V',5)
on conflict(code) do update set name=excluded.name,sort_order=excluded.sort_order,active=true;
insert into public.hr_exit_cause_catalog(code,name,action_type) values
 ('DESPIDO','Despido','DESPIDO'),('ABANDONO_TRABAJO','Abandono del trabajo','ABANDONO_TRABAJO'),('RENUNCIA','Renuncia','RENUNCIA'),('RESCISION_CONTRATO','Rescisión de contrato','RESCISION_CONTRATO'),('JUBILACION','Jubilación','OTROS'),('FALLECIMIENTO','Fallecimiento','OTROS'),('FIN_CONTRATO','Finalización de contrato','OTROS')
on conflict(code) do update set name=excluded.name,action_type=excluded.action_type,active=true;

alter table public.hr_employees add column if not exists position_id uuid references public.hr_position_catalog(id);
alter table public.hr_employees add column if not exists employment_status_id uuid references public.hr_employment_status_catalog(id);
alter table public.hr_employees add column if not exists occupational_group_id uuid references public.hr_occupational_group_catalog(id);
alter table public.hr_employees add column if not exists exit_cause_id uuid references public.hr_exit_cause_catalog(id);
alter table public.hr_employees disable trigger trg_hr_validate_employee_master;
alter table public.hr_employees disable trigger trg_hr_audit_employee_master;
update public.hr_employees e set position_id=p.id from public.hr_position_catalog p where e.position_id is null and p.active and lower(trim(p.position_name))=lower(trim(e.position_name));
update public.hr_employees e set employment_status_id=s.id from public.hr_employment_status_catalog s where e.employment_status_id is null and lower(trim(s.name))=lower(trim(e.employment_status));
update public.hr_employees e set occupational_group_id=g.id from public.hr_occupational_group_catalog g where e.occupational_group_id is null and g.code=coalesce(nullif(e.occupational_group,''),nullif(e.employee_group,''));
update public.hr_employees e set exit_cause_id=c.id from public.hr_exit_cause_catalog c where e.exit_cause_id is null and lower(trim(c.name))=lower(trim(coalesce(e.termination_type,'')));
alter table public.hr_employees enable trigger trg_hr_validate_employee_master;
alter table public.hr_employees enable trigger trg_hr_audit_employee_master;

do $$begin if not exists(select 1 from public.hr_employees where app_user_id is not null group by app_user_id having count(*)>1) then execute 'create unique index if not exists hr_employees_app_user_unique on public.hr_employees(app_user_id) where app_user_id is not null';end if;end$$;
create index if not exists hr_employees_unit_idx on public.hr_employees(organization_unit_id,employment_status);
create index if not exists hr_employees_position_idx on public.hr_employees(position_id);

create or replace function public.hr_sync_employee_catalog_relations()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if nullif(trim(coalesce(new.employee_code,'')),'') is null then new.employee_code:='EMP-'||lpad(nextval('public.hr_employee_code_seq')::text,6,'0');end if;
 select id into new.position_id from public.hr_position_catalog where active and lower(trim(position_name))=lower(trim(new.position_name)) order by updated_at desc limit 1;
 select id into new.employment_status_id from public.hr_employment_status_catalog where active and lower(trim(name))=lower(trim(new.employment_status)) limit 1;
 select id into new.occupational_group_id from public.hr_occupational_group_catalog where active and code=coalesce(nullif(new.occupational_group,''),nullif(new.employee_group,'')) limit 1;
 if nullif(trim(coalesce(new.termination_type,'')),'') is not null then select id into new.exit_cause_id from public.hr_exit_cause_catalog where active and lower(trim(name))=lower(trim(new.termination_type)) limit 1;else new.exit_cause_id:=null;end if;
 if new.position_id is null then raise exception 'El cargo no pertenece al catálogo institucional activo.';end if;
 if new.employment_status_id is null then raise exception 'El estatus laboral no pertenece al catálogo institucional activo.';end if;
 return new;
end $$;
drop trigger if exists trg_hr_sync_employee_catalog_relations on public.hr_employees;
create trigger trg_hr_sync_employee_catalog_relations before insert or update of employee_code,position_name,employment_status,occupational_group,employee_group,termination_type on public.hr_employees for each row execute function public.hr_sync_employee_catalog_relations();

create or replace view public.hr_employee_current as select * from public.hr_employees;
create or replace view public.hr_employee_timeline as
select h.id,h.employee_id,e.employee_code,e.full_name,h.effective_year,h.effective_month,h.position_name,h.employment_status,h.payroll_status,h.direction_name,h.department_name,h.division_name,h.section_name,h.center_name,h.execution_fund,h.program,h.subproduct,h.activity,h.monthly_salary,h.change_type,h.created_at
from public.hr_employee_history h join public.hr_employees e on e.id=h.employee_id;
revoke all on public.hr_employee_current,public.hr_employee_timeline from anon,authenticated;

create or replace function public.audit_hr_module_base(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para auditar Recursos Humanos.');end if;
 return jsonb_build_object('success',true,'source','hr_employees','employee_count',(select count(*) from public.hr_employees),'history_count',(select count(*) from public.hr_employee_history),
  'linked_users',(select count(*) from public.hr_employees where app_user_id is not null),'linked_units',(select count(*) from public.hr_employees where organization_unit_id is not null),'linked_positions',(select count(*) from public.hr_employees where position_id is not null),
  'duplicate_documents',(select count(*) from(select regexp_replace(document_number,'\D','','g') from public.hr_employees group by 1 having count(*)>1)x),
  'duplicate_codes',(select count(*) from(select employee_code from public.hr_employees group by employee_code having count(*)>1)x),
  'duplicate_user_links',(select count(*) from(select app_user_id from public.hr_employees where app_user_id is not null group by app_user_id having count(*)>1)x),
  'orphan_history',(select count(*) from public.hr_employee_history h left join public.hr_employees e on e.id=h.employee_id where e.id is null),
  'catalogs',jsonb_build_object('positions',(select count(*) from public.hr_position_catalog where active),'statuses',(select count(*) from public.hr_employment_status_catalog where active),'occupational_groups',(select count(*) from public.hr_occupational_group_catalog where active),'exit_causes',(select count(*) from public.hr_exit_cause_catalog where active),'organization_units',(select count(*) from public.organization_units where active)));
end $$;
revoke all on function public.audit_hr_module_base(text) from public;
grant execute on function public.audit_hr_module_base(text) to anon,authenticated;

alter table public.hr_employment_status_catalog enable row level security;
alter table public.hr_occupational_group_catalog enable row level security;
alter table public.hr_exit_cause_catalog enable row level security;
revoke all on public.hr_employment_status_catalog,public.hr_occupational_group_catalog,public.hr_exit_cause_catalog from anon,authenticated;
