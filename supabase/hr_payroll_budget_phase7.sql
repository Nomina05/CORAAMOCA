-- Fase 7: cierre presupuestario mensual y bloqueo de operaciones de nómina.
create table if not exists public.hr_payroll_budget_periods(
 id uuid primary key default gen_random_uuid(),
 budget_year integer not null check(budget_year between 2000 and 2200),
 budget_month integer not null check(budget_month between 1 and 12),
 status text not null default 'ABIERTO' check(status in('ABIERTO','CERRADO')),
 closed_at timestamptz,closed_by uuid references public.app_users(id),close_reason text,
 reopened_at timestamptz,reopened_by uuid references public.app_users(id),reopen_reason text,
 updated_at timestamptz not null default now(),unique(budget_year,budget_month)
);
alter table public.hr_payroll_budget_periods enable row level security;
revoke all on public.hr_payroll_budget_periods from anon,authenticated;

create or replace function public.get_hr_payroll_budget_period(p_token text,p_year integer,p_month integer)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_period public.hr_payroll_budget_periods;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar el período presupuestario.');end if;
 select * into v_period from public.hr_payroll_budget_periods where budget_year=p_year and budget_month=p_month;
 return jsonb_build_object('success',true,'period',jsonb_build_object('year',p_year,'month',p_month,'status',coalesce(v_period.status,'ABIERTO'),'closed_at',v_period.closed_at,'close_reason',v_period.close_reason,'reopened_at',v_period.reopened_at,'reopen_reason',v_period.reopen_reason));
end $$;

create or replace function public.set_hr_payroll_budget_period_status(p_token text,p_year integer,p_month integer,p_status text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;v_status text:=upper(trim(coalesce(p_status,'')));v_previous text;
begin
 v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'cerrar_nomina')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso específico para cerrar o reabrir períodos presupuestarios.');end if;
 if p_year not between 2000 and 2200 or p_month not between 1 and 12 or v_status not in('ABIERTO','CERRADO') or length(trim(coalesce(p_reason,'')))<5 then return jsonb_build_object('success',false,'error','Indique un período válido y un motivo de al menos cinco caracteres.');end if;
 select status into v_previous from public.hr_payroll_budget_periods where budget_year=p_year and budget_month=p_month for update;v_previous:=coalesce(v_previous,'ABIERTO');
 if v_previous=v_status then return jsonb_build_object('success',false,'error','El período ya se encuentra '||lower(v_status)||'.');end if;
 if v_status='CERRADO' and exists(select 1 from public.hr_payroll_batches where payroll_year=p_year and payroll_month=p_month and status not in('CERRADA','ANULADA')) then return jsonb_build_object('success',false,'error','Existen nóminas sin cerrar o anular en este período.');end if;
 insert into public.hr_payroll_budget_periods(budget_year,budget_month,status,closed_at,closed_by,close_reason,reopened_at,reopened_by,reopen_reason)
 values(p_year,p_month,v_status,case when v_status='CERRADO' then now() end,case when v_status='CERRADO' then v_user.id end,case when v_status='CERRADO' then trim(p_reason) end,case when v_status='ABIERTO' then now() end,case when v_status='ABIERTO' then v_user.id end,case when v_status='ABIERTO' then trim(p_reason) end)
 on conflict(budget_year,budget_month) do update set status=excluded.status,closed_at=case when excluded.status='CERRADO' then now() else hr_payroll_budget_periods.closed_at end,closed_by=case when excluded.status='CERRADO' then v_user.id else hr_payroll_budget_periods.closed_by end,close_reason=case when excluded.status='CERRADO' then trim(p_reason) else hr_payroll_budget_periods.close_reason end,reopened_at=case when excluded.status='ABIERTO' then now() else hr_payroll_budget_periods.reopened_at end,reopened_by=case when excluded.status='ABIERTO' then v_user.id else hr_payroll_budget_periods.reopened_by end,reopen_reason=case when excluded.status='ABIERTO' then trim(p_reason) else hr_payroll_budget_periods.reopen_reason end,updated_at=now();
 insert into public.security_audit_log(actor_user_id,action,module,detail) values(v_user.id,case when v_status='CERRADO' then 'CERRAR_PERIODO_PRESUPUESTO_NOMINA' else 'REABRIR_PERIODO_PRESUPUESTO_NOMINA' end,'Recursos Humanos',jsonb_build_object('year',p_year,'month',p_month,'previous',v_previous,'new',v_status,'reason',trim(p_reason)));
 return jsonb_build_object('success',true,'status',v_status);
end $$;

create or replace function public.hr_protect_closed_budget_period()
returns trigger language plpgsql set search_path=public as $$begin
 if exists(select 1 from public.hr_payroll_budget_periods where budget_year=new.payroll_year and budget_month=new.payroll_month and status='CERRADO') then raise exception 'El período presupuestario de nómina %/% está cerrado.',new.payroll_month,new.payroll_year;end if;return new;
end $$;
drop trigger if exists hr_protect_closed_budget_period_trigger on public.hr_payroll_batches;
create trigger hr_protect_closed_budget_period_trigger before insert or update on public.hr_payroll_batches for each row execute function public.hr_protect_closed_budget_period();

create or replace function public.hr_protect_closed_budget_modification()
returns trigger language plpgsql set search_path=public as $$begin
 if exists(select 1 from public.hr_payroll_budget_periods where budget_year=new.budget_year and budget_month=new.effective_month and status='CERRADO') then raise exception 'No se puede modificar un período presupuestario cerrado.';end if;return new;
end $$;
drop trigger if exists hr_protect_closed_budget_modification_trigger on public.hr_payroll_budget_modifications;
create trigger hr_protect_closed_budget_modification_trigger before insert or update on public.hr_payroll_budget_modifications for each row execute function public.hr_protect_closed_budget_modification();

grant execute on function public.get_hr_payroll_budget_period(text,integer,integer),public.set_hr_payroll_budget_period_status(text,integer,integer,text,text) to anon,authenticated;
