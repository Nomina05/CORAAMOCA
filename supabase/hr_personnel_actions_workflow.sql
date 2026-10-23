-- Fase 3: flujo controlado y trazable de acciones de personal.
-- Registrada -> Revisada -> Aprobada -> Aplicada.

update public.app_users set permissions=coalesce(permissions,'{}'::jsonb)||jsonb_build_object(
 'revisar_acciones_personal',case when role='Administrador' then true else coalesce((permissions->>'revisar_acciones_personal')::boolean,(permissions->>'editar_recursos_humanos')::boolean,false) end,
 'aplicar_acciones_personal',case when role='Administrador' then true else coalesce((permissions->>'aplicar_acciones_personal')::boolean,false) end
),permissions_version=permissions_version+1,updated_at=now();

alter table public.hr_personnel_actions add column if not exists reviewed_by uuid references public.app_users(id);
alter table public.hr_personnel_actions add column if not exists reviewed_at timestamptz;
alter table public.hr_personnel_actions add column if not exists review_observation text not null default '';
alter table public.hr_personnel_actions add column if not exists applied_by uuid references public.app_users(id);
alter table public.hr_personnel_actions add column if not exists applied_at timestamptz;
alter table public.hr_personnel_actions add column if not exists return_observation text not null default '';
alter table public.hr_personnel_actions add column if not exists workflow_enabled boolean;

alter table public.hr_personnel_actions drop constraint if exists hr_personnel_actions_status_check;
update public.hr_personnel_actions set status=case status
 when 'BORRADOR' then 'REGISTRADA' when 'RECOMENDADA' then 'REVISADA'
 when 'APROBADA' then 'APLICADA' else status end where workflow_enabled is null;
update public.hr_personnel_actions set workflow_enabled=true where workflow_enabled is null;
alter table public.hr_personnel_actions alter column workflow_enabled set default true;
alter table public.hr_personnel_actions alter column workflow_enabled set not null;
alter table public.hr_personnel_actions add constraint hr_personnel_actions_status_check
 check(status in('REGISTRADA','REVISADA','APROBADA','APLICADA','DEVUELTA','ANULADA'));

create table if not exists public.hr_personnel_action_workflow_history(
 id bigint generated always as identity primary key,
 action_id uuid not null references public.hr_personnel_actions(id) on delete cascade,
 from_status text,
 to_status text not null,
 observation text not null default '',
 responsible_user_id uuid not null references public.app_users(id),
 created_at timestamptz not null default now()
);
create index if not exists hr_personnel_action_workflow_history_idx on public.hr_personnel_action_workflow_history(action_id,created_at);
alter table public.hr_personnel_action_workflow_history enable row level security;
revoke all on public.hr_personnel_action_workflow_history from anon,authenticated;

insert into public.hr_personnel_action_workflow_history(action_id,from_status,to_status,observation,responsible_user_id,created_at)
select a.id,null,a.status,'Estado incorporado durante la normalización del flujo',a.created_by,a.created_at
from public.hr_personnel_actions a where not exists(select 1 from public.hr_personnel_action_workflow_history h where h.action_id=a.id);

