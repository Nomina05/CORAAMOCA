-- Fase 5: catálogo institucional de plazas, ocupación y planificación de vacantes.
create sequence if not exists public.hr_staff_position_code_seq start 1;

create table if not exists public.hr_staff_positions(
 id uuid primary key default gen_random_uuid(),
 position_code text not null unique,
 organization_unit_id uuid not null references public.organization_units(id),
 position_catalog_id uuid not null references public.hr_position_catalog(id),
 status text not null default 'VACANTE' check(status in('OCUPADA','VACANTE','CONGELADA','ELIMINADA')),
 source_employee_id uuid unique references public.hr_employees(id),
 incumbent_employee_id uuid references public.hr_employees(id),
 execution_fund text not null default '',program integer,subproduct integer,activity integer,
 monthly_amount numeric(18,2) not null default 0 check(monthly_amount>=0),
 effective_from date not null default current_date,effective_to date,
 created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from),
 check((status='OCUPADA' and incumbent_employee_id is not null) or status<>'OCUPADA')
);
alter table public.hr_staff_positions add column if not exists source_employee_id uuid references public.hr_employees(id);
create unique index if not exists hr_staff_positions_source_employee_uidx on public.hr_staff_positions(source_employee_id) where source_employee_id is not null;
create unique index if not exists hr_staff_positions_incumbent_uidx on public.hr_staff_positions(incumbent_employee_id) where status='OCUPADA';
create index if not exists hr_staff_positions_unit_idx on public.hr_staff_positions(organization_unit_id,status);
alter table public.hr_staff_positions enable row level security;
revoke all on public.hr_staff_positions from anon,authenticated;

alter table public.hr_employees add column if not exists staff_position_id uuid references public.hr_staff_positions(id);
alter table public.hr_vacancies add column if not exists staff_position_id uuid references public.hr_staff_positions(id);
alter table public.hr_vacancies add column if not exists organization_unit_id uuid references public.organization_units(id);
alter table public.hr_vacancies add column if not exists position_catalog_id uuid references public.hr_position_catalog(id);
create unique index if not exists hr_vacancies_open_position_uidx on public.hr_vacancies(staff_position_id) where status in('VACANTE','CON_RECLUTAMIENTO','CONGELADA');

-- Cada empleado histórico o activo recibe una plaza identificable sin duplicar ejecuciones.
insert into public.hr_staff_positions(position_code,organization_unit_id,position_catalog_id,status,source_employee_id,incumbent_employee_id,execution_fund,program,subproduct,activity,monthly_amount,effective_from)
select 'PLA-'||lpad(nextval('public.hr_staff_position_code_seq')::text,6,'0'),e.organization_unit_id,e.position_id,
 case when e.employment_status='Desvinculado' then 'VACANTE' else 'OCUPADA' end,e.id,
 case when e.employment_status='Desvinculado' then null else e.id end,coalesce(e.execution_fund,''),e.program,e.subproduct,e.activity,e.monthly_salary,coalesce(e.hire_date,current_date)
from public.hr_employees e
where e.organization_unit_id is not null and e.position_id is not null and e.staff_position_id is null
on conflict(source_employee_id) do nothing;

alter table public.hr_employees disable trigger trg_hr_validate_employee_master;
alter table public.hr_employees disable trigger trg_hr_audit_employee_master;
update public.hr_employees e set staff_position_id=p.id
from public.hr_staff_positions p
where e.staff_position_id is null and p.source_employee_id=e.id;
alter table public.hr_employees enable trigger trg_hr_validate_employee_master;
alter table public.hr_employees enable trigger trg_hr_audit_employee_master;

with duplicate_open as (
 select id,row_number() over(partition by source_employee_id order by updated_at desc,created_at desc,id) rn
 from public.hr_vacancies where source_employee_id is not null and status in('VACANTE','CON_RECLUTAMIENTO','CONGELADA')
)
update public.hr_vacancies v set status='CANCELADA',updated_at=now()
from duplicate_open d where d.id=v.id and d.rn>1;

update public.hr_vacancies v set staff_position_id=e.staff_position_id,organization_unit_id=e.organization_unit_id,position_catalog_id=e.position_id
from public.hr_employees e where v.source_employee_id=e.id and (v.staff_position_id is null or v.organization_unit_id is null or v.position_catalog_id is null);

