begin;

create table if not exists public.commercial_customer_categories(
 id bigint generated always as identity primary key,
 code text not null unique,
 name text not null unique,
 description text not null default '',
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

insert into public.commercial_customer_categories(code,name,description) values
 ('RES','Residencial','Usuarios de viviendas y residencias'),
 ('COM','Comercial','Negocios y establecimientos comerciales'),
 ('IND','Industrial','Industrias y grandes consumidores'),
 ('OFI','Oficial','Instituciones públicas'),
 ('SFL','Sin fines de lucro','Organizaciones sin fines de lucro')
on conflict(code) do update set name=excluded.name,description=excluded.description,active=true,updated_at=now();

create index if not exists commercial_customers_category_idx on public.commercial_customers(customer_category,status);
create index if not exists commercial_invoices_overdue_idx on public.commercial_invoices(customer_id,due_date,status);

create or replace view public.commercial_overdue_customer_alerts as
select c.id customer_id,c.account_code,c.full_name,c.customer_category,
 count(i.id)::integer overdue_invoice_count,
 sum(greatest(i.amount-coalesce(p.paid_amount,0),0)) overdue_balance,
 min(i.due_date) oldest_due_date
from public.commercial_customers c
join public.commercial_invoices i on i.customer_id=c.id
left join lateral(select coalesce(sum(cp.amount),0) paid_amount from public.commercial_payments cp where cp.invoice_id=i.id)p on true
where i.status not in('Pagada','Anulada') and (i.status='Vencida' or i.due_date<current_date)
group by c.id,c.account_code,c.full_name,c.customer_category
having count(i.id)>2;

comment on view public.commercial_overdue_customer_alerts is 'Alerta clientes desde la tercera factura vencida (más de dos).';
revoke all on public.commercial_customer_categories,public.commercial_overdue_customer_alerts from anon,authenticated;

commit;
