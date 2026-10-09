-- Activos financieros con flujo controlado e impacto presupuestario exclusivo al pago.
alter table public.technical_projects add column if not exists paid_assets_amount numeric(18,2) not null default 0;

create table if not exists public.financial_assets(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references public.technical_projects(id),
 asset_number integer not null,
 code text not null unique,
 asset_type text not null,
 supplier text not null default '',
 amount numeric(18,2) not null check(amount>0),
 description text not null default '',
 status text not null default 'Registrado' check(status in ('Registrado','Revisado','Libramiento','Pagado')),
 registered_by uuid not null references public.app_users(id),
 reviewed_by uuid references public.app_users(id), reviewed_at timestamptz,
 released_by uuid references public.app_users(id), released_at timestamptz,
 paid_by uuid references public.app_users(id), paid_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(project_id,asset_number)
);
create table if not exists public.financial_asset_audit(
 id bigint generated always as identity primary key,
 asset_id uuid not null references public.financial_assets(id) on delete cascade,
 action text not null, from_status text, to_status text not null,
 user_id uuid not null references public.app_users(id), comments text not null default '',
 amount numeric(18,2) not null, created_at timestamptz not null default now()
);
create index if not exists financial_assets_project_idx on public.financial_assets(project_id,created_at desc);
create sequence if not exists public.financial_assets_code_seq;
alter table public.financial_assets enable row level security;
alter table public.financial_asset_audit enable row level security;
revoke all on public.financial_assets,public.financial_asset_audit from anon,authenticated;

create or replace function public.recalculate_project_financials(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_paid numeric;v_measured numeric;v_paid_progress numeric;v_assets numeric;
begin
 select coalesce(sum(net_paid_amount),0) into v_paid from public.project_measurements where project_id=p_project_id and lower(trim(status)) in ('pagada','pago');
 select coalesce(sum(amount),0) into v_measured from public.project_measurements where project_id=p_project_id;
 select coalesce(sum(progress_increment),0) into v_paid_progress from public.project_measurements where project_id=p_project_id and lower(trim(status)) in ('pagada','pago');
 select coalesce(sum(amount),0) into v_assets from public.financial_assets where project_id=p_project_id and lower(trim(status)) in ('pagado','pago');
 update public.technical_projects set paid_measurements_amount=v_paid,paid_assets_amount=v_assets,total_measured=v_measured,
  total_paid=case when lower(trim(coalesce(fixed_asset_status,''))) in ('pagada','pago') then coalesce(fixed_asset_paid_amount,0) else 0 end
   +case when lower(trim(coalesce(advance_status,''))) in ('pagada','pago') then coalesce(advance_20_amount,0) else 0 end+v_paid+v_assets,
  work_progress=least(100,case when lower(trim(coalesce(advance_status,''))) in ('pagada','pago') and coalesce(awarded_amount,0)>0 then round(coalesce(advance_20_amount,0)*100/awarded_amount,2) else 0 end+v_paid_progress),updated_at=now()
 where id=p_project_id;
end $$;

create or replace function public.sync_financial_asset_totals()
returns trigger language plpgsql security definer set search_path=public,extensions as $$
begin perform public.recalculate_project_financials(coalesce(new.project_id,old.project_id));return coalesce(new,old);end $$;
drop trigger if exists trg_sync_financial_asset_totals on public.financial_assets;
create trigger trg_sync_financial_asset_totals after insert or update or delete on public.financial_assets for each row execute function public.sync_financial_asset_totals();

create or replace function public.list_financial_assets(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_items jsonb;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_activos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar activos.');end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from(
  select a.*,p.work_name,p.snip_code,p.municipality,p.district,p.sector,u.full_name registered_by_name,
   coalesce((select jsonb_agg(jsonb_build_object('action',h.action,'from_status',h.from_status,'to_status',h.to_status,'comments',h.comments,'amount',h.amount,'created_at',h.created_at,'user_name',hu.full_name) order by h.created_at) from public.financial_asset_audit h join public.app_users hu on hu.id=h.user_id where h.asset_id=a.id),'[]'::jsonb) audit
  from public.financial_assets a join public.technical_projects p on p.id=a.project_id join public.app_users u on u.id=a.registered_by)x;
 return jsonb_build_object('success',true,'assets',v_items);
end $$;

create or replace function public.create_financial_asset(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_project public.technical_projects;v_number integer;v_id uuid;v_code text;v_amount numeric;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'registrar_activos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para registrar activos.');end if;
 select * into v_project from public.technical_projects where id=(p_data->>'project_id')::uuid;
 if v_project.id is null then return jsonb_build_object('success',false,'error','Proyecto no encontrado.');end if;
 if nullif(trim(coalesce(v_project.fixed_assets,'')),'') is null then return jsonb_build_object('success',false,'error','El proyecto seleccionado no corresponde a activos fijos.');end if;
 v_amount:=coalesce((p_data->>'amount')::numeric,0);if v_amount<=0 then return jsonb_build_object('success',false,'error','El monto debe ser mayor que cero.');end if;
 perform pg_advisory_xact_lock(hashtext(v_project.id::text));select coalesce(max(asset_number),0)+1 into v_number from public.financial_assets where project_id=v_project.id;
 v_code:='ACT-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.financial_assets_code_seq')::text,6,'0');
 insert into public.financial_assets(project_id,asset_number,code,asset_type,supplier,amount,description,registered_by)
 values(v_project.id,v_number,v_code,trim(p_data->>'asset_type'),coalesce(p_data->>'supplier',''),v_amount,coalesce(p_data->>'description',''),v_user.id) returning id into v_id;
 insert into public.financial_asset_audit(asset_id,action,from_status,to_status,user_id,comments,amount) values(v_id,'Registro',null,'Registrado',v_user.id,coalesce(p_data->>'description',''),v_amount);
 return jsonb_build_object('success',true,'id',v_id,'code',v_code,'status','Registrado');