-- Mantiene una única fuente entre plaza, empleado y vacante.
create or replace function public.hr_sync_staff_position_from_vacancy()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_previous uuid;
begin
 if new.staff_position_id is null then return new;end if;
 if new.status='OCUPADA' and new.filled_by_employee_id is not null then
  select staff_position_id into v_previous from public.hr_employees where id=new.filled_by_employee_id for update;
  if v_previous is not null and v_previous<>new.staff_position_id then
   update public.hr_staff_positions set status='VACANTE',incumbent_employee_id=null,updated_at=now() where id=v_previous and incumbent_employee_id=new.filled_by_employee_id;
  end if;
  update public.hr_staff_positions set status='OCUPADA',incumbent_employee_id=new.filled_by_employee_id,monthly_amount=new.monthly_amount,updated_at=now() where id=new.staff_position_id;
  update public.hr_employees set staff_position_id=new.staff_position_id,organization_unit_id=coalesce(new.organization_unit_id,organization_unit_id),position_id=coalesce(new.position_catalog_id,position_id),updated_at=now() where id=new.filled_by_employee_id;
 elsif new.status in('VACANTE','CON_RECLUTAMIENTO') then
  update public.hr_staff_positions set status='VACANTE',incumbent_employee_id=null,updated_at=now() where id=new.staff_position_id;
 elsif new.status='CONGELADA' then update public.hr_staff_positions set status='CONGELADA',incumbent_employee_id=null,updated_at=now() where id=new.staff_position_id;
 elsif new.status in('ELIMINADA','CANCELADA') then update public.hr_staff_positions set status='ELIMINADA',incumbent_employee_id=null,effective_to=current_date,updated_at=now() where id=new.staff_position_id;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_sync_staff_position_from_vacancy on public.hr_vacancies;
drop trigger if exists trg_hr_sync_staff_position_from_vacancy_insert on public.hr_vacancies;
create trigger trg_hr_sync_staff_position_from_vacancy after update of status,filled_by_employee_id on public.hr_vacancies
for each row execute function public.hr_sync_staff_position_from_vacancy();
create trigger trg_hr_sync_staff_position_from_vacancy_insert after insert on public.hr_vacancies
for each row execute function public.hr_sync_staff_position_from_vacancy();

create or replace function public.hr_release_staff_position_on_exit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.employment_status='Desvinculado' and old.employment_status is distinct from 'Desvinculado' and new.staff_position_id is not null then
  update public.hr_staff_positions set status='VACANTE',incumbent_employee_id=null,monthly_amount=new.monthly_salary,updated_at=now() where id=new.staff_position_id;
  update public.hr_vacancies set staff_position_id=new.staff_position_id,organization_unit_id=new.organization_unit_id,position_catalog_id=new.position_id,updated_at=now()
  where source_employee_id=new.id and status in('VACANTE','CON_RECLUTAMIENTO');
 end if;
 return new;
end $$;
drop trigger if exists zz_hr_release_staff_position_on_exit on public.hr_employees;
create trigger zz_hr_release_staff_position_on_exit after update of employment_status on public.hr_employees
for each row execute function public.hr_release_staff_position_on_exit();

create or replace function public.create_hr_staff_position(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_unit public.organization_units;v_catalog public.hr_position_catalog;v_id uuid;v_code text;v_direction text:='';v_department text:='';v_division text:='';v_section text:='';v_center text:='';
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para crear plazas.');end if;
 select * into v_unit from public.organization_units where id=(p_data->>'organization_unit_id')::uuid and active;
 select * into v_catalog from public.hr_position_catalog where id=(p_data->>'position_catalog_id')::uuid and active;
 if v_unit.id is null or v_catalog.id is null then return jsonb_build_object('success',false,'error','Seleccione una unidad y un cargo institucional válidos.');end if;
 if v_user.role<>'Administrador' and v_user.organization_scope_unit_id is not null and not public.hr_unit_contains(v_user.organization_scope_unit_id,v_unit.id) then return jsonb_build_object('success',false,'error','La unidad no pertenece a su alcance autorizado.');end if;
 v_code:='PLA-'||lpad(nextval('public.hr_staff_position_code_seq')::text,6,'0');
 with recursive lineage as (
  select id,parent_id,unit_name,unit_type from public.organization_units where id=v_unit.id
  union all select p.id,p.parent_id,p.unit_name,p.unit_type from public.organization_units p join lineage c on c.parent_id=p.id
 ) select coalesce(max(unit_name) filter(where unit_type='Dirección'),''),coalesce(max(unit_name) filter(where unit_type='Departamento'),''),coalesce(max(unit_name) filter(where unit_type='División'),''),coalesce(max(unit_name) filter(where unit_type='Sección'),''),coalesce(max(unit_name) filter(where unit_type='Centro'),'')
 into v_direction,v_department,v_division,v_section,v_center from lineage;
 insert into public.hr_staff_positions(position_code,organization_unit_id,position_catalog_id,status,execution_fund,program,subproduct,activity,monthly_amount,effective_from,created_by)
 values(v_code,v_unit.id,v_catalog.id,'VACANTE',trim(coalesce(p_data->>'execution_fund','')),nullif(p_data->>'program','')::integer,nullif(p_data->>'subproduct','')::integer,nullif(p_data->>'activity','')::integer,greatest(0,coalesce(nullif(p_data->>'monthly_amount','')::numeric,0)),coalesce(nullif(p_data->>'effective_from','')::date,current_date),v_user.id) returning id into v_id;
 insert into public.hr_vacancies(staff_position_id,organization_unit_id,position_catalog_id,position_name,direction_name,department_name,division_name,section_name,center_name,execution_fund,program,subproduct,activity,monthly_amount,available_from,status)
 select v_id,v_unit.id,v_catalog.id,v_catalog.position_name,v_direction,v_department,v_division,v_section,v_center,
  trim(coalesce(p_data->>'execution_fund','')),nullif(p_data->>'program','')::integer,nullif(p_data->>'subproduct','')::integer,nullif(p_data->>'activity','')::integer,greatest(0,coalesce(nullif(p_data->>'monthly_amount','')::numeric,0)),coalesce(nullif(p_data->>'effective_from','')::date,current_date),'VACANTE';
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'CREAR_PLAZA','Recursos Humanos',jsonb_build_object('staff_position_id',v_id,'position_code',v_code,'unit_id',v_unit.id,'catalog_id',v_catalog.id));
 return jsonb_build_object('success',true,'id',v_id,'position_code',v_code);
