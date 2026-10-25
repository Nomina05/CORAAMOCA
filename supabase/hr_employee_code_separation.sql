-- Separa de forma definitiva el código institucional de la cédula del empleado.
create sequence if not exists public.hr_employee_code_seq start 1000;

select setval(
 'public.hr_employee_code_seq',
 greatest(
  (select last_value from public.hr_employee_code_seq),
  coalesce((select max(substring(employee_code from '[0-9]+$')::bigint) from public.hr_employees where employee_code ~ '^EMP-[0-9]+$'),999)
 ),true
);

alter table public.hr_employees
 alter column employee_code set default ('EMP-'||lpad(nextval('public.hr_employee_code_seq')::text,6,'0'));

-- Corrige empleados importados cuyo código fue cargado con el número de cédula.
alter table public.hr_employees disable trigger trg_hr_sync_employee_catalog_relations;
update public.hr_employees
set employee_code='EMP-'||lpad(nextval('public.hr_employee_code_seq')::text,6,'0'),updated_at=now()
where nullif(trim(employee_code),'') is null
   or regexp_replace(employee_code,'\D','','g')=regexp_replace(coalesce(document_number,''),'\D','','g')
   or employee_code ~ '^[0-9]{11}$';
alter table public.hr_employees enable trigger trg_hr_sync_employee_catalog_relations;

create or replace function public.hr_sync_employee_catalog_relations()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if nullif(trim(coalesce(new.employee_code,'')),'') is null
    or regexp_replace(new.employee_code,'\D','','g')=regexp_replace(coalesce(new.document_number,''),'\D','','g')
    or new.employee_code ~ '^[0-9]{11}$'
 then new.employee_code:='EMP-'||lpad(nextval('public.hr_employee_code_seq')::text,6,'0');end if;
 select id into new.position_id from public.hr_position_catalog where active and lower(trim(position_name))=lower(trim(new.position_name)) order by updated_at desc limit 1;
 select id into new.employment_status_id from public.hr_employment_status_catalog where active and lower(trim(name))=lower(trim(new.employment_status)) limit 1;
 select id into new.occupational_group_id from public.hr_occupational_group_catalog where active and code=coalesce(nullif(new.occupational_group,''),nullif(new.employee_group,'')) limit 1;
 if nullif(trim(coalesce(new.termination_type,'')),'') is not null then select id into new.exit_cause_id from public.hr_exit_cause_catalog where active and lower(trim(name))=lower(trim(new.termination_type)) limit 1;else new.exit_cause_id:=null;end if;
 if new.position_id is null then raise exception 'El cargo no pertenece al catálogo institucional activo.';end if;
 if new.employment_status_id is null then raise exception 'El estatus laboral no pertenece al catálogo institucional activo.';end if;
 return new;
end $$;

drop trigger if exists trg_hr_sync_employee_catalog_relations on public.hr_employees;
create trigger trg_hr_sync_employee_catalog_relations
before insert or update of employee_code,document_number,position_name,employment_status,occupational_group,employee_group,termination_type
on public.hr_employees for each row execute function public.hr_sync_employee_catalog_relations();

do $$begin
 if not exists(select 1 from pg_constraint where conname='hr_employees_code_document_distinct') then
  alter table public.hr_employees add constraint hr_employees_code_document_distinct
  check(regexp_replace(employee_code,'\D','','g')<>regexp_replace(coalesce(document_number,''),'\D','','g'));
 end if;
end$$;
