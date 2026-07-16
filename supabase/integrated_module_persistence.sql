-- Persistencia relacional para todos los módulos institucionales.
-- Ejecutar después de technical_operations.sql.

create table if not exists public.organization_units (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.organization_units(id) on delete restrict,
  unit_code text unique,
  unit_name text not null unique,
  unit_type text not null default 'Unidad',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.institutional_projects (
  id uuid primary key default gen_random_uuid(),
  project_code text not null unique,
  project_name text not null,
  area text not null,
  responsible_name text not null,
  responsible_unit_id uuid references public.organization_units(id),
  responsible_user_id uuid references public.app_users(id),
  progress numeric(5,2) not null default 0 check(progress between 0 and 100),
  budget numeric(18,2) not null default 0 check(budget>=0),
  spent numeric(18,2) not null default 0 check(spent>=0),
  project_status text not null default 'En curso' check(project_status in ('En curso','En riesgo','Completado','Suspendido','Cancelado')),
  due_date date,
  description text not null default '',
  created_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hr_employees (
  id uuid primary key default gen_random_uuid(),
  employee_code text not null unique,
  document_number text unique,
  full_name text not null,
  organization_unit_id uuid not null references public.organization_units(id),
  app_user_id uuid references public.app_users(id),
  position_name text not null,
  employment_status text not null default 'Activo' check(employment_status in ('Activo','Licencia','Suspendido','Desvinculado')),
  hire_date date,
  created_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hr_employee_files (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  document_type text not null,
  document_name text not null,
  document_url text not null,
  uploaded_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now()
);

alter table public.organization_units enable row level security;
alter table public.institutional_projects enable row level security;
alter table public.hr_employees enable row level security;
alter table public.hr_employee_files enable row level security;
revoke all on public.organization_units,public.institutional_projects,public.hr_employees,public.hr_employee_files from anon,authenticated;

insert into public.organization_units(unit_code,unit_name,unit_type,sort_order)
values
  ('DG','Dirección General','Dirección',1),
  ('DRH','Dirección de Recursos Humanos','Dirección',2),
  ('DT','Dirección Técnica','Dirección',3),
  ('DPD','Dirección de Planificación y Desarrollo','Dirección',4),
  ('DAF','Dirección Administrativa y Financiera','Dirección',5),
  ('DC','Dirección Comercial','Dirección',6),
  ('TIC','Departamento de Tecnología de la Información y Comunicación (TIC)','Departamento',7)
on conflict(unit_name) do update set unit_code=excluded.unit_code,unit_type=excluded.unit_type,sort_order=excluded.sort_order;

update public.organization_units child set parent_id=parent.id
from public.organization_units parent
where parent.unit_name='Dirección General' and child.unit_name<>parent.unit_name and child.parent_id is null;

create or replace function public.list_institutional_projects(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_proyectos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar proyectos institucionales.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]'::jsonb) into v_items from (
    select p.id,p.project_code code,p.project_name name,p.area,p.responsible_name owner,p.progress,p.budget,p.spent,
      p.project_status status,p.due_date due,p.description,p.responsible_unit_id,p.responsible_user_id,p.created_at,p.updated_at
    from public.institutional_projects p
    where v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.area=v_user.area
  )x;
  return jsonb_build_object('success',true,'projects',v_items);
end $$;

create or replace function public.save_institutional_project(p_token text,p_project_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_id uuid; v_code text; v_previous jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and
    coalesce((v_user.permissions->>case when p_project_id is null then 'crear_proyectos' else 'editar_proyectos' end)::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para guardar proyectos institucionales.'); end if;
  if length(trim(coalesce(p_data->>'name','')))<3 then return jsonb_build_object('success',false,'error','El nombre del proyecto es obligatorio.'); end if;
  if p_project_id is null then
    v_code:=coalesce(nullif(trim(p_data->>'code'),''),upper(left(coalesce(p_data->>'area','PI'),2))||'-'||to_char(now(),'YYMMDDHH24MISS'));
    insert into public.institutional_projects(project_code,project_name,area,responsible_name,responsible_unit_id,responsible_user_id,
      progress,budget,spent,project_status,due_date,description,created_by)
    values(v_code,trim(p_data->>'name'),trim(p_data->>'area'),trim(p_data->>'owner'),
      nullif(p_data->>'responsibleUnitId','')::uuid,nullif(p_data->>'responsibleUserId','')::uuid,
      coalesce((p_data->>'progress')::numeric,0),coalesce((p_data->>'budget')::numeric,0),coalesce((p_data->>'spent')::numeric,0),
      coalesce(nullif(p_data->>'status',''),'En curso'),nullif(p_data->>'due','')::date,coalesce(p_data->>'description',''),v_user.id)
    returning id into v_id;
  else
    select to_jsonb(p) into v_previous from public.institutional_projects p where p.id=p_project_id;
    update public.institutional_projects set project_name=trim(p_data->>'name'),area=trim(p_data->>'area'),
      responsible_name=trim(p_data->>'owner'),responsible_unit_id=nullif(p_data->>'responsibleUnitId','')::uuid,
      responsible_user_id=nullif(p_data->>'responsibleUserId','')::uuid,progress=coalesce((p_data->>'progress')::numeric,progress),
      budget=coalesce((p_data->>'budget')::numeric,budget),spent=coalesce((p_data->>'spent')::numeric,spent),
      project_status=coalesce(nullif(p_data->>'status',''),project_status),due_date=nullif(p_data->>'due','')::date,
      description=coalesce(p_data->>'description',description),updated_at=now()
    where id=p_project_id returning id into v_id;
  end if;
  if v_id is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  return jsonb_build_object('success',true,'id',v_id,'previous',v_previous);
end $$;

create or replace function public.list_organization_units(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user_id uuid; v_items jsonb;
begin
  select u.id into v_user_id from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user_id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select coalesce(jsonb_agg(to_jsonb(o) order by o.sort_order,o.unit_name),'[]'::jsonb) into v_items
  from (select id,parent_id,unit_code,unit_name,unit_type,active,sort_order from public.organization_units where active=true)o;
  return jsonb_build_object('success',true,'units',v_items);
end $$;

create or replace function public.list_hr_employees(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar Recursos Humanos.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_items from (
    select e.id,e.employee_code,e.document_number,e.full_name,e.position_name,e.employment_status,e.hire_date,
      e.organization_unit_id,o.unit_name,e.app_user_id,e.created_at
    from public.hr_employees e join public.organization_units o on o.id=e.organization_unit_id
  )x;
  return jsonb_build_object('success',true,'employees',v_items);
end $$;

grant execute on function public.list_institutional_projects(text),public.save_institutional_project(text,uuid,jsonb),
  public.list_organization_units(text),public.list_hr_employees(text) to anon,authenticated;
