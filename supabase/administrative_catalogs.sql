-- Catálogos administrativos unificados.
-- Ejecutar después de project_digital_file.sql.

create table if not exists public.administrative_catalogs (
  id uuid primary key default gen_random_uuid(),
  catalog_type text not null check(catalog_type in ('supplier','account','process','municipality','district','sector','funding_source','work_type','work_status')),
  code text not null default '',
  name text not null,
  description text not null default '',
  parent_id uuid references public.administrative_catalogs(id),
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists administrative_catalogs_unique_active
  on public.administrative_catalogs(catalog_type,lower(code),lower(name));
alter table public.administrative_catalogs enable row level security;
revoke all on public.administrative_catalogs from anon,authenticated;

alter table public.technical_projects
  add column if not exists funding_source text not null default '',
  add column if not exists work_type text not null default '';

create or replace function public.list_project_catalogs(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_result jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_catalogos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar catálogos.'); end if;
  select jsonb_build_object(
    'suppliers',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='supplier'),'[]'::jsonb),
    'accounts',coalesce(jsonb_agg(to_jsonb(c) order by c.code) filter(where catalog_type='account'),'[]'::jsonb),
    'processes',coalesce(jsonb_agg(to_jsonb(c) order by c.code) filter(where catalog_type='process'),'[]'::jsonb),
    'municipalities',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='municipality'),'[]'::jsonb),
    'districts',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='district'),'[]'::jsonb),
    'sectors',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='sector'),'[]'::jsonb),
    'fundingSources',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='funding_source'),'[]'::jsonb),
    'workTypes',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='work_type'),'[]'::jsonb),
    'workStatuses',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='work_status'),'[]'::jsonb)
  ) into v_result from public.administrative_catalogs c;
  return jsonb_build_object('success',true,'catalogs',v_result);
end $$;

create or replace function public.manage_project_catalog(p_token text,p_type text,p_id uuid,p_code text,p_name text,p_description text,p_active boolean,p_parent_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_name text; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'gestionar_catalogos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para gestionar catálogos.'); end if;
  if p_type not in ('supplier','account','process','municipality','district','sector','funding_source','work_type','work_status')
    then return jsonb_build_object('success',false,'error','Tipo de catálogo no válido.'); end if;
  v_name:=trim(coalesce(nullif(p_name,''),p_code));
  if length(v_name)<2 then return jsonb_build_object('success',false,'error','Indique un código o nombre válido.'); end if;
  if p_id is null then
    insert into public.administrative_catalogs(catalog_type,code,name,description,parent_id,active,created_by)
    values(p_type,trim(coalesce(p_code,'')),v_name,trim(coalesce(p_description,'')),p_parent_id,true,v_user.id)
    returning id into v_id;
  else
    update public.administrative_catalogs set code=trim(coalesce(p_code,'')),name=v_name,description=trim(coalesce(p_description,'')),
      parent_id=p_parent_id,active=p_active,updated_at=now() where id=p_id and catalog_type=p_type returning id into v_id;
  end if;
  if v_id is null then return jsonb_build_object('success',false,'error','Registro no encontrado.'); end if;
  return jsonb_build_object('success',true,'id',v_id);
exception when unique_violation then
  return jsonb_build_object('success',false,'error','Ya existe un registro con ese código o nombre.');
end $$;

insert into public.administrative_catalogs(catalog_type,name,description)
values ('work_status','Planificación','Estado inicial'),('work_status','En contratación','Proceso contractual'),
('work_status','Adjudicada','Contrato adjudicado'),('work_status','En ejecución','Obra activa'),
('work_status','Pausada','Ejecución detenida'),('work_status','Finalizada','Obra concluida'),('work_status','Cancelada','Proyecto cancelado')
on conflict do nothing;

create or replace function public.set_project_administrative_classification(p_token text,p_project_id uuid,p_funding_source text,p_work_type text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_proyectos_tecnicos')::boolean,false)=false
    and coalesce((v_user.permissions->>'crear_proyectos_tecnicos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para clasificar el proyecto.'); end if;
  update public.technical_projects set funding_source=trim(coalesce(p_funding_source,'')),work_type=trim(coalesce(p_work_type,'')),updated_at=now()
  where id=p_project_id;
  return jsonb_build_object('success',found);
end $$;

grant execute on function public.list_project_catalogs(text),
  public.manage_project_catalog(text,text,uuid,text,text,text,boolean,uuid) to anon,authenticated;
grant execute on function public.set_project_administrative_classification(text,uuid,text,text) to anon,authenticated;
