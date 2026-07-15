alter table public.app_users add column if not exists permissions jsonb not null default '{"registrar_cubicaciones":true,"revisar_cubicaciones":false,"libramiento_cubicaciones":false,"pagar_cubicaciones":false}'::jsonb;
update public.app_users set permissions='{"registrar_cubicaciones":true,"revisar_cubicaciones":true,"libramiento_cubicaciones":true,"pagar_cubicaciones":true}'::jsonb where role='Administrador';

create table if not exists public.project_measurements (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.technical_projects(id) on delete cascade,
  measurement_number integer not null, code text not null unique, amount numeric(18,2) not null check(amount>0),
  progress_increment numeric(5,2) not null default 0 check(progress_increment between 0 and 100), description text,
  status text not null default 'Registrada' check(status in ('Registrada','Revisada','Libramiento','Pagada')),
  registered_by uuid not null references public.app_users(id), reviewed_by uuid references public.app_users(id),
  reviewed_at timestamptz, released_by uuid references public.app_users(id), released_at timestamptz,
  paid_by uuid references public.app_users(id), paid_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(project_id,measurement_number)
);
create table if not exists public.measurement_audit (
  id bigserial primary key, measurement_id uuid not null references public.project_measurements(id) on delete cascade,
  action text not null, from_status text, to_status text not null, user_id uuid not null references public.app_users(id),
  comments text, amount numeric(18,2) not null, created_at timestamptz not null default now()
);
alter table public.project_measurements enable row level security;
alter table public.measurement_audit enable row level security;
revoke all on public.project_measurements, public.measurement_audit from anon, authenticated;