create or replace function public.transition_hr_personnel_action(p_token text,p_action_id uuid,p_target_status text,p_observation text default '')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_action public.hr_personnel_actions;v_employee public.hr_employees;v_permission text;v_expected text;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null then return jsonb_build_object('success',false,'error','Sesión inválida o vencida.');end if;
 select * into v_action from public.hr_personnel_actions where id=p_action_id for update;
 if v_action.id is null then return jsonb_build_object('success',false,'error','Acción de personal no encontrada.');end if;
 select * into v_employee from public.hr_employees where id=v_action.employee_id;
 if v_user.role<>'Administrador' and not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','La acción corresponde a un empleado fuera de su alcance.');end if;
 if p_target_status='DEVUELTA' then
  if v_action.status not in('REGISTRADA','REVISADA','APROBADA') then return jsonb_build_object('success',false,'error','Esta acción no puede devolverse desde su estado actual.');end if;
  if trim(coalesce(p_observation,''))='' then return jsonb_build_object('success',false,'error','La observación de devolución es obligatoria.');end if;
  v_permission:=case when v_action.status='REGISTRADA' then 'revisar_acciones_personal' else 'aprobar_acciones_personal' end;
 else
  v_expected:=case p_target_status when 'REVISADA' then 'REGISTRADA' when 'APROBADA' then 'REVISADA' when 'APLICADA' then 'APROBADA' end;
  if v_expected is null or v_action.status<>v_expected then return jsonb_build_object('success',false,'error','La transición solicitada no corresponde al siguiente paso del flujo.');end if;
  v_permission:=case p_target_status when 'REVISADA' then 'revisar_acciones_personal' when 'APROBADA' then 'aprobar_acciones_personal' when 'APLICADA' then 'aplicar_acciones_personal' end;
 end if;
 if v_user.role<>'Administrador' and not coalesce((v_user.permissions->>v_permission)::boolean,false) then return jsonb_build_object('success',false,'error','No posee permiso para ejecutar esta transición.');end if;
 if p_target_status='APLICADA' then return public.approve_hr_personnel_action(p_token,p_action_id);end if;
 update public.hr_personnel_actions set status=p_target_status,
  reviewed_by=case when p_target_status='REVISADA' then v_user.id else reviewed_by end,
  reviewed_at=case when p_target_status='REVISADA' then now() else reviewed_at end,
  review_observation=case when p_target_status='REVISADA' then coalesce(p_observation,'') else review_observation end,
  approved_by=case when p_target_status='APROBADA' then v_user.id else approved_by end,
  approved_at=case when p_target_status='APROBADA' then now() else approved_at end,
  return_observation=case when p_target_status='DEVUELTA' then trim(p_observation) else '' end,updated_at=now()
 where id=p_action_id;
 insert into public.hr_personnel_action_workflow_history(action_id,from_status,to_status,observation,responsible_user_id)
 values(p_action_id,v_action.status,p_target_status,coalesce(p_observation,''),v_user.id);
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'TRANSICION_ACCION_PERSONAL','Recursos Humanos',jsonb_build_object('action_id',p_action_id,'employee_id',v_employee.id,'from',v_action.status,'to',p_target_status,'observation',p_observation));
 return jsonb_build_object('success',true,'id',p_action_id,'status',p_target_status);
end $$;

-- Completa la trazabilidad cuando el paso final aplica los cambios al expediente.
create or replace function public.hr_audit_applied_personnel_action()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='APLICADA' and old.status='APROBADA' then
  insert into public.hr_personnel_action_workflow_history(action_id,from_status,to_status,observation,responsible_user_id)
  values(new.id,old.status,new.status,'Cambios aplicados al expediente maestro',new.applied_by);
 elsif new.status='REGISTRADA' and old.status='DEVUELTA' then
  insert into public.hr_personnel_action_workflow_history(action_id,from_status,to_status,observation,responsible_user_id)
  values(new.id,old.status,new.status,'Acción corregida y reenviada a revisión',coalesce(new.updated_by,new.created_by));
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_audit_applied_personnel_action on public.hr_personnel_actions;
create trigger trg_hr_audit_applied_personnel_action after update of status on public.hr_personnel_actions
for each row execute function public.hr_audit_applied_personnel_action();

-- La consulta incorpora historial y aplica el alcance jerárquico.
create or replace function public.list_hr_personnel_actions(p_token text,p_employee_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar acciones de personal.');end if;
 return jsonb_build_object('success',true,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
  select a.*,e.employee_code,case when v_user.role='Administrador' or coalesce((v_user.permissions->>'ver_datos_personales')::boolean,false) then e.document_number else '***'||right(e.document_number,4) end document_number,e.full_name,e.position_name,
   coalesce((select jsonb_agg(jsonb_build_object('from_status',h.from_status,'to_status',h.to_status,'observation',h.observation,'responsible_name',u.full_name,'created_at',h.created_at) order by h.created_at) from public.hr_personnel_action_workflow_history h join public.app_users u on u.id=h.responsible_user_id where h.action_id=a.id),'[]'::jsonb) workflow_history
  from public.hr_personnel_actions a join public.hr_employees e on e.id=a.employee_id
  where (p_employee_id is null or a.employee_id=p_employee_id) and public.hr_employee_in_user_scope(v_user,e)
 )x),'[]'::jsonb));
end $$;

revoke all on function public.transition_hr_personnel_action(text,uuid,text,text) from public;
grant execute on function public.transition_hr_personnel_action(text,uuid,text,text),public.list_hr_personnel_actions(text,uuid) to anon,authenticated;
