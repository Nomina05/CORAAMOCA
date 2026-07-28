-- Lotes de impresión para acciones de personal individuales ya registradas.
create table if not exists public.hr_personnel_action_batches(
 id uuid primary key default gen_random_uuid(),
 batch_number bigint generated always as identity,
 period_year integer not null check(period_year between 2020 and 2100),
 period_month integer not null check(period_month between 1 and 12),
 category text not null check(category in ('INGRESOS','SALIDAS','MOVIMIENTOS','LICENCIAS','OTRAS')),
 item_count integer not null default 0,
 status text not null default 'GENERADO' check(status in ('GENERADO','IMPRESO','ANULADO')),
 created_by uuid not null references public.app_users(id),
 created_at timestamptz not null default now(),
 printed_at timestamptz not null default now()
);
create table if not exists public.hr_personnel_action_batch_items(
 batch_id uuid not null references public.hr_personnel_action_batches(id) on delete cascade,
 action_id uuid not null references public.hr_personnel_actions(id),
 position integer not null,
 action_snapshot jsonb not null,
 primary key(batch_id,action_id),
 unique(batch_id,position)
);
create index if not exists hr_personnel_action_batches_period_idx on public.hr_personnel_action_batches(period_year,period_month,category,created_at desc);
alter table public.hr_personnel_action_batches enable row level security;
alter table public.hr_personnel_action_batch_items enable row level security;
revoke all on public.hr_personnel_action_batches,public.hr_personnel_action_batch_items from anon,authenticated;

create or replace function public.list_hr_personnel_action_batches(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para consultar lotes de acciones de personal.');
 end if;
 return jsonb_build_object('success',true,'items',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc) from (select * from public.hr_personnel_action_batches where status<>'ANULADO' limit 50)b),'[]'::jsonb));
end $$;

create or replace function public.create_hr_personnel_action_batch(p_token text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_batch_id uuid;v_batch_number bigint;v_year integer;v_month integer;v_category text;v_ids uuid[];v_expected text[];v_count integer;begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'editar_recursos_humanos')::boolean,false)) then
  return jsonb_build_object('success',false,'error','No posee permiso para generar lotes de acciones de personal.');
 end if;
 v_year:=(p_data->>'period_year')::integer;v_month:=(p_data->>'period_month')::integer;v_category:=p_data->>'category';
 select coalesce(array_agg(value::uuid),'{}'::uuid[]) into v_ids from jsonb_array_elements_text(coalesce(p_data->'action_ids','[]'::jsonb));
 if cardinality(v_ids)=0 then return jsonb_build_object('success',false,'error','Seleccione al menos una acción de personal.');end if;
 v_expected:=case v_category when 'INGRESOS' then array['NOMBRAMIENTO_REGULAR','NOMBRAMIENTO_CONTRATO','REINGRESO_TRABAJO'] when 'SALIDAS' then array['DESPIDO','RENUNCIA','ABANDONO_TRABAJO','RESCISION_CONTRATO'] when 'MOVIMIENTOS' then array['AUMENTO_SUELDO','ASCENSO','INTERINAJE','TRASLADO','PRORROGA_CONTRATO','COMPENSACION'] when 'LICENCIAS' then array['VACACIONES','LICENCIA_ESTUDIOS','LICENCIA_SIN_SUELDO','LICENCIA_ENFERMEDAD','LICENCIA_EMBARAZO'] when 'OTRAS' then array['APERTURA_CONCURSO','OTROS'] else null end;
 if v_expected is null then return jsonb_build_object('success',false,'error','Categoría de lote inválida.');end if;
 select count(*) into v_count from public.hr_personnel_actions a where a.id=any(v_ids) and extract(year from a.effective_date)=v_year and extract(month from a.effective_date)=v_month and a.action_type=any(v_expected);
 if v_count<>cardinality(v_ids) then return jsonb_build_object('success',false,'error','Una o más acciones no corresponden al período o grupo seleccionado.');end if;
 insert into public.hr_personnel_action_batches(period_year,period_month,category,item_count,created_by) values(v_year,v_month,v_category,v_count,v_user.id) returning id,batch_number into v_batch_id,v_batch_number;
 insert into public.hr_personnel_action_batch_items(batch_id,action_id,position,action_snapshot)
 select v_batch_id,a.id,row_number() over(order by a.effective_date,a.action_number)::integer,to_jsonb(a)||jsonb_build_object('employee_code',e.employee_code,'document_number',e.document_number,'full_name',e.full_name)
 from public.hr_personnel_actions a join public.hr_employees e on e.id=a.employee_id where a.id=any(v_ids);
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,'GENERAR_LOTE_ACCIONES_PERSONAL','Recursos Humanos',jsonb_build_object('batch_id',v_batch_id,'batch_number',v_batch_number,'period_year',v_year,'period_month',v_month,'category',v_category,'action_ids',to_jsonb(v_ids)));
 return jsonb_build_object('success',true,'id',v_batch_id,'batch_number',v_batch_number,'item_count',v_count);
end $$;

grant execute on function public.list_hr_personnel_action_batches(text),public.create_hr_personnel_action_batch(text,jsonb) to anon,authenticated;
