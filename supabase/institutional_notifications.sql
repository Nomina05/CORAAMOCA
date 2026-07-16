-- Centro de notificaciones y alertas institucionales.
-- Ejecutar después de complete_audit.sql.

alter table public.technical_projects
  add column if not exists contract_end_date date;

alter table public.app_notifications
  add column if not exists project_id uuid references public.technical_projects(id) on delete cascade,
  add column if not exists notification_type text not null default 'CUBICACION',
  add column if not exists severity text not null default 'medium',
  add column if not exists event_key text,
  add column if not exists action_section text not null default 'Resumen',
  add column if not exists email_status text not null default 'PENDIENTE';

create unique index if not exists app_notifications_user_event_key
  on public.app_notifications(user_id,event_key) where event_key is not null;

create or replace function public.refresh_institutional_notifications(p_user_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_direction text;
begin
  select * into v_user from public.app_users where id=p_user_id and active=true and suspended_at is null;
  if v_user.id is null then return; end if;
  v_direction:=case v_user.area
    when 'Técnica' then 'Dirección Técnica'
    when 'Financiera' then 'Dirección Administrativa y Financiera'
    when 'Gestión Humana' then 'Dirección de Recursos Humanos'
    when 'Comercial' then 'Dirección Comercial'
    else 'Dirección General' end;

  -- Cubicaciones que esperan la intervención autorizada del usuario.
  insert into public.app_notifications(user_id,measurement_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,m.id,p.id,'CUBICACION','high','CUBICACION:'||m.id||':'||m.status,
    'Cubicación pendiente',
    case m.status when 'Cubicada' then 'Debe revisar ' when 'Revisada' then 'Debe tramitar el libramiento de '
      when 'Libramiento' then 'Debe registrar el pago de ' end||m.code||' · '||p.work_name,'Cubicaciones'
  from public.project_measurements m join public.technical_projects p on p.id=m.project_id
  where m.status<>'Pagada'
    and (v_user.role='Administrador'
      or (m.status='Cubicada' and coalesce((v_user.permissions->>'revisar_cubicaciones')::boolean,false))
      or (m.status='Revisada' and coalesce((v_user.permissions->>'libramiento_cubicaciones')::boolean,false))
      or (m.status='Libramiento' and coalesce((v_user.permissions->>'pagar_cubicaciones')::boolean,false)))
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set title=excluded.title,message=excluded.message,severity=excluded.severity,created_at=now();

  -- Apropiación insuficiente.
  insert into public.app_notifications(user_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,p.id,'PRESUPUESTO',
    case when p.total_paid>p.appropriation_amount then 'critical' else 'high' end,
    'PRESUPUESTO:'||p.id,'Apropiación insuficiente',
    p.work_name||' presenta compromisos o pagos superiores a la apropiación disponible.','Gestión Presupuestaria'
  from public.technical_projects p
  where (p.awarded_amount>p.appropriation_amount or p.total_paid>p.appropriation_amount)
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set message=excluded.message,severity=excluded.severity,created_at=now();

  -- Contratos que vencen dentro de los próximos 30 días.
  insert into public.app_notifications(user_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,p.id,'CONTRATO',
    case when p.contract_end_date<=current_date+7 then 'critical' else 'high' end,
    'CONTRATO:'||p.id,'Contrato próximo a vencer',
    p.work_name||' vence el '||to_char(p.contract_end_date,'DD/MM/YYYY')||'.','Proyectos Técnicos'
  from public.technical_projects p
  where p.contract_end_date between current_date and current_date+30
    and p.work_status not in ('Finalizada','Cancelada')
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set message=excluded.message,severity=excluded.severity,created_at=now();

  -- Obras detenidas o fuera de fecha.
  insert into public.app_notifications(user_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,p.id,'OBRA',case when p.work_status='Pausada' then 'critical' else 'high' end,
    'OBRA:'||p.id,'Obra detenida o atrasada',
    case when p.work_status='Pausada' then p.work_name||' está registrada como pausada.'
      else p.work_name||' superó su fecha prevista de finalización.' end,'Proyectos Técnicos'
  from public.technical_projects p
  where (p.work_status='Pausada' or (p.planned_end_date<current_date and p.work_status not in ('Finalizada','Cancelada')))
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set message=excluded.message,severity=excluded.severity,created_at=now();

  -- Libramientos pendientes de pago.
  insert into public.app_notifications(user_id,measurement_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,m.id,p.id,'PAGO','high','PAGO:'||m.id,'Pago pendiente',
    m.code||' · '||p.work_name||' está en libramiento por RD$ '||to_char(m.amount,'FM999G999G999G990D00')||'.','Cubicaciones'
  from public.project_measurements m join public.technical_projects p on p.id=m.project_id
  where m.status='Libramiento'
    and (v_user.role='Administrador' or coalesce((v_user.permissions->>'pagar_cubicaciones')::boolean,false))
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set message=excluded.message,severity=excluded.severity,created_at=now();

  -- Expedientes sin documentos mínimos: contrato, proceso de compra y presupuesto.
  insert into public.app_notifications(user_id,project_id,notification_type,severity,event_key,title,message,action_section)
  select v_user.id,p.id,'DOCUMENTO','medium','DOCUMENTO:'||p.id,'Documentos faltantes',
    p.work_name||' no posee: '||
      concat_ws(', ',
        case when not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='CONTRATO') then 'contrato' end,
        case when not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PROCESO_COMPRA') then 'proceso de compra' end,
        case when not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PRESUPUESTO') then 'presupuesto' end
      )||'.','Proyectos Técnicos'
  from public.technical_projects p
  where (not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='CONTRATO')
      or not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PROCESO_COMPRA')
      or not exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PRESUPUESTO'))
    and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
  on conflict(user_id,event_key) where event_key is not null do update
    set message=excluded.message,severity=excluded.severity,created_at=now();

  -- Cerrar avisos que ya dejaron de estar vigentes.
  update public.app_notifications n set read_at=coalesce(n.read_at,now())
  where n.user_id=v_user.id and n.event_key is not null and n.read_at is null
    and ((n.notification_type='CUBICACION' and not exists(
      select 1 from public.project_measurements m where m.id=n.measurement_id and n.event_key='CUBICACION:'||m.id||':'||m.status and m.status<>'Pagada'))
    or (n.notification_type='PAGO' and not exists(select 1 from public.project_measurements m where m.id=n.measurement_id and m.status='Libramiento'))
    or (n.notification_type='PRESUPUESTO' and not exists(select 1 from public.technical_projects p where p.id=n.project_id and (p.awarded_amount>p.appropriation_amount or p.total_paid>p.appropriation_amount)))
    or (n.notification_type='CONTRATO' and not exists(select 1 from public.technical_projects p where p.id=n.project_id and p.contract_end_date between current_date and current_date+30 and p.work_status not in ('Finalizada','Cancelada')))
    or (n.notification_type='OBRA' and not exists(select 1 from public.technical_projects p where p.id=n.project_id and (p.work_status='Pausada' or (p.planned_end_date<current_date and p.work_status not in ('Finalizada','Cancelada')))))
    or (n.notification_type='DOCUMENTO' and exists(
      select 1 from public.technical_projects p where p.id=n.project_id
        and exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='CONTRATO')
        and exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PROCESO_COMPRA')
        and exists(select 1 from public.project_documents d where d.project_id=p.id and d.category='PRESUPUESTO'))));
end $$;

create or replace function public.list_app_notifications(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  perform public.refresh_institutional_notifications(v_user.id);
  select coalesce(jsonb_agg(to_jsonb(n) order by n.read_at nulls first,n.created_at desc),'[]'::jsonb) into v_items
  from (select id,title,message,notification_type,severity,project_id,measurement_id,action_section,email_status,read_at,created_at
    from public.app_notifications where user_id=v_user.id order by read_at nulls first,created_at desc limit 100)n;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

create or replace function public.mark_app_notifications_read(p_token text,p_notification_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
  update public.app_notifications set read_at=coalesce(read_at,now())
  where user_id=v_user.id and (p_notification_id is null or id=p_notification_id);
  return jsonb_build_object('success',true);
end $$;

create or replace function public.set_project_contract_end_date(p_token text,p_project_id uuid,p_date date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_proyectos_tecnicos')::boolean,false)=false
    and coalesce((v_user.permissions->>'crear_proyectos_tecnicos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para actualizar el vencimiento contractual.'); end if;
  update public.technical_projects set contract_end_date=p_date,updated_at=now() where id=p_project_id;
  return jsonb_build_object('success',found);
end $$;

grant execute on function public.list_app_notifications(text),public.mark_app_notifications_read(text,uuid),
  public.set_project_contract_end_date(text,uuid,date) to anon,authenticated;
