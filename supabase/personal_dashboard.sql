-- Panel personalizado por usuario.
-- Ejecutar después de security_permissions_audit.sql.

alter table public.technical_projects
  add column if not exists responsible_user_id uuid references public.app_users(id);

create or replace function public.get_personal_dashboard(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare
  v_user public.app_users%rowtype;
  v_direction text;
  v_projects jsonb;
  v_tasks jsonb;
  v_alerts jsonb;
  v_activity jsonb;
  v_modules jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now()
    and u.active=true and u.suspended_at is null;
  if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;

  v_direction:=case v_user.area
    when 'Técnica' then 'Dirección Técnica'
    when 'Financiera' then 'Dirección Administrativa y Financiera'
    when 'Gestión Humana' then 'Dirección de Recursos Humanos'
    when 'Comercial' then 'Dirección Comercial'
    else 'Dirección General' end;

  select coalesce(jsonb_agg(jsonb_build_object('key',key,'label',label) order by sort_order),'[]'::jsonb) into v_modules
  from (values
    ('ver_resumen','Resumen',1),('ver_proyectos','Proyectos institucionales',2),
    ('ver_proyectos_tecnicos','Proyectos y obras',3),('ver_cubicaciones','Cubicaciones',4),
    ('ver_gestion_presupuestaria','Gestión presupuestaria',5),('ver_catalogos','Compras, cuentas y proveedores',6),('ver_reportes','Reportes',7),
    ('ver_recursos_humanos','Recursos Humanos',8),('ver_estructura_organizacional','Estructura organizacional',9)
  ) m(key,label,sort_order)
  where v_user.role='Administrador' or coalesce((v_user.permissions->>key)::boolean,false);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc),'[]'::jsonb) into v_projects from (
    select p.id,p.work_name,p.snip_code,p.municipality,p.sector,p.work_status,p.work_progress,
      p.budgeted_amount,p.appropriation_amount,p.awarded_amount,p.total_paid,p.updated_at,
      coalesce(r.full_name,v_direction) responsible_name
    from public.technical_projects p left join public.app_users r on r.id=p.responsible_user_id
    where v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction
      or v_direction=any(p.participating_directions)
    order by p.updated_at desc limit 8
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into v_tasks from (
    select m.id,m.code,m.status,m.amount,m.created_at,p.work_name,p.municipality,p.sector,
      case m.status when 'Cubicada' then 'Revisar cubicación' when 'Revisada' then 'Enviar a libramiento'
        when 'Libramiento' then 'Registrar pago' end task_label
    from public.project_measurements m join public.technical_projects p on p.id=m.project_id
    where (v_user.role='Administrador'
      or (m.status='Cubicada' and coalesce((v_user.permissions->>'revisar_cubicaciones')::boolean,false))
      or (m.status='Revisada' and coalesce((v_user.permissions->>'libramiento_cubicaciones')::boolean,false))
      or (m.status='Libramiento' and coalesce((v_user.permissions->>'pagar_cubicaciones')::boolean,false)))
      and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
    order by m.created_at limit 10
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.severity desc,x.updated_at desc),'[]'::jsonb) into v_alerts from (
    select p.id,p.work_name,p.updated_at,
      case when p.total_paid>p.appropriation_amount then 'critical'
        when p.awarded_amount>p.appropriation_amount then 'high'
        when p.appropriation_amount<p.budgeted_amount then 'medium' else 'low' end severity,
      case when p.total_paid>p.appropriation_amount then 'El total pagado supera la apropiación.'
        when p.awarded_amount>p.appropriation_amount then 'El monto adjudicado supera la apropiación.'
        when p.appropriation_amount<p.budgeted_amount then 'La apropiación es menor que el presupuesto.'
        else 'Revisión presupuestaria requerida.' end message
    from public.technical_projects p
    where (p.total_paid>p.appropriation_amount or p.awarded_amount>p.appropriation_amount or p.appropriation_amount<p.budgeted_amount)
      and (v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction or v_direction=any(p.participating_directions))
    order by p.updated_at desc limit 8
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_activity from (
    select a.action,a.from_status,a.to_status,a.comments,a.created_at,u.full_name user_name,
      m.code,p.work_name
    from public.measurement_audit a join public.app_users u on u.id=a.user_id
      join public.project_measurements m on m.id=a.measurement_id join public.technical_projects p on p.id=m.project_id
    where v_user.role='Administrador' or p.responsible_user_id=v_user.id or p.lead_direction=v_direction
      or v_direction=any(p.participating_directions)
    order by a.created_at desc limit 10
  ) x;

  return jsonb_build_object('success',true,'direction',v_direction,'department',v_user.department,
    'modules',v_modules,'tasks',v_tasks,'projects',v_projects,'alerts',v_alerts,'activity',v_activity);
end $$;

revoke all on function public.get_personal_dashboard(text) from public;
grant execute on function public.get_personal_dashboard(text) to anon,authenticated;
