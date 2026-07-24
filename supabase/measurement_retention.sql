-- Retención contractual del 25 % aplicada al pagar cubicaciones.
alter table public.project_measurements
  add column if not exists retention_rate numeric(5,2) not null default 25.00,
  add column if not exists retention_amount numeric(18,2) not null default 0,
  add column if not exists net_paid_amount numeric(18,2) not null default 0;

update public.project_measurements set retention_rate=25.00,
  retention_amount=case when lower(trim(status)) in ('pagada','pago') then round(amount*0.25,2) else 0 end,
  net_paid_amount=case when lower(trim(status)) in ('pagada','pago') then amount-round(amount*0.25,2) else 0 end;

create or replace function public.calculate_measurement_retention()
returns trigger language plpgsql set search_path=public,extensions as $$
begin
  new.retention_rate:=25.00;
  if lower(trim(new.status)) in ('pagada','pago') then
    new.retention_amount:=round(new.amount*0.25,2);
    new.net_paid_amount:=new.amount-new.retention_amount;
  else
    new.retention_amount:=0; new.net_paid_amount:=0;
  end if;
  return new;
end $$;
drop trigger if exists trg_calculate_measurement_retention on public.project_measurements;
create trigger trg_calculate_measurement_retention before insert or update of amount,status on public.project_measurements
for each row execute function public.calculate_measurement_retention();

create or replace function public.recalculate_project_financials(p_project_id uuid)
returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_paid numeric; v_measured numeric; v_paid_progress numeric;
begin
  select coalesce(sum(net_paid_amount),0) into v_paid from public.project_measurements where project_id=p_project_id and lower(trim(status)) in ('pagada','pago');
  select coalesce(sum(amount),0) into v_measured from public.project_measurements where project_id=p_project_id;
  select coalesce(sum(progress_increment),0) into v_paid_progress from public.project_measurements where project_id=p_project_id and lower(trim(status)) in ('pagada','pago');
  update public.technical_projects set paid_measurements_amount=v_paid,
    total_measured=v_measured,total_paid=case when lower(trim(coalesce(fixed_asset_status,''))) in ('pagada','pago') then coalesce(fixed_asset_paid_amount,0) else 0 end+case when lower(trim(coalesce(advance_status,''))) in ('pagada','pago') then coalesce(advance_20_amount,0) else 0 end+v_paid,
    work_progress=least(100,case when lower(trim(coalesce(advance_status,''))) in ('pagada','pago') and coalesce(awarded_amount,0)>0 then round(coalesce(advance_20_amount,0)*100/awarded_amount,2) else 0 end+v_paid_progress),updated_at=now()
  where id=p_project_id;
end $$;

do $$ declare r record; begin for r in select id from public.technical_projects loop perform public.recalculate_project_financials(r.id); end loop; end $$;
