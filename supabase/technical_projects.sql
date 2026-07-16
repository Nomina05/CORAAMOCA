create table if not exists public.technical_projects (
  id uuid primary key default gen_random_uuid(), budget_account text not null, procurement_process text not null,
  project_year integer not null check (project_year between 2000 and 2100), supplier_contractor text not null,
  snip_code text, has_lot boolean not null default false, lot_number text, work_name text not null, fixed_assets text,
  municipality text not null, district text, sector text, population integer not null default 0 check (population >= 0),
  linear_meters numeric(14,2), budgeted_amount numeric(18,2) not null default 0,
  appropriation_amount numeric(18,2) not null default 0, awarded_amount numeric(18,2) not null default 0,
  advance_20_amount numeric(18,2) not null default 0, measurement_count integer not null default 0,
  measurement_status text not null default 'Pendiente', total_measured numeric(18,2) not null default 0,
  total_paid numeric(18,2) not null default 0, work_status text not null default 'Planificación',
  work_progress numeric(5,2) not null default 0 check (work_progress between 0 and 100),
  lead_direction text not null default 'Dirección Técnica',
  participating_directions text[] not null default array['Dirección Administrativa y Financiera','Dirección de Planificación y Desarrollo'],
  created_by uuid references public.app_users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.technical_projects enable row level security;
revoke all on public.technical_projects from anon, authenticated;

create or replace function public.list_technical_projects(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype; v_projects jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_proyectos_tecnicos')::boolean,false)=false) then return jsonb_build_object('success',false,'error','No tienes permiso para consultar proyectos técnicos.'); end if;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb) into v_projects from public.technical_projects p;
  return jsonb_build_object('success',true,'projects',v_projects);
end $$;

create or replace function public.save_technical_project(p_token text, p_project_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_user public.app_users%rowtype; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>case when p_project_id is null then 'crear_proyectos_tecnicos' else 'editar_proyectos_tecnicos' end)::boolean,false)=false) then return jsonb_build_object('success',false,'error','No tienes permiso para registrar o editar proyectos.'); end if;
  if coalesce(trim(p_data->>'work_name'),'')='' then return jsonb_build_object('success',false,'error','El nombre de la obra es obligatorio.'); end if;
  if p_project_id is null then
    insert into public.technical_projects(budget_account,procurement_process,project_year,supplier_contractor,snip_code,has_lot,lot_number,work_name,fixed_assets,municipality,district,sector,population,linear_meters,budgeted_amount,appropriation_amount,awarded_amount,advance_20_amount,measurement_count,measurement_status,total_measured,total_paid,work_status,work_progress,created_by)
    values(p_data->>'budget_account',p_data->>'procurement_process',(p_data->>'project_year')::integer,p_data->>'supplier_contractor',p_data->>'snip_code',coalesce((p_data->>'has_lot')::boolean,false),p_data->>'lot_number',p_data->>'work_name',p_data->>'fixed_assets',p_data->>'municipality',p_data->>'district',p_data->>'sector',coalesce((p_data->>'population')::integer,0),nullif(p_data->>'linear_meters','')::numeric,coalesce((p_data->>'budgeted_amount')::numeric,0),coalesce((p_data->>'appropriation_amount')::numeric,0),coalesce((p_data->>'awarded_amount')::numeric,0),coalesce((p_data->>'advance_20_amount')::numeric,0),coalesce((p_data->>'measurement_count')::integer,0),coalesce(p_data->>'measurement_status','Pendiente'),coalesce((p_data->>'total_measured')::numeric,0),coalesce((p_data->>'total_paid')::numeric,0),coalesce(p_data->>'work_status','Planificación'),coalesce((p_data->>'work_progress')::numeric,0),v_user.id) returning id into v_id;
  else
    update public.technical_projects set budget_account=p_data->>'budget_account',procurement_process=p_data->>'procurement_process',project_year=(p_data->>'project_year')::integer,supplier_contractor=p_data->>'supplier_contractor',snip_code=p_data->>'snip_code',has_lot=coalesce((p_data->>'has_lot')::boolean,false),lot_number=p_data->>'lot_number',work_name=p_data->>'work_name',fixed_assets=p_data->>'fixed_assets',municipality=p_data->>'municipality',district=p_data->>'district',sector=p_data->>'sector',population=coalesce((p_data->>'population')::integer,0),linear_meters=nullif(p_data->>'linear_meters','')::numeric,budgeted_amount=coalesce((p_data->>'budgeted_amount')::numeric,0),appropriation_amount=coalesce((p_data->>'appropriation_amount')::numeric,0),awarded_amount=coalesce((p_data->>'awarded_amount')::numeric,0),advance_20_amount=coalesce((p_data->>'advance_20_amount')::numeric,0),measurement_count=coalesce((p_data->>'measurement_count')::integer,0),measurement_status=coalesce(p_data->>'measurement_status','Pendiente'),total_measured=coalesce((p_data->>'total_measured')::numeric,0),total_paid=coalesce((p_data->>'total_paid')::numeric,0),work_status=coalesce(p_data->>'work_status','Planificación'),work_progress=coalesce((p_data->>'work_progress')::numeric,0),updated_at=now() where id=p_project_id returning id into v_id;
  end if;
  if v_id is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  return jsonb_build_object('success',true,'id',v_id);
end $$;
revoke all on function public.list_technical_projects(text), public.save_technical_project(text,uuid,jsonb) from public;
grant execute on function public.list_technical_projects(text), public.save_technical_project(text,uuid,jsonb) to anon, authenticated;
