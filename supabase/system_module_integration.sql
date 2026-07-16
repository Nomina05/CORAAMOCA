-- Integración transversal entre proyectos, catálogos, presupuesto y módulos operativos.
-- Ejecutar después de integrated_module_persistence.sql.

alter table public.technical_projects
  add column if not exists supplier_id uuid references public.administrative_catalogs(id),
  add column if not exists budget_account_id uuid references public.administrative_catalogs(id),
  add column if not exists procurement_process_id uuid references public.administrative_catalogs(id),
  add column if not exists municipality_id uuid references public.administrative_catalogs(id),
  add column if not exists district_id uuid references public.administrative_catalogs(id),
  add column if not exists sector_id uuid references public.administrative_catalogs(id),
  add column if not exists funding_source_id uuid references public.administrative_catalogs(id),
  add column if not exists work_type_id uuid references public.administrative_catalogs(id),
  add column if not exists work_status_id uuid references public.administrative_catalogs(id);

create or replace function public.sync_project_catalog_relations(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
begin
  update public.technical_projects p set
    supplier_id=(select c.id from public.administrative_catalogs c where c.catalog_type='supplier' and c.active=true
      and lower(c.name)=lower(p.supplier_contractor) order by c.updated_at desc limit 1),
    budget_account_id=(select c.id from public.administrative_catalogs c where c.catalog_type='account' and c.active=true
      and (lower(c.code)=lower(p.budget_account) or lower(c.name)=lower(p.budget_account)) order by c.updated_at desc limit 1),
    procurement_process_id=(select c.id from public.administrative_catalogs c where c.catalog_type='process' and c.active=true
      and (lower(c.code)=lower(p.procurement_process) or lower(c.name)=lower(p.procurement_process)) order by c.updated_at desc limit 1),
    municipality_id=(select c.id from public.administrative_catalogs c where c.catalog_type='municipality' and c.active=true
      and lower(c.name)=lower(p.municipality) order by c.updated_at desc limit 1),
    district_id=(select c.id from public.administrative_catalogs c where c.catalog_type='district' and c.active=true
      and lower(c.name)=lower(p.district) order by c.updated_at desc limit 1),
    sector_id=(select c.id from public.administrative_catalogs c where c.catalog_type='sector' and c.active=true
      and lower(c.name)=lower(p.sector) order by c.updated_at desc limit 1),
    funding_source_id=(select c.id from public.administrative_catalogs c where c.catalog_type='funding_source' and c.active=true
      and lower(c.name)=lower(p.funding_source) order by c.updated_at desc limit 1),
    work_type_id=(select c.id from public.administrative_catalogs c where c.catalog_type='work_type' and c.active=true
      and lower(c.name)=lower(p.work_type) order by c.updated_at desc limit 1),
    work_status_id=(select c.id from public.administrative_catalogs c where c.catalog_type='work_status' and c.active=true
      and lower(c.name)=lower(p.work_status) order by c.updated_at desc limit 1)
  where p.id=p_project_id;
end $$;

create or replace function public.trigger_sync_project_catalog_relations()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  perform public.sync_project_catalog_relations(new.id);
  return new;
end $$;

drop trigger if exists trg_sync_project_catalog_relations on public.technical_projects;
create trigger trg_sync_project_catalog_relations
after insert or update of supplier_contractor,budget_account,procurement_process,municipality,district,sector,funding_source,work_type,work_status
on public.technical_projects for each row execute function public.trigger_sync_project_catalog_relations();

create or replace function public.trigger_recalculate_budget_modification()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  perform public.recalculate_project_financials(coalesce(new.project_id,old.project_id));
  return coalesce(new,old);
end $$;

drop trigger if exists trg_recalculate_budget_modification on public.project_budget_modifications;
create trigger trg_recalculate_budget_modification
after insert or update or delete on public.project_budget_modifications
for each row execute function public.trigger_recalculate_budget_modification();

create or replace function public.refresh_all_module_relations()
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r record; v_projects integer:=0;
begin
  for r in select id from public.technical_projects loop
    perform public.sync_project_catalog_relations(r.id);
    perform public.recalculate_project_financials(r.id);
    v_projects:=v_projects+1;
  end loop;
  return jsonb_build_object('success',true,'projects_synchronized',v_projects,'updated_at',now());
end $$;

select public.refresh_all_module_relations();