create or replace function public.login_app_user(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_token text;
begin select * into v_user from public.app_users where username=lower(trim(p_username)) and active=true;
if v_user.id is null or v_user.password_hash<>crypt(p_password,v_user.password_hash) then return null; end if;
delete from public.app_user_sessions where expires_at<now(); v_token:=encode(gen_random_bytes(32),'hex');
insert into public.app_user_sessions(user_id,token_hash,expires_at) values(v_user.id,encode(digest(v_token,'sha256'),'hex'),now()+interval '12 hours'); update public.app_users set last_login_at=now() where id=v_user.id;
return jsonb_build_object('token',v_token,'user',jsonb_build_object('id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'role',v_user.role,'permissions',v_user.permissions)); end $$;
create or replace function public.get_app_session(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; begin select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true;
if v_user.id is null then return null; end if; return jsonb_build_object('user',jsonb_build_object('id',v_user.id,'username',v_user.username,'full_name',v_user.full_name,'area',v_user.area,'role',v_user.role,'permissions',v_user.permissions)); end $$;
create or replace function public.admin_list_users(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users%rowtype; v_users jsonb; begin select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.role='Administrador'; if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
select coalesce(jsonb_agg(jsonb_build_object('id',id,'username',username,'full_name',full_name,'area',area,'role',role,'active',active,'permissions',permissions,'created_at',created_at,'last_login_at',last_login_at) order by created_at),'[]'::jsonb) into v_users from public.app_users; return jsonb_build_object('success',true,'users',v_users); end $$;
create or replace function public.admin_set_user_permissions(p_token text,p_user_id uuid,p_permissions jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_admin public.app_users%rowtype; begin select u.* into v_admin from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true and u.role='Administrador'; if v_admin.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
update public.app_users set permissions=jsonb_build_object('registrar_cubicaciones',coalesce((p_permissions->>'registrar_cubicaciones')::boolean,false),'revisar_cubicaciones',coalesce((p_permissions->>'revisar_cubicaciones')::boolean,false),'libramiento_cubicaciones',coalesce((p_permissions->>'libramiento_cubicaciones')::boolean,false),'pagar_cubicaciones',coalesce((p_permissions->>'pagar_cubicaciones')::boolean,false)),updated_at=now() where id=p_user_id; return jsonb_build_object('success',found); end $$;

create or replace function public.list_measurements(p_token text,p_project_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_items jsonb; begin select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true; if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if;
select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (select m.*,p.work_name,p.snip_code,p.sector,p.municipality,u.full_name registered_by_name,(select coalesce(jsonb_agg(jsonb_build_object('action',a.action,'from_status',a.from_status,'to_status',a.to_status,'comments',a.comments,'created_at',a.created_at,'user_name',au.full_name) order by a.created_at),'[]'::jsonb) from public.measurement_audit a join public.app_users au on au.id=a.user_id where a.measurement_id=m.id) audit from public.project_measurements m join public.technical_projects p on p.id=m.project_id join public.app_users u on u.id=m.registered_by where p_project_id is null or m.project_id=p_project_id) x;
return jsonb_build_object('success',true,'measurements',v_items); end $$;
create or replace function public.create_measurement(p_token text,p_project_id uuid,p_amount numeric,p_progress numeric,p_description text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_number integer; v_id uuid; v_code text; begin select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true; if v_user.id is null or (v_user.role<>'Administrador' and coalesce((v_user.permissions->>'registrar_cubicaciones')::boolean,false)=false) then return jsonb_build_object('success',false,'error','No tienes permiso para registrar cubicaciones.'); end if;
perform 1 from public.technical_projects where id=p_project_id; if not found then return jsonb_build_object('success',false,'error','Obra no encontrada.'); end if; if p_amount<=0 then return jsonb_build_object('success',false,'error','El monto debe ser mayor que cero.'); end if;
select coalesce(max(measurement_number),0)+1 into v_number from public.project_measurements where project_id=p_project_id; v_code:='CUB-'||to_char(now(),'YYYY')||'-'||substr(replace(p_project_id::text,'-',''),1,6)||'-'||lpad(v_number::text,2,'0');
insert into public.project_measurements(project_id,measurement_number,code,amount,progress_increment,description,registered_by) values(p_project_id,v_number,v_code,p_amount,coalesce(p_progress,0),p_description,v_user.id) returning id into v_id;
insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount) values(v_id,'Registro',null,'Registrada',v_user.id,p_description,p_amount); update public.technical_projects set measurement_count=measurement_count+1,measurement_status='Registrada',updated_at=now() where id=p_project_id;
return jsonb_build_object('success',true,'id',v_id,'code',v_code); end $$;
create or replace function public.transition_measurement(p_token text,p_measurement_id uuid,p_target_status text,p_comments text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users%rowtype; v_m public.project_measurements%rowtype; v_expected text; v_permission text; begin select u.* into v_user from public.app_users u join public.app_user_sessions s on s.user_id=u.id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and u.active=true; if v_user.id is null then return jsonb_build_object('success',false,'error','No autorizado.'); end if; select * into v_m from public.project_measurements where id=p_measurement_id for update; if v_m.id is null then return jsonb_build_object('success',false,'error','Cubicación no encontrada.'); end if;
v_expected:=case v_m.status when 'Registrada' then 'Revisada' when 'Revisada' then 'Libramiento' when 'Libramiento' then 'Pagada' else null end; if p_target_status is distinct from v_expected then return jsonb_build_object('success',false,'error','La transición de estatus no corresponde a la línea de mando.'); end if;
v_permission:=case p_target_status when 'Revisada' then 'revisar_cubicaciones' when 'Libramiento' then 'libramiento_cubicaciones' when 'Pagada' then 'pagar_cubicaciones' end; if v_user.role<>'Administrador' and coalesce((v_user.permissions->>v_permission)::boolean,false)=false then return jsonb_build_object('success',false,'error','No tienes permiso para este paso.'); end if;
update public.project_measurements set status=p_target_status,reviewed_by=case when p_target_status='Revisada' then v_user.id else reviewed_by end,reviewed_at=case when p_target_status='Revisada' then now() else reviewed_at end,released_by=case when p_target_status='Libramiento' then v_user.id else released_by end,released_at=case when p_target_status='Libramiento' then now() else released_at end,paid_by=case when p_target_status='Pagada' then v_user.id else paid_by end,paid_at=case when p_target_status='Pagada' then now() else paid_at end,updated_at=now() where id=v_m.id;
insert into public.measurement_audit(measurement_id,action,from_status,to_status,user_id,comments,amount) values(v_m.id,'Cambio de estatus',v_m.status,p_target_status,v_user.id,p_comments,v_m.amount);
if p_target_status='Pagada' then update public.technical_projects set total_measured=total_measured+v_m.amount,total_paid=total_paid+v_m.amount,work_progress=least(100,work_progress+v_m.progress_increment),measurement_status='Pagada',updated_at=now() where id=v_m.project_id; else update public.technical_projects set measurement_status=p_target_status,updated_at=now() where id=v_m.project_id; end if;
return jsonb_build_object('success',true); end $$;
revoke all on function public.admin_set_user_permissions(text,uuid,jsonb),public.list_measurements(text,uuid),public.create_measurement(text,uuid,numeric,numeric,text),public.transition_measurement(text,uuid,text,text) from public;
grant execute on function public.admin_set_user_permissions(text,uuid,jsonb),public.list_measurements(text,uuid),public.create_measurement(text,uuid,numeric,numeric,text),public.transition_measurement(text,uuid,text,text) to anon,authenticated;
