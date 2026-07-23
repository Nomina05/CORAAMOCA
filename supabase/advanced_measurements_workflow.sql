-- Flujo avanzado: Cubicada -> Revisada -> Libramiento -> Pagada.
-- Ejecutar después de cubicaciones_workflow.sql y security_permissions_audit.sql.

alter table public.project_measurements drop constraint if exists project_measurements_status_check;
update public.project_measurements set status='Cubicada' where status='Registrada';
alter table public.project_measurements
  add constraint project_measurements_status_check check(status in ('Cubicada','Revisada','Libramiento','Pagada'));
alter table public.project_measurements alter column status set default 'Cubicada';

create table if not exists public.measurement_documents (
  id uuid primary key default gen_random_uuid(),
  measurement_id uuid not null references public.project_measurements(id) on delete cascade,
  stage text not null check(stage in ('Cubicada','Revisada','Libramiento','Pagada')),
  document_name text not null,
  document_url text not null,
  uploaded_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  measurement_id uuid references public.project_measurements(id) on delete cascade,
  title text not null,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.measurement_documents enable row level security;
alter table public.app_notifications enable row level security;
revoke all on public.measurement_documents,public.app_notifications from anon,authenticated;

create or replace function public.notify_measurement_next_step(p_measurement_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_permission text; v_code text; v_work text;
begin
  v_permission:=case p_status when 'Cubicada' then 'revisar_cubicaciones' when 'Revisada' then 'libramiento_cubicaciones' when 'Libramiento' then 'pagar_cubicaciones' else null end;
  if v_permission is null then return; end if;
  select m.code,p.work_name into v_code,v_work from public.project_measurements m join public.technical_projects p on p.id=m.project_id where m.id=p_measurement_id;
  insert into public.app_notifications(user_id,measurement_id,title,message)
  select u.id,p_measurement_id,'Cubicación pendiente',
    case p_status when 'Cubicada' then 'Debe revisar ' when 'Revisada' then 'Debe enviar a libramiento ' when 'Libramiento' then 'Debe registrar el pago de ' end||v_code||' · '||v_work
  from public.app_users u
  where u.active=true and u.suspended_at is null
    and (u.role='Administrador' or coalesce((u.permissions->>v_permission)::boolean,false))
    and not exists(select 1 from public.app_notifications n where n.user_id=u.id and n.measurement_id=p_measurement_id and n.read_at is null and n.message like '%'||v_code||'%');
end $$;

create or replace function public.transition_measurement_advanced(p_token text,p_measurement_id uuid,p_action text,p_comments text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_m public.project_measurements%rowtype; v_target text; v_permission text;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select * into v_m from public.project_measurements where id=p_measurement_id for update;
  if v_m.id is null then return jsonb_build_object('success',false,'error','Cubicación no encontrada.'); end if;
  if v_m.status='Pagada' then return jsonb_build_object('success',false,'error','Una cubicación pagada no puede modificarse.'); end if;

  if upper(p_action)='ADVANCE' then
    v_target:=case v_m.status when 'Cubicada' then 'Revisada' when 'Revisada' then 'Libramiento' when 'Libramiento' then 'Pagada' end;
    v_permission:=case v_target when 'Revisada' then 'revisar_cubicaciones' when 'Libramiento' then 'libramiento_cubicaciones' when 'Pagada' then 'pagar_cubicaciones' end;
  elsif upper(p_action)='RETURN' then
    if length(trim(coalesce(p_comments,'')))<5 then return jsonb_build_object('success',false,'error','La observación de devolución es obligatoria.'); end if;
    v_target:=case v_m.status when 'Revisada' then 'Cubicada' when 'Libramiento' then 'Revisada' end;
    v_permission:=case v_m.status when 'Revisada' then 'revisar_cubicaciones' when 'Libramiento' then 'libramiento_cubicaciones' end;
  else return jsonb_build_object('success',false,'error','Acción no válida.');
  end if;
  if v_target is null then return jsonb_build_object('success',false,'error','La transición no corresponde al flujo autorizado.'); end if;
  if v_user.role<>'Administrador' and coalesce((v_user.permissions->>v_permission)::boolean,false)=false then
    return jsonb_build_object('success',false,'error','No posee permiso para esta transición.');
  end if;

  update public.project_measurements set status=v_target,
    reviewed_by=case when v_target='Revisada' and upper(p_action)='ADVANCE' then v_user.id else reviewed_by end,
    reviewed_at=case when v_target='Revisada' and upper(p_action)='ADVANCE' then now() else reviewed_at end,
    released_by=case when v_target='Libramiento' then v_user.id else released_by end,
    released_at=case when v_target='Libramiento' then now() else released_at end,
    paid_by=case when v_target='Pagada' then v_user.id else paid_by end,
    paid_at=case when v_target='Pagada' then now() else paid_at end,updated_at=now()
  where id=v_m.id;
  insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount)
  values(v_m.id,case when upper(p_action)='RETURN' then 'Devolución' else 'Cambio de estatus' end,v_m.status,v_target,v_user.id,p_comments,v_m.amount);
  update public.app_notifications set read_at=now() where measurement_id=v_m.id and user_id=v_user.id and read_at is null;
  if v_target='Pagada' then
    update public.technical_projects set work_progress=least(100,work_progress+v_m.progress_increment),
      measurement_status='Pagada',updated_at=now() where id=v_m.project_id;
  else
    update public.technical_projects set measurement_status=v_target,updated_at=now() where id=v_m.project_id;
    perform public.notify_measurement_next_step(v_m.id,v_target);
  end if;
  return jsonb_build_object('success',true,'status',v_target);
end $$;

create or replace function public.add_measurement_document(p_token text,p_measurement_id uuid,p_name text,p_url text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_m public.project_measurements%rowtype; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select * into v_m from public.project_measurements where id=p_measurement_id;
  if v_m.id is null then return jsonb_build_object('success',false,'error','Cubicación no encontrada.'); end if;
  if length(trim(p_name))<3 or p_url !~ '^https?://' then return jsonb_build_object('success',false,'error','Indique un nombre y un enlace válido al documento.'); end if;
  insert into public.measurement_documents(measurement_id,stage,document_name,document_url,uploaded_by)
  values(v_m.id,v_m.status,trim(p_name),trim(p_url),v_user.id) returning id into v_id;
  insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount)
  values(v_m.id,'Documento adjunto',v_m.status,v_m.status,v_user.id,trim(p_name),v_m.amount);
  return jsonb_build_object('success',true,'id',v_id);
end $$;

create or replace function public.create_measurement(p_token text,p_project_id uuid,p_amount numeric,p_progress numeric,p_description text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_number integer; v_id uuid; v_code text;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'registrar_cubicaciones')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para registrar cubicaciones.'); end if;
  perform 1 from public.technical_projects where id=p_project_id;
  if not found then return jsonb_build_object('success',false,'error','Obra no encontrada.'); end if;
  if p_amount<=0 then return jsonb_build_object('success',false,'error','El monto debe ser mayor que cero.'); end if;
  select coalesce(max(measurement_number),0)+1 into v_number from public.project_measurements where project_id=p_project_id;
  v_code:='CUB-'||to_char(now(),'YYYY')||'-'||substr(replace(p_project_id::text,'-',''),1,6)||'-'||lpad(v_number::text,2,'0');
  insert into public.project_measurements(project_id,measurement_number,code,amount,progress_increment,description,status,registered_by)
  values(p_project_id,v_number,v_code,p_amount,coalesce(p_progress,0),p_description,'Cubicada',v_user.id) returning id into v_id;
  insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount)
  values(v_id,'Registro',null,'Cubicada',v_user.id,p_description,p_amount);
  update public.technical_projects set measurement_count=measurement_count+1,measurement_status='Cubicada',updated_at=now() where id=p_project_id;
  perform public.notify_measurement_next_step(v_id,'Cubicada');
  return jsonb_build_object('success',true,'id',v_id,'code',v_code);
end $$;

create or replace function public.list_measurements(p_token text,p_project_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_cubicaciones')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar cubicaciones.'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (
    select m.*,p.work_name,p.snip_code,p.sector,p.municipality,u.full_name registered_by_name,
      reviewer.full_name reviewed_by_name,releaser.full_name released_by_name,payer.full_name paid_by_name,
      (select coalesce(jsonb_agg(jsonb_build_object('action',a.action,'from_status',a.from_status,'to_status',a.to_status,
        'comments',a.comments,'created_at',a.created_at,'user_name',au.full_name) order by a.created_at),'[]'::jsonb)
        from public.measurement_audit a join public.app_users au on au.id=a.user_id where a.measurement_id=m.id) audit,
      (select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'stage',d.stage,'name',d.document_name,'url',d.document_url,
        'created_at',d.created_at,'user_name',du.full_name) order by d.created_at),'[]'::jsonb)
        from public.measurement_documents d join public.app_users du on du.id=d.uploaded_by where d.measurement_id=m.id) documents
    from public.project_measurements m join public.technical_projects p on p.id=m.project_id
      join public.app_users u on u.id=m.registered_by left join public.app_users reviewer on reviewer.id=m.reviewed_by
      left join public.app_users releaser on releaser.id=m.released_by left join public.app_users payer on payer.id=m.paid_by
    where p_project_id is null or m.project_id=p_project_id
  )x;
  return jsonb_build_object('success',true,'measurements',v_items);
