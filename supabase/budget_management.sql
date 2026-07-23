-- Gestión presupuestaria integral.
-- Ejecutar después de advanced_measurements_workflow.sql.

alter table public.technical_projects
  add column if not exists committed_amount numeric(18,2) not null default 0,
  add column if not exists fixed_asset_paid_amount numeric(18,2) not null default 0,
  add column if not exists paid_measurements_amount numeric(18,2) not null default 0,
  add column if not exists budget_closed_at timestamptz,
  add column if not exists budget_closed_by uuid references public.app_users(id);

create table if not exists public.project_budget_modifications (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.technical_projects(id) on delete cascade,
  modification_type text not null check(modification_type in ('PRESUPUESTO','APROPIACION')),
  amount numeric(18,2) not null check(amount<>0),
  description text not null,
  reference text not null default '',
  created_by uuid not null references public.app_users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.budget_year_closures (
  id uuid primary key default gen_random_uuid(),
  budget_year integer not null unique check(budget_year between 2000 and 2100),
  notes text not null default '',
  closed_by uuid not null references public.app_users(id),
  closed_at timestamptz not null default now()
);

alter table public.project_budget_modifications enable row level security;
alter table public.budget_year_closures enable row level security;
revoke all on public.project_budget_modifications,public.budget_year_closures from anon,authenticated;

create or replace function public.recalculate_project_financials(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_paid numeric; v_measured numeric; v_paid_progress numeric;
begin
  select coalesce(sum(amount),0) into v_paid from public.project_measurements where project_id=p_project_id and status='Pagada';
  select coalesce(sum(amount),0) into v_measured from public.project_measurements where project_id=p_project_id;
  select coalesce(sum(progress_increment),0) into v_paid_progress from public.project_measurements where project_id=p_project_id and status='Pagada';
  update public.technical_projects set paid_measurements_amount=v_paid,
    total_measured=v_measured,total_paid=coalesce(fixed_asset_paid_amount,0)+coalesce(advance_20_amount,0)+v_paid,
    work_progress=least(100,case when coalesce(awarded_amount,0)>0 then round(coalesce(advance_20_amount,0)*100/awarded_amount,2) else 0 end+v_paid_progress),updated_at=now()
  where id=p_project_id;
end $$;

create or replace function public.sync_measurement_financials()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin
  perform public.recalculate_project_financials(coalesce(new.project_id,old.project_id));
  return coalesce(new,old);
end $$;
drop trigger if exists trg_sync_measurement_financials on public.project_measurements;
create trigger trg_sync_measurement_financials after insert or update or delete on public.project_measurements
for each row execute function public.sync_measurement_financials();

do $$ declare v_project record; begin
  for v_project in select id from public.technical_projects loop
    perform public.recalculate_project_financials(v_project.id);
  end loop;
end $$;

create or replace function public.get_budget_management(p_token text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb; v_closed boolean;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'ver_gestion_presupuestaria')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para consultar la gestión presupuestaria.'); end if;
  select exists(select 1 from public.budget_year_closures where budget_year=coalesce(p_year,extract(year from now())::integer)) into v_closed;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.project_year desc,x.work_name),'[]'::jsonb) into v_items from (
    select p.id,p.work_name,p.snip_code,p.project_year,p.work_status,p.work_progress,
      p.budgeted_amount initial_budget,
      p.budgeted_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='PRESUPUESTO'),0) current_budget,
      p.appropriation_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='APROPIACION'),0) current_appropriation,
      p.committed_amount,p.awarded_amount,p.total_measured,p.fixed_asset_paid_amount,p.advance_20_amount,
      p.paid_measurements_amount,p.total_paid,
      (p.appropriation_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='APROPIACION'),0))-p.committed_amount available_appropriation,
      p.total_paid>(p.appropriation_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='APROPIACION'),0)) payment_exceeds_availability,
      (p.budgeted_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='PRESUPUESTO'),0))-p.total_paid pending_balance,
      case when (p.budgeted_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='PRESUPUESTO'),0))>0
        then round(p.total_paid*100/(p.budgeted_amount+coalesce((select sum(m.amount) from public.project_budget_modifications m where m.project_id=p.id and m.modification_type='PRESUPUESTO'),0)),2) else 0 end financial_progress,
      coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'type',m.modification_type,'amount',m.amount,'description',m.description,'reference',m.reference,'created_at',m.created_at,'user_name',u.full_name) order by m.created_at desc)
        from public.project_budget_modifications m join public.app_users u on u.id=m.created_by where m.project_id=p.id),'[]'::jsonb) modifications
    from public.technical_projects p where p_year is null or p.project_year=p_year
  )x;
  return jsonb_build_object('success',true,'year_closed',v_closed,'projects',v_items);
