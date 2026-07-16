-- Expediente digital de proyectos.
-- Ejecutar después de budget_management.sql.

create table if not exists public.project_documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.technical_projects(id) on delete cascade,
  category text not null check(category in ('CONTRATO','PROCESO_COMPRA','PRESUPUESTO','FOTO_ANTES','FOTO_DURANTE','FOTO_DESPUES','LIBRAMIENTO','FACTURA','COMPROBANTE','INFORME_TECNICO','ACTA_RECEPCION','OTRO')),
  document_name text not null,
  document_url text not null,
  description text not null default '',
  document_date date,
  uploaded_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.project_change_history (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.technical_projects(id) on delete cascade,
  changed_by uuid references public.app_users(id),
  action text not null,
  previous_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

alter table public.project_documents enable row level security;
alter table public.project_change_history enable row level security;
revoke all on public.project_documents,public.project_change_history from anon,authenticated;

create or replace function public.get_project_digital_file(p_token text,p_project_id uuid)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_project jsonb; v_documents jsonb; v_measurements jsonb; v_history jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_expediente_proyecto')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar el expediente.'); end if;
  select to_jsonb(p) into v_project from public.technical_projects p where p.id=p_project_id;
  if v_project is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'category',d.category,'name',d.document_name,'url',d.document_url,
    'description',d.description,'document_date',d.document_date,'created_at',d.created_at,'user_name',u.full_name) order by d.created_at desc),'[]'::jsonb)
  into v_documents from public.project_documents d join public.app_users u on u.id=d.uploaded_by where d.project_id=p_project_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'code',m.code,'number',m.measurement_number,'status',m.status,
    'amount',m.amount,'progress',m.progress_increment,'created_at',m.created_at) order by m.measurement_number),'[]'::jsonb)
  into v_measurements from public.project_measurements m where m.project_id=p_project_id;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_history from (
    select h.action,h.previous_data,h.new_data,h.created_at,u.full_name user_name from public.project_change_history h
    left join public.app_users u on u.id=h.changed_by where h.project_id=p_project_id
    union all
    select 'MODIFICACION_PRESUPUESTARIA',null,jsonb_build_object('type',m.modification_type,'amount',m.amount,'description',m.description,'reference',m.reference),m.created_at,u.full_name
    from public.project_budget_modifications m join public.app_users u on u.id=m.created_by where m.project_id=p_project_id
  )x;
  return jsonb_build_object('success',true,'project',v_project,'documents',v_documents,'measurements',v_measurements,'history',v_history);
end $$;

create or replace function public.add_project_document(p_token text,p_project_id uuid,p_category text,p_name text,p_url text,p_description text,p_document_date date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'gestionar_expediente_proyecto')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para agregar documentos.'); end if;
  if p_category not in ('CONTRATO','PROCESO_COMPRA','PRESUPUESTO','FOTO_ANTES','FOTO_DURANTE','FOTO_DESPUES','LIBRAMIENTO','FACTURA','COMPROBANTE','INFORME_TECNICO','ACTA_RECEPCION','OTRO')
    or length(trim(p_name))<3 or p_url !~ '^https?://' then return jsonb_build_object('success',false,'error','Categoría, nombre o enlace no válido.'); end if;
  insert into public.project_documents(project_id,category,document_name,document_url,description,document_date,uploaded_by)
  values(p_project_id,p_category,trim(p_name),trim(p_url),coalesce(trim(p_description),''),p_document_date,v_user.id) returning id into v_id;
  insert into public.project_change_history(project_id,changed_by,action,new_data)
  values(p_project_id,v_user.id,'DOCUMENTO_AGREGADO',jsonb_build_object('id',v_id,'category',p_category,'name',p_name));
  return jsonb_build_object('success',true,'id',v_id);
end $$;

create or replace function public.record_project_change(p_token text,p_project_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_project jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select to_jsonb(p) into v_project from public.technical_projects p where p.id=p_project_id;
  if v_project is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  insert into public.project_change_history(project_id,changed_by,action,new_data)
  values(p_project_id,v_user.id,case when p_action='CREATE' then 'PROYECTO_CREADO' else 'PROYECTO_MODIFICADO' end,v_project);
  return jsonb_build_object('success',true);
end $$;

grant execute on function public.get_project_digital_file(text,uuid),
  public.add_project_document(text,uuid,text,text,text,text,date),
  public.record_project_change(text,uuid,text) to anon,authenticated;
