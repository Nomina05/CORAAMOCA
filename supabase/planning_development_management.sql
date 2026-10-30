-- Dirección de Planificación y Desarrollo: POA/PEI, indicadores, riesgos, calidad y cooperación.
create table if not exists public.planning_plans(
 id uuid primary key default gen_random_uuid(),code text not null unique,plan_type text not null check(plan_type in('PEI','POA','PLAN_SECTORIAL')),
 title text not null,year integer not null,organization_unit_id uuid references public.organization_units(id),responsible text not null default '',
 start_date date,end_date date,budget numeric(18,2) not null default 0,status text not null default 'BORRADOR',progress numeric(5,2) not null default 0,
 description text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.planning_goals(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.planning_plans(id) on delete cascade,code text not null,objective text not null,
 product text not null default '',activity text not null default '',responsible text not null default '',weight numeric(5,2) not null default 0,
 target numeric(18,2) not null default 0,achieved numeric(18,2) not null default 0,unit text not null default 'Porcentaje',due_date date,status text not null default 'PENDIENTE',
 evidence_url text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now(),unique(plan_id,code));
create table if not exists public.planning_indicators(
 id uuid primary key default gen_random_uuid(),goal_id uuid references public.planning_goals(id) on delete cascade,code text not null unique,name text not null,
 indicator_type text not null default 'Gestión',formula text not null default '',frequency text not null default 'Mensual',baseline numeric(18,2) not null default 0,
 target numeric(18,2) not null default 0,current_value numeric(18,2) not null default 0,unit text not null default 'Porcentaje',cutoff_date date,
 traffic_light text not null default 'SIN_MEDIR',observation text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.planning_risks(
 id uuid primary key default gen_random_uuid(),code text not null unique,process_name text not null,risk text not null,cause text not null default '',consequence text not null default '',
 probability integer not null default 1 check(probability between 1 and 5),impact integer not null default 1 check(impact between 1 and 5),
 control_description text not null default '',action_plan text not null default '',owner text not null default '',due_date date,status text not null default 'ABIERTO',
 created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.planning_quality_actions(
 id uuid primary key default gen_random_uuid(),code text not null unique,source text not null,process_name text not null,finding text not null,
 action_type text not null default 'MEJORA',action_description text not null,responsible text not null default '',due_date date,status text not null default 'REGISTRADA',
 result text not null default '',evidence_url text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.planning_cooperation(
 id uuid primary key default gen_random_uuid(),code text not null unique,partner text not null,initiative text not null,cooperation_type text not null default 'Técnica',
 amount numeric(18,2) not null default 0,currency text not null default 'DOP',start_date date,end_date date,responsible text not null default '',status text not null default 'FORMULACION',
 commitments text not null default '',created_by uuid references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());

do $$declare t text;begin foreach t in array array['planning_plans','planning_goals','planning_indicators','planning_risks','planning_quality_actions','planning_cooperation'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);end loop;end$$;

create sequence if not exists public.planning_operation_seq start 1;
create or replace function public.list_planning_development(p_token text,p_year integer default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;v_year integer:=coalesce(p_year,extract(year from current_date)::integer);result jsonb;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'ver_planificacion_institucional')::boolean,false)) then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 select jsonb_build_object('success',true,'year',v_year,
  'plans',(select coalesce(jsonb_agg(to_jsonb(x) order by code),'[]'::jsonb) from(select p.*,o.unit_name,(select count(*) from public.planning_goals g where g.plan_id=p.id) goal_count from public.planning_plans p left join public.organization_units o on o.id=p.organization_unit_id where p.year=v_year)x),
  'goals',(select coalesce(jsonb_agg(to_jsonb(x) order by plan_code,code),'[]'::jsonb) from(select g.*,p.code plan_code,p.title plan_title from public.planning_goals g join public.planning_plans p on p.id=g.plan_id where p.year=v_year)x),
  'indicators',(select coalesce(jsonb_agg(to_jsonb(x) order by code),'[]'::jsonb) from(select i.*,g.objective goal_name from public.planning_indicators i left join public.planning_goals g on g.id=i.goal_id where i.cutoff_date is null or extract(year from i.cutoff_date)=v_year)x),
  'risks',(select coalesce(jsonb_agg(to_jsonb(r) order by probability*impact desc,code),'[]'::jsonb) from public.planning_risks r),
  'quality',(select coalesce(jsonb_agg(to_jsonb(q) order by created_at desc),'[]'::jsonb) from public.planning_quality_actions q),
  'cooperation',(select coalesce(jsonb_agg(to_jsonb(c) order by created_at desc),'[]'::jsonb) from public.planning_cooperation c),
  'metrics',jsonb_build_object('plans',(select count(*) from public.planning_plans where year=v_year),'goals',(select count(*) from public.planning_goals g join public.planning_plans p on p.id=g.plan_id where p.year=v_year),'averageProgress',(select coalesce(avg(progress),0) from public.planning_plans where year=v_year),'delayedGoals',(select count(*) from public.planning_goals g join public.planning_plans p on p.id=g.plan_id where p.year=v_year and g.due_date<current_date and g.status not in('COMPLETADA','CERRADA')),'criticalRisks',(select count(*) from public.planning_risks where probability*impact>=15 and status<>'CERRADO'),'openQuality',(select count(*) from public.planning_quality_actions where status not in('CERRADA','VERIFICADA')))
 ) into result;return result;
end$$;

create or replace function public.manage_planning_development(p_token text,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;new_id uuid;code text;can_manage boolean;
begin
 u:=public.hr_authenticated_user(p_token);can_manage:=u.role='Administrador' or coalesce((u.permissions->>'gestionar_planificacion_institucional')::boolean,false);
 if u.id is null or not can_manage then return jsonb_build_object('success',false,'error','No autorizado.');end if;
 if p_action='CREATE_PLAN' then code=coalesce(nullif(p_data->>'code',''),'PLAN-'||extract(year from current_date)::int||'-'||lpad(nextval('public.planning_operation_seq')::text,4,'0'));insert into public.planning_plans(code,plan_type,title,year,organization_unit_id,responsible,start_date,end_date,budget,status,description,created_by) values(code,coalesce(p_data->>'plan_type','POA'),p_data->>'title',coalesce(nullif(p_data->>'year','')::integer,extract(year from current_date)::integer),nullif(p_data->>'organization_unit_id','')::uuid,coalesce(p_data->>'responsible',''),nullif(p_data->>'start_date','')::date,nullif(p_data->>'end_date','')::date,coalesce(nullif(p_data->>'budget','')::numeric,0),coalesce(p_data->>'status','BORRADOR'),coalesce(p_data->>'description',''),u.id) returning id into new_id;
 elsif p_action='CREATE_GOAL' then insert into public.planning_goals(plan_id,code,objective,product,activity,responsible,weight,target,unit,due_date,created_by) values((p_data->>'plan_id')::uuid,p_data->>'code',p_data->>'objective',coalesce(p_data->>'product',''),coalesce(p_data->>'activity',''),coalesce(p_data->>'responsible',''),coalesce(nullif(p_data->>'weight','')::numeric,0),coalesce(nullif(p_data->>'target','')::numeric,0),coalesce(p_data->>'unit','Porcentaje'),nullif(p_data->>'due_date','')::date,u.id) returning id into new_id;
 elsif p_action='CREATE_INDICATOR' then insert into public.planning_indicators(goal_id,code,name,indicator_type,formula,frequency,baseline,target,current_value,unit,cutoff_date,observation,created_by) values(nullif(p_data->>'goal_id','')::uuid,p_data->>'code',p_data->>'name',coalesce(p_data->>'indicator_type','Gestión'),coalesce(p_data->>'formula',''),coalesce(p_data->>'frequency','Mensual'),coalesce(nullif(p_data->>'baseline','')::numeric,0),coalesce(nullif(p_data->>'target','')::numeric,0),coalesce(nullif(p_data->>'current_value','')::numeric,0),coalesce(p_data->>'unit','Porcentaje'),nullif(p_data->>'cutoff_date','')::date,coalesce(p_data->>'observation',''),u.id) returning id into new_id;
 elsif p_action='CREATE_RISK' then code=coalesce(nullif(p_data->>'code',''),'R-'||lpad(nextval('public.planning_operation_seq')::text,5,'0'));insert into public.planning_risks(code,process_name,risk,cause,consequence,probability,impact,control_description,action_plan,owner,due_date,created_by) values(code,p_data->>'process_name',p_data->>'risk',coalesce(p_data->>'cause',''),coalesce(p_data->>'consequence',''),coalesce(nullif(p_data->>'probability','')::integer,1),coalesce(nullif(p_data->>'impact','')::integer,1),coalesce(p_data->>'control_description',''),coalesce(p_data->>'action_plan',''),coalesce(p_data->>'owner',''),nullif(p_data->>'due_date','')::date,u.id) returning id into new_id;
 elsif p_action='CREATE_QUALITY' then code='MC-'||extract(year from current_date)::int||'-'||lpad(nextval('public.planning_operation_seq')::text,4,'0');insert into public.planning_quality_actions(code,source,process_name,finding,action_type,action_description,responsible,due_date,evidence_url,created_by) values(code,p_data->>'source',p_data->>'process_name',p_data->>'finding',coalesce(p_data->>'action_type','MEJORA'),p_data->>'action_description',coalesce(p_data->>'responsible',''),nullif(p_data->>'due_date','')::date,coalesce(p_data->>'evidence_url',''),u.id) returning id into new_id;
 elsif p_action='CREATE_COOPERATION' then code='COOP-'||extract(year from current_date)::int||'-'||lpad(nextval('public.planning_operation_seq')::text,4,'0');insert into public.planning_cooperation(code,partner,initiative,cooperation_type,amount,currency,start_date,end_date,responsible,commitments,created_by) values(code,p_data->>'partner',p_data->>'initiative',coalesce(p_data->>'cooperation_type','Técnica'),coalesce(nullif(p_data->>'amount','')::numeric,0),coalesce(p_data->>'currency','DOP'),nullif(p_data->>'start_date','')::date,nullif(p_data->>'end_date','')::date,coalesce(p_data->>'responsible',''),coalesce(p_data->>'commitments',''),u.id) returning id into new_id;
 elsif p_action='UPDATE_STATUS' then
  if p_data->>'entity'='PLAN' then update public.planning_plans set status=p_data->>'status',progress=coalesce(nullif(p_data->>'progress','')::numeric,progress),updated_at=now() where id=(p_data->>'id')::uuid returning id into new_id;
  elsif p_data->>'entity'='GOAL' then update public.planning_goals set status=p_data->>'status',achieved=coalesce(nullif(p_data->>'achieved','')::numeric,achieved),evidence_url=coalesce(p_data->>'evidence_url',evidence_url) where id=(p_data->>'id')::uuid returning id into new_id;
  elsif p_data->>'entity'='RISK' then update public.planning_risks set status=p_data->>'status',updated_at=now() where id=(p_data->>'id')::uuid returning id into new_id;
  elsif p_data->>'entity'='QUALITY' then update public.planning_quality_actions set status=p_data->>'status',result=coalesce(p_data->>'result',result),updated_at=now() where id=(p_data->>'id')::uuid returning id into new_id;end if;
 else return jsonb_build_object('success',false,'error','Acción de planificación no reconocida.');end if;
 return jsonb_build_object('success',true,'id',new_id,'code',code);
exception when others then return jsonb_build_object('success',false,'error',sqlerrm);end$$;
grant execute on function public.list_planning_development(text,integer),public.manage_planning_development(text,text,jsonb) to anon,authenticated;
