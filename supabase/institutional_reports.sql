-- Reportes institucionales.
-- Ejecutar después de administrative_catalogs.sql.

alter table public.technical_projects add column if not exists planned_end_date date;

create or replace function public.get_institutional_reports(p_token text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_investment jsonb; v_projects jsonb; v_budget jsonb;
  v_pending jsonb; v_suppliers jsonb; v_delayed jsonb; v_progress jsonb; v_public_investment jsonb;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_reportes')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar reportes.'); end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_investment desc),'[]'::jsonb) into v_investment from (
    select municipality,coalesce(nullif(sector,''),'Sin sector') sector,count(*) projects,
      sum(budgeted_amount) total_investment,sum(total_paid) total_paid
    from public.technical_projects where p_year is null or project_year=p_year
    group by municipality,coalesce(nullif(sector,''),'Sin sector'))x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.project_year desc,x.projects desc),'[]'::jsonb) into v_projects from (
    select project_year,work_status,count(*) projects,sum(budgeted_amount) budget,sum(total_paid) paid
    from public.technical_projects where p_year is null or project_year=p_year group by project_year,work_status)x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.work_name),'[]'::jsonb) into v_budget from (
    select id,work_name,snip_code,project_year,budgeted_amount,appropriation_amount,committed_amount,awarded_amount,
      total_measured,total_paid,(budgeted_amount-total_paid) pending_balance,
      case when budgeted_amount>0 then round(total_paid*100/budgeted_amount,2) else 0 end financial_progress
    from public.technical_projects where p_year is null or project_year=p_year)x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into v_pending from (
    select m.id,m.code,m.status,m.amount,m.created_at,p.work_name,p.municipality,p.sector,
      case m.status when 'Cubicada' then 'Revisión' when 'Revisada' then 'Libramiento' when 'Libramiento' then 'Pago' end pending_step
    from public.project_measurements m join public.technical_projects p on p.id=m.project_id
    where m.status<>'Pagada' and (p_year is null or p.project_year=p_year))x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_paid desc),'[]'::jsonb) into v_suppliers from (
    select supplier_contractor supplier,count(*) projects,sum(awarded_amount) awarded,sum(total_paid) total_paid,
      jsonb_agg(jsonb_build_object(
        'id',id,'snip_code',coalesce(snip_code,''),'procurement_process',coalesce(procurement_process,''),
        'project_type',case when lower(trim(coalesce(fixed_assets,''))) ~ '(^|[^[:alpha:]])activos?[[:space:]]+fijos?([^[:alpha:]]|$)'
          then coalesce(nullif(work_type,''),nullif(work_name,''),'Activo fijo') else coalesce(nullif(work_type,''),nullif(work_name,''),'Obra') end,
        'record_type',case when lower(trim(coalesce(fixed_assets,''))) ~ '(^|[^[:alpha:]])activos?[[:space:]]+fijos?([^[:alpha:]]|$)' then 'ACTIVO_FIJO' else 'OBRA' end,
        'awarded_amount',coalesce(awarded_amount,0),'measurement_count',coalesce(measurement_count,0),
        'total_measured',coalesce(total_measured,0),'total_paid',coalesce(total_paid,0),
        'payment_percentage',case when coalesce(awarded_amount,0)>0 then round(coalesce(total_paid,0)*100/awarded_amount,2) else 0 end,
        'remaining_payment',greatest(coalesce(awarded_amount,0)-coalesce(total_paid,0),0)
      ) order by snip_code,work_name) history
    from public.technical_projects where p_year is null or project_year=p_year group by supplier_contractor)x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.planned_end_date),'[]'::jsonb) into v_delayed from (
    select id,work_name,snip_code,municipality,sector,planned_end_date,work_status,work_progress,
      current_date-planned_end_date delayed_days
    from public.technical_projects where planned_end_date<current_date and work_status not in ('Finalizada','Cancelada')
      and (p_year is null or project_year=p_year))x;

  select coalesce(jsonb_agg(to_jsonb(x) order by abs(x.physical_progress-x.financial_progress) desc),'[]'::jsonb) into v_progress from (
    select id,work_name,snip_code,work_progress physical_progress,
      case when budgeted_amount>0 then round(total_paid*100/budgeted_amount,2) else 0 end financial_progress
    from public.technical_projects where p_year is null or project_year=p_year)x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.location_name,x.sector,x.work_name),'[]'::jsonb)
  into v_public_investment from (
    select p.id,case when lower(trim(coalesce(p.fixed_assets,''))) ~ '(^|[^[:alpha:]])activos?[[:space:]]+fijos?([^[:alpha:]]|$)' then 'ACTIVO_FIJO' else 'OBRA' end record_type,
      p.snip_code,case
        when lower(trim(coalesce(p.fixed_assets,''))) ~ '(^|[^[:alpha:]])activos?[[:space:]]+fijos?([^[:alpha:]]|$)'
          and lower(trim(p.fixed_assets)) not in ('activo fijo','activos fijos') then p.fixed_assets
        else coalesce(nullif(p.work_type,''),nullif(p.work_name,''),case when lower(trim(coalesce(p.fixed_assets,''))) ~ '(^|[^[:alpha:]])activos?[[:space:]]+fijos?([^[:alpha:]]|$)' then 'Tipo de activo no especificado' else 'Tipo de obra no especificado' end)
      end work_type,p.work_name,
      p.municipality,p.district,coalesce(nullif(p.district,''),p.municipality,'Sin ubicación') location_name,
      case when nullif(p.district,'') is null then 'Municipio' else 'Distrito' end location_type,
      coalesce(nullif(p.sector,''),'Sin sector') sector,coalesce(p.population,0) population,
      coalesce(p.linear_meters,0) linear_meters,coalesce(p.budgeted_amount,0) budgeted_amount,coalesce(p.appropriation_amount,0) appropriation_amount,coalesce(p.committed_amount,0) committed_amount,coalesce(p.awarded_amount,0) awarded_amount,
      coalesce(p.advance_20_amount,0) advance_20_amount,coalesce(p.measurement_status,'Pendiente') measurement_status,
      coalesce(p.total_measured,0) total_measured,coalesce(p.total_paid,0) total_paid,
      coalesce(p.work_status,'Sin estatus') work_status,coalesce(p.work_progress,0) work_progress,
      p.project_year
    from public.technical_projects p where p_year is null or p.project_year=p_year
  )x;

  return jsonb_build_object('success',true,'year',p_year,'investment',v_investment,'projectsByYearStatus',v_projects,
    'budgetExecution',v_budget,'pendingMeasurements',v_pending,'supplierPayments',v_suppliers,
    'delayedProjects',v_delayed,'physicalFinancial',v_progress,'publicInvestment',v_public_investment,'generated_at',now());
end $$;

grant execute on function public.get_institutional_reports(text,integer) to anon,authenticated;

create or replace function public.set_project_planned_end_date(p_token text,p_project_id uuid,p_date date)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_proyectos_tecnicos')::boolean,false)=false
    and coalesce((v_user.permissions->>'crear_proyectos_tecnicos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para actualizar la fecha prevista.'); end if;
  update public.technical_projects set planned_end_date=p_date,updated_at=now() where id=p_project_id;
  return jsonb_build_object('success',found);
end $$;
grant execute on function public.set_project_planned_end_date(text,uuid,date) to anon,authenticated;
