-- Relaciones reales entre proyectos y los catalogos administrativos iniciales.
-- Ejecutar despues de technical_projects.sql y administrative_catalogs.sql.

create table if not exists public.budget_account_catalog (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.procurement_process_catalog (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.supplier_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.budget_account_catalog enable row level security;
alter table public.procurement_process_catalog enable row level security;
alter table public.supplier_catalog enable row level security;
revoke all on public.budget_account_catalog, public.procurement_process_catalog, public.supplier_catalog from anon, authenticated;

alter table public.technical_projects
  add column if not exists budget_account_catalog_id uuid,
  add column if not exists procurement_process_catalog_id uuid,
  add column if not exists supplier_catalog_id uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='technical_projects_budget_account_catalog_fk') then
    alter table public.technical_projects
      add constraint technical_projects_budget_account_catalog_fk
      foreign key (budget_account_catalog_id) references public.budget_account_catalog(id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='technical_projects_procurement_process_catalog_fk') then
    alter table public.technical_projects
      add constraint technical_projects_procurement_process_catalog_fk
      foreign key (procurement_process_catalog_id) references public.procurement_process_catalog(id)
      on update cascade on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='technical_projects_supplier_catalog_fk') then
    alter table public.technical_projects
      add constraint technical_projects_supplier_catalog_fk
      foreign key (supplier_catalog_id) references public.supplier_catalog(id)
      on update cascade on delete restrict;
  end if;
end $$;

create index if not exists technical_projects_budget_account_catalog_idx
  on public.technical_projects(budget_account_catalog_id);
create index if not exists technical_projects_procurement_process_catalog_idx
  on public.technical_projects(procurement_process_catalog_id);
create index if not exists technical_projects_supplier_catalog_idx
  on public.technical_projects(supplier_catalog_id);

-- Copia el catalogo unificado hacia las tablas especificas sin eliminar datos existentes.
insert into public.budget_account_catalog(code,description,active,created_at,updated_at)
select trim(coalesce(nullif(c.code,''),c.name)),c.description,c.active,c.created_at,c.updated_at
from public.administrative_catalogs c
where c.catalog_type='account' and trim(coalesce(nullif(c.code,''),c.name))<>''
on conflict(code) do update set
  description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;

insert into public.procurement_process_catalog(code,description,active,created_at,updated_at)
select trim(coalesce(nullif(c.code,''),c.name)),c.description,c.active,c.created_at,c.updated_at
from public.administrative_catalogs c
where c.catalog_type='process' and trim(coalesce(nullif(c.code,''),c.name))<>''
on conflict(code) do update set
  description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;

insert into public.supplier_catalog(name,description,active,created_at,updated_at)
select trim(c.name),c.description,c.active,c.created_at,c.updated_at
from public.administrative_catalogs c
where c.catalog_type='supplier' and trim(c.name)<>''
on conflict(name) do update set
  description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;

-- Incorpora valores historicos de proyectos que todavia no estaban catalogados.
insert into public.budget_account_catalog(code)
select distinct trim(p.budget_account) from public.technical_projects p
where trim(coalesce(p.budget_account,''))<>''
on conflict(code) do nothing;

insert into public.procurement_process_catalog(code)
select distinct trim(p.procurement_process) from public.technical_projects p
where trim(coalesce(p.procurement_process,''))<>''
on conflict(code) do nothing;

insert into public.supplier_catalog(name)
select distinct trim(p.supplier_contractor) from public.technical_projects p
where trim(coalesce(p.supplier_contractor,''))<>''
on conflict(name) do nothing;

create or replace function public.sync_project_legacy_catalog_relations(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  update public.technical_projects p set
    budget_account_catalog_id=(
      select c.id from public.budget_account_catalog c
      where lower(trim(c.code))=lower(trim(p.budget_account))
      order by c.active desc,c.updated_at desc limit 1
    ),
    procurement_process_catalog_id=(
      select c.id from public.procurement_process_catalog c
      where lower(trim(c.code))=lower(trim(p.procurement_process))
      order by c.active desc,c.updated_at desc limit 1
    ),
    supplier_catalog_id=(
      select c.id from public.supplier_catalog c
      where lower(trim(c.name))=lower(trim(p.supplier_contractor))
      order by c.active desc,c.updated_at desc limit 1
    )
  where p.id=p_project_id;
end $$;

create or replace function public.trigger_sync_project_legacy_catalog_relations()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  perform public.sync_project_legacy_catalog_relations(new.id);
  return new;
end $$;

drop trigger if exists trg_sync_project_legacy_catalog_relations on public.technical_projects;
create trigger trg_sync_project_legacy_catalog_relations
after insert or update of budget_account,procurement_process,supplier_contractor
on public.technical_projects for each row
execute function public.trigger_sync_project_legacy_catalog_relations();

create or replace function public.sync_specific_project_catalogs_from_unified()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  if new.catalog_type='account' then
    insert into public.budget_account_catalog(code,description,active,created_at,updated_at)
    values(trim(coalesce(nullif(new.code,''),new.name)),new.description,new.active,new.created_at,new.updated_at)
    on conflict(code) do update set description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;
  elsif new.catalog_type='process' then
    insert into public.procurement_process_catalog(code,description,active,created_at,updated_at)
    values(trim(coalesce(nullif(new.code,''),new.name)),new.description,new.active,new.created_at,new.updated_at)
    on conflict(code) do update set description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;
  elsif new.catalog_type='supplier' then
    insert into public.supplier_catalog(name,description,active,created_at,updated_at)
    values(trim(new.name),new.description,new.active,new.created_at,new.updated_at)
    on conflict(name) do update set description=excluded.description,active=excluded.active,updated_at=excluded.updated_at;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_specific_project_catalogs_from_unified on public.administrative_catalogs;
create trigger trg_sync_specific_project_catalogs_from_unified
after insert or update of code,name,description,active
on public.administrative_catalogs for each row
when (new.catalog_type in ('account','process','supplier'))
execute function public.sync_specific_project_catalogs_from_unified();

do $$
declare r record;
begin
  for r in select id from public.technical_projects loop
    perform public.sync_project_legacy_catalog_relations(r.id);
  end loop;
end $$;

grant execute on function public.sync_project_legacy_catalog_relations(uuid) to service_role;

