-- Canalización de averías desde Comercial hacia Dirección Técnica.
alter table public.commercial_faults
  add column if not exists technical_status text not null default 'Reportada',
  add column if not exists technical_comment text not null default '',
  add column if not exists technical_assigned_to uuid references public.app_users(id),
  add column if not exists technical_updated_at timestamptz;

update public.commercial_faults
set technical_status=case when status='RESUELTA' then 'Atendida' else 'Reportada' end
where technical_status='Reportada';

create table if not exists public.technical_fault_history(
  id uuid primary key default gen_random_uuid(),
  fault_id uuid not null references public.commercial_faults(id) on delete cascade,
  previous_status text not null,
  new_status text not null,
  comment text not null default '',
  responsible_user_id uuid not null references public.app_users(id),
  created_at timestamptz not null default now()
);
alter table public.technical_fault_history enable row level security;
revoke all on public.technical_fault_history from anon,authenticated;

create or replace function public.list_technical_faults(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;result jsonb;
begin
 u:=public.hr_authenticated_user(p_token);
 if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'ver_proyectos_tecnicos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar las averías reportadas.');
 end if;
 select jsonb_build_object('success',true,'faults',coalesce(jsonb_agg(to_jsonb(x) order by x.reported_at desc),'[]'::jsonb)) into result
 from(
  select f.id,f.fault_code,f.fault_type,f.description,f.zone,f.latitude,f.longitude,f.priority,
   f.affected_customers,f.reported_at,f.resolved_at,f.technical_status,f.technical_comment,
   f.technical_assigned_to,f.technical_updated_at,c.full_name customer_name,c.account_code,
   c.phone,c.address,c.municipality,c.district,c.sector,
   coalesce(a.full_name,'Sin asignar') responsible_name,
   coalesce((select jsonb_agg(to_jsonb(hx) order by hx.created_at desc) from(
    select h.id,h.previous_status,h.new_status,h.comment,h.created_at,au.full_name responsible_name
    from public.technical_fault_history h join public.app_users au on au.id=h.responsible_user_id
    where h.fault_id=f.id
   )hx),'[]'::jsonb) history
  from public.commercial_faults f
  left join public.commercial_customers c on c.id=f.customer_id
  left join public.app_users a on a.id=f.technical_assigned_to
 )x;
 return result;
end$$;

create or replace function public.manage_technical_fault(p_token text,p_fault_ids uuid[],p_status text,p_comment text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;fid uuid;old_status text;clean_status text:=trim(coalesce(p_status,''));affected integer:=0;
begin
 u:=public.hr_authenticated_user(p_token);
 if u.id is null or (u.role<>'Administrador' and not coalesce((u.permissions->>'editar_proyectos_tecnicos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para actualizar averías técnicas.');
 end if;
 if clean_status not in('Atendida','En proceso','En espera de materiales') then
  return jsonb_build_object('success',false,'error','Seleccione un estado técnico válido.');
 end if;
 if coalesce(array_length(p_fault_ids,1),0)=0 then return jsonb_build_object('success',false,'error','Seleccione al menos una avería.');end if;
 foreach fid in array p_fault_ids loop
  select technical_status into old_status from public.commercial_faults where id=fid for update;
  if old_status is null then continue;end if;
  update public.commercial_faults set technical_status=clean_status,technical_comment=trim(coalesce(p_comment,'')),
   technical_assigned_to=u.id,technical_updated_at=now(),status=case when clean_status='Atendida' then 'RESUELTA' else 'EN_PROCESO' end,
   resolved_at=case when clean_status='Atendida' then now() else null end where id=fid;
  update public.commercial_service_requests set status=case when clean_status='Atendida' then 'Resuelta' else clean_status end,
   resolved_at=case when clean_status='Atendida' then now() else null end,updated_at=now()
  where id=(select service_request_id from public.commercial_faults where id=fid);
  insert into public.technical_fault_history(fault_id,previous_status,new_status,comment,responsible_user_id)
  values(fid,old_status,clean_status,trim(coalesce(p_comment,'')),u.id);
  affected:=affected+1;
 end loop;
 return jsonb_build_object('success',true,'updated',affected);
end$$;

grant execute on function public.list_technical_faults(text),public.manage_technical_fault(text,uuid[],text,text) to anon,authenticated;
