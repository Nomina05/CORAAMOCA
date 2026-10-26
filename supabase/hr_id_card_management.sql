-- Carnetización integrada al expediente único de Recursos Humanos.
create table if not exists public.hr_employee_id_cards(
 id uuid primary key default gen_random_uuid(),
 card_number bigint generated always as identity unique,
 employee_id uuid not null unique references public.hr_employees(id) on delete cascade,
 personnel_type text not null default 'Empleado fijo',
 issue_date date not null default current_date,
 expiry_date date not null,
 status text not null default 'Activo' check(status in('Activo','Suspendido','Anulado')),
 photo_data text not null default '',
 observation text not null default '',
 created_by uuid not null references public.app_users(id),
 updated_by uuid not null references public.app_users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(expiry_date>=issue_date)
);
create index if not exists hr_employee_id_cards_expiry_idx on public.hr_employee_id_cards(status,expiry_date);

create table if not exists public.hr_id_card_configuration(
 singleton boolean primary key default true check(singleton),
 institution_name text not null default 'Corporación del Acueducto y Alcantarillado de Moca',
 mission text not null default 'Garantizar servicios de agua potable y saneamiento con calidad, eficiencia y responsabilidad social.',
 vision text not null default 'Ser una institución referente por la excelencia, sostenibilidad e innovación en la prestación de sus servicios.',
 institutional_values text not null default 'Integridad · Responsabilidad · Transparencia · Respeto · Compromiso',
 return_note text not null default 'Este carnet es propiedad de CORAAMOCA. En caso de pérdida, favor devolverlo a la institución.',
 phone text not null default '',
 website text not null default 'www.coraamoca.gob.do',
 authority_name text not null default '',
 authority_position text not null default '',
 signature_data text not null default '',
 updated_by uuid references public.app_users(id),
 updated_at timestamptz not null default now()
);
insert into public.hr_id_card_configuration(singleton) values(true) on conflict(singleton) do nothing;

alter table public.hr_employee_id_cards enable row level security;
alter table public.hr_id_card_configuration enable row level security;
revoke all on public.hr_employee_id_cards,public.hr_id_card_configuration from anon,authenticated;

create or replace function public.list_hr_id_cards(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_items jsonb;v_config jsonb;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_carnets_rrhh')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar carnetización.');
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb) into v_items from(
  select e.id employee_id,e.employee_code,e.full_name,e.position_name,e.employment_status,
   e.direction_name,e.department_name,e.division_name,e.section_name,e.center_name,
   c.id,c.card_number,c.personnel_type,c.issue_date,c.expiry_date,c.status,c.photo_data,c.observation,c.updated_at
  from public.hr_employees e left join public.hr_employee_id_cards c on c.employee_id=e.id
  where e.employment_status<>'Desvinculado' and public.hr_employee_in_user_scope(v_user,e)
 )x;
 select to_jsonb(c) into v_config from public.hr_id_card_configuration c where singleton;
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'HR_ID_CARDS_VIEWED','Recursos Humanos',jsonb_build_object('result_count',jsonb_array_length(v_items)));
 return jsonb_build_object('success',true,'items',v_items,'configuration',coalesce(v_config,'{}'::jsonb));
end $$;

create or replace function public.save_hr_id_card(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_employee public.hr_employees;v_id uuid;v_issue date;v_expiry date;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'gestionar_carnets_rrhh')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para registrar o modificar carnets.');
 end if;
 select * into v_employee from public.hr_employees where id=(p_data->>'employee_id')::uuid;
 if v_employee.id is null or not public.hr_employee_in_user_scope(v_user,v_employee) then return jsonb_build_object('success',false,'error','Empleado no encontrado o fuera de su alcance.');end if;
 v_issue:=coalesce(nullif(p_data->>'issue_date','')::date,current_date);
 v_expiry:=nullif(p_data->>'expiry_date','')::date;
 if v_expiry is null or v_expiry<v_issue then return jsonb_build_object('success',false,'error','La fecha de vencimiento debe ser igual o posterior a la emisión.');end if;
 insert into public.hr_employee_id_cards(employee_id,personnel_type,issue_date,expiry_date,status,photo_data,observation,created_by,updated_by)
 values(v_employee.id,coalesce(nullif(trim(p_data->>'personnel_type'),''),'Empleado fijo'),v_issue,v_expiry,
  case when p_data->>'status' in('Activo','Suspendido','Anulado') then p_data->>'status' else 'Activo' end,
  coalesce(p_data->>'photo_data',''),coalesce(p_data->>'observation',''),v_user.id,v_user.id)
 on conflict(employee_id) do update set personnel_type=excluded.personnel_type,issue_date=excluded.issue_date,expiry_date=excluded.expiry_date,
  status=excluded.status,photo_data=case when excluded.photo_data='' then public.hr_employee_id_cards.photo_data else excluded.photo_data end,
  observation=excluded.observation,updated_by=v_user.id,updated_at=now()
 returning id into v_id;
 insert into public.security_audit_log(actor_user_id,action,module,detail)
 values(v_user.id,'HR_ID_CARD_SAVED','Recursos Humanos',jsonb_build_object('employee_id',v_employee.id,'card_id',v_id,'status',p_data->>'status'));
 return jsonb_build_object('success',true,'id',v_id);
end $$;

create or replace function public.save_hr_id_card_configuration(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'configurar_carnets_rrhh')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para configurar los carnets.');
 end if;
 update public.hr_id_card_configuration set
  institution_name=coalesce(nullif(trim(p_data->>'institution_name'),''),institution_name),mission=coalesce(p_data->>'mission',''),
  vision=coalesce(p_data->>'vision',''),institutional_values=coalesce(p_data->>'institutional_values',''),
  return_note=coalesce(p_data->>'return_note',''),phone=coalesce(p_data->>'phone',''),website=coalesce(p_data->>'website',''),
  authority_name=coalesce(p_data->>'authority_name',''),authority_position=coalesce(p_data->>'authority_position',''),
  signature_data=case when coalesce(p_data->>'signature_data','')='' then signature_data else p_data->>'signature_data' end,
  updated_by=v_user.id,updated_at=now() where singleton;
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'HR_ID_CARD_CONFIGURATION_UPDATED','Recursos Humanos','{}'::jsonb);
 return jsonb_build_object('success',true);
end $$;

grant execute on function public.list_hr_id_cards(text),public.save_hr_id_card(text,jsonb),public.save_hr_id_card_configuration(text,jsonb) to anon,authenticated;