end $$;

create or replace function public.transition_financial_asset(p_token text,p_asset_id uuid,p_action text,p_comments text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_asset public.financial_assets;v_target text;v_permission text;begin
 v_user:=public.hr_authenticated_user(p_token);if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 select * into v_asset from public.financial_assets where id=p_asset_id for update;if v_asset.id is null then return jsonb_build_object('success',false,'error','Activo no encontrado.');end if;
 if v_asset.status='Pagado' then return jsonb_build_object('success',false,'error','Un activo pagado no puede cambiar de estado.');end if;
 if p_action='RETURN' then
  if length(trim(coalesce(p_comments,'')))<5 then return jsonb_build_object('success',false,'error','La devolución requiere una observación.');end if;
  v_target:=case v_asset.status when 'Revisado' then 'Registrado' when 'Libramiento' then 'Revisado' end;
  v_permission:=case v_asset.status when 'Revisado' then 'revisar_activos' when 'Libramiento' then 'libramiento_activos' end;
 else
  v_target:=case v_asset.status when 'Registrado' then 'Revisado' when 'Revisado' then 'Libramiento' when 'Libramiento' then 'Pagado' end;
  v_permission:=case v_target when 'Revisado' then 'revisar_activos' when 'Libramiento' then 'libramiento_activos' when 'Pagado' then 'pagar_activos' end;
 end if;
 if v_target is null then return jsonb_build_object('success',false,'error','Transición no permitida.');end if;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para esta etapa.');end if;
 update public.financial_assets set status=v_target,reviewed_by=case when v_target='Revisado' then v_user.id else reviewed_by end,reviewed_at=case when v_target='Revisado' then now() else reviewed_at end,released_by=case when v_target='Libramiento' then v_user.id else released_by end,released_at=case when v_target='Libramiento' then now() else released_at end,paid_by=case when v_target='Pagado' then v_user.id else paid_by end,paid_at=case when v_target='Pagado' then now() else paid_at end,updated_at=now() where id=v_asset.id;
 insert into public.financial_asset_audit(asset_id,action,from_status,to_status,user_id,comments,amount) values(v_asset.id,case when p_action='RETURN' then 'Devolución' else 'Cambio de estatus' end,v_asset.status,v_target,v_user.id,coalesce(p_comments,''),v_asset.amount);
 return jsonb_build_object('success',true,'id',v_asset.id,'project_id',v_asset.project_id,'previous_status',v_asset.status,'status',v_target);
end $$;

do $$ declare r record;begin for r in select id from public.technical_projects loop perform public.recalculate_project_financials(r.id);end loop;end $$;
grant execute on function public.list_financial_assets(text),public.create_financial_asset(text,jsonb),public.transition_financial_asset(text,uuid,text,text) to anon,authenticated;