end $$;

create or replace function public.set_project_fixed_asset_payment(p_token text,p_project_id uuid,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_year integer;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_proyectos_tecnicos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para registrar pagos del proyecto.'); end if;
  select project_year into v_year from public.technical_projects where id=p_project_id;
  if exists(select 1 from public.budget_year_closures where budget_year=v_year) then return jsonb_build_object('success',false,'error','El año presupuestario está cerrado.'); end if;
  update public.technical_projects set fixed_asset_paid_amount=greatest(coalesce(p_amount,0),0),updated_at=now() where id=p_project_id;
  if not found then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  perform public.recalculate_project_financials(p_project_id);
  return jsonb_build_object('success',true);
end $$;

create or replace function public.set_project_financial_commitments(p_token text,p_project_id uuid,p_committed numeric,p_advance numeric)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_year integer; v_supplier text; v_awarded numeric;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'editar_proyectos_tecnicos')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para actualizar los compromisos financieros.'); end if;
  select project_year,supplier_contractor,awarded_amount into v_year,v_supplier,v_awarded from public.technical_projects where id=p_project_id;
  if exists(select 1 from public.budget_year_closures where budget_year=v_year) then return jsonb_build_object('success',false,'error','El año presupuestario está cerrado.'); end if;
  if coalesce(p_advance,0)>0 and (coalesce(trim(v_supplier),'')='' or coalesce(v_awarded,0)<=0)
    then return jsonb_build_object('success',false,'error','Debe asignar un proveedor y un monto adjudicado antes de pagar el avance inicial.'); end if;
  if coalesce(p_advance,0)>coalesce(v_awarded,0)
    then return jsonb_build_object('success',false,'error','El avance inicial no puede superar el monto adjudicado.'); end if;
  update public.technical_projects set committed_amount=greatest(coalesce(p_committed,0),0),
    advance_20_amount=greatest(coalesce(p_advance,0),0),updated_at=now() where id=p_project_id;
  if not found then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  perform public.recalculate_project_financials(p_project_id);
  return jsonb_build_object('success',true);
end $$;

create or replace function public.add_budget_modification(p_token text,p_project_id uuid,p_type text,p_amount numeric,p_description text,p_reference text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_year integer; v_id uuid;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'modificar_presupuesto')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para modificar el presupuesto.'); end if;
  select project_year into v_year from public.technical_projects where id=p_project_id;
  if v_year is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.'); end if;
  if exists(select 1 from public.budget_year_closures where budget_year=v_year) then return jsonb_build_object('success',false,'error','El año presupuestario está cerrado.'); end if;
  if p_type not in ('PRESUPUESTO','APROPIACION') or p_amount=0 or length(trim(p_description))<5
    then return jsonb_build_object('success',false,'error','Datos de modificación incompletos.'); end if;
  insert into public.project_budget_modifications(project_id,modification_type,amount,description,reference,created_by)
  values(p_project_id,p_type,p_amount,trim(p_description),coalesce(trim(p_reference),''),v_user.id) returning id into v_id;
  insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'BUDGET_MODIFICATION','Presupuesto',
    jsonb_build_object('project_id',p_project_id,'type',p_type,'amount',p_amount,'description',p_description,'reference',p_reference));
  return jsonb_build_object('success',true,'id',v_id);
end $$;

create or replace function public.close_budget_year(p_token text,p_year integer,p_notes text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype;
begin
  select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.suspended_at is null;
  if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'cerrar_presupuesto')::boolean,false)=false)
    then return jsonb_build_object('success',false,'error','No posee permiso para cerrar el año presupuestario.'); end if;
  insert into public.budget_year_closures(budget_year,notes,closed_by) values(p_year,coalesce(trim(p_notes),''),v_user.id)
  on conflict(budget_year) do nothing;
  if not found then return jsonb_build_object('success',false,'error','El año ya se encuentra cerrado.'); end if;
  update public.technical_projects set budget_closed_at=now(),budget_closed_by=v_user.id where project_year=p_year;
  insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'BUDGET_YEAR_CLOSED','Presupuesto',jsonb_build_object('year',p_year,'notes',p_notes));
  return jsonb_build_object('success',true);
end $$;

do $$ declare r record; begin for r in select id from public.technical_projects loop perform public.recalculate_project_financials(r.id); end loop; end $$;

grant execute on function public.get_budget_management(text,integer),public.add_budget_modification(text,uuid,text,numeric,text,text),
  public.close_budget_year(text,integer,text),public.set_project_fixed_asset_payment(text,uuid,numeric) to anon,authenticated;
grant execute on function public.set_project_financial_commitments(text,uuid,numeric,numeric) to anon,authenticated;