end $$;

create or replace function public.list_app_notifications(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc),'[]'::jsonb) into v_items
  from (select id,title,message,measurement_id,read_at,created_at from public.app_notifications where user_id=v_user.id order by created_at desc limit 30)n;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

create or replace function public.admin_correct_paid_measurement(p_token text,p_measurement_id uuid,p_amount numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_m public.project_measurements%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or v_user.role<>'Administrador' then
    return jsonb_build_object('success',false,'error','Solo el administrador puede corregir montos pagados.');
  end if;
  select * into v_m from public.project_measurements where id=p_measurement_id for update;
  if v_m.id is null then return jsonb_build_object('success',false,'error','Cubicación no encontrada.'); end if;
  if v_m.status<>'Pagada' then return jsonb_build_object('success',false,'error','Solo se pueden corregir cubicaciones en estado Pagada.'); end if;
  if coalesce(p_amount,0)<=0 then return jsonb_build_object('success',false,'error','El monto corregido debe ser mayor que cero.'); end if;
  if length(trim(coalesce(p_reason,'')))<5 then return jsonb_build_object('success',false,'error','Debe indicar el motivo de la corrección.'); end if;
  if p_amount=v_m.amount then return jsonb_build_object('success',false,'error','El monto nuevo debe ser diferente al monto actual.'); end if;
  update public.project_measurements set amount=round(p_amount,2),updated_at=now() where id=v_m.id;
  insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount)
  values(v_m.id,'Corrección administrativa de pago','Pagada','Pagada',v_user.id,
    'Monto anterior: '||v_m.amount||'. Monto nuevo: '||round(p_amount,2)||'. Motivo: '||trim(p_reason),round(p_amount,2));
  perform public.recalculate_project_financials(v_m.project_id);
  return jsonb_build_object('success',true,'id',v_m.id,'project_id',v_m.project_id,'previous_amount',v_m.amount,'amount',round(p_amount,2));
end $$;

grant execute on function public.transition_measurement_advanced(text,uuid,text,text),
  public.add_measurement_document(text,uuid,text,text),public.list_app_notifications(text),
  public.create_measurement(text,uuid,numeric,numeric,text),public.list_measurements(text,uuid),
  public.admin_correct_paid_measurement(text,uuid,numeric,text) to anon,authenticated;