exception when invalid_text_representation then return jsonb_build_object('success',false,'error','Revise los valores del formulario de plaza.');end $$;

create or replace function public.list_hr_vacancy_planning(p_token text,p_year integer,p_month integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$declare v_user public.app_users;v_end date:=(make_date(p_year,p_month,1)+interval '1 month - 1 day')::date;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar la planificación de vacantes.');end if;
 return jsonb_build_object('success',true,'period_end',v_end,
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.direction_name,x.department_name,x.position_name) from(select v.*,p.position_code,e.full_name filled_employee_name,r.id recruitment_id,r.process_number,r.status recruitment_status,r.start_date recruitment_start,r.reference recruitment_reference from public.hr_vacancies v left join public.hr_staff_positions p on p.id=v.staff_position_id left join public.hr_employees e on e.id=v.filled_by_employee_id left join lateral(select * from public.hr_recruitment_processes r where r.vacancy_id=v.id order by r.created_at desc limit 1)r on true where v.available_from<=v_end and (v_user.role='Administrador' or v.organization_unit_id is null or v_user.organization_scope_unit_id is null or public.hr_unit_contains(v_user.organization_scope_unit_id,v.organization_unit_id)))x),'[]'::jsonb),
 'areas',coalesce((select jsonb_agg(to_jsonb(a) order by a.monthly_available desc,a.direction_name,a.department_name) from(select direction_name,department_name,count(*) filter(where status in('VACANTE','CON_RECLUTAMIENTO'))::integer vacancy_count,coalesce(sum(monthly_amount) filter(where status in('VACANTE','CON_RECLUTAMIENTO')),0)::numeric(18,2) monthly_available,coalesce(sum(monthly_amount*greatest(0,13-greatest(p_month,extract(month from available_from)::integer))) filter(where status in('VACANTE','CON_RECLUTAMIENTO')),0)::numeric(18,2) annual_available from public.hr_vacancies where available_from<=v_end and (v_user.role='Administrador' or organization_unit_id is null or v_user.organization_scope_unit_id is null or public.hr_unit_contains(v_user.organization_scope_unit_id,organization_unit_id)) group by direction_name,department_name)a),'[]'::jsonb),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'employee_code',e.employee_code,'full_name',e.full_name,'position_name',e.position_name,'unit_name',o.unit_name) order by e.full_name) from public.hr_employees e left join public.organization_units o on o.id=e.organization_unit_id where e.employment_status<>'Desvinculado' and (v_user.role='Administrador' or public.hr_employee_in_user_scope(v_user,e))),'[]'::jsonb),
 'positions',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'position_name',p.position_name,'occupational_group',p.occupational_group) order by p.position_name) from public.hr_position_catalog p where p.active),'[]'::jsonb),
 'units',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'unit_name',o.unit_name,'unit_type',o.unit_type) order by o.unit_name) from public.organization_units o where o.active and (v_user.role='Administrador' or v_user.organization_scope_unit_id is null or public.hr_unit_contains(v_user.organization_scope_unit_id,o.id))),'[]'::jsonb),
 'staff_positions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'position_code',s.position_code,'status',s.status,'unit_name',o.unit_name,'unit_type',o.unit_type,'position_name',p.position_name,'occupational_group',p.occupational_group,'incumbent_name',e.full_name,'execution_fund',s.execution_fund,'program',s.program,'subproduct',s.subproduct,'activity',s.activity,'monthly_amount',s.monthly_amount,'effective_from',s.effective_from) order by s.position_code) from public.hr_staff_positions s join public.organization_units o on o.id=s.organization_unit_id join public.hr_position_catalog p on p.id=s.position_catalog_id left join public.hr_employees e on e.id=s.incumbent_employee_id where v_user.role='Administrador' or v_user.organization_scope_unit_id is null or public.hr_unit_contains(v_user.organization_scope_unit_id,s.organization_unit_id)),'[]'::jsonb));end $$;

grant execute on function public.create_hr_staff_position(text,jsonb),public.list_hr_vacancy_planning(text,integer,integer) to anon,authenticated;
