-- Catálogo territorial institucional de la provincia Espaillat.
-- Fuente base: ONE, División Territorial 2021. Provincia 09.
create table if not exists public.espaillat_territorial_catalog(
 id uuid primary key default gen_random_uuid(),
 level text not null check(level in('MUNICIPIO','DISTRITO','SECTOR')),
 code text not null,
 name text not null,
 municipality text not null,
 district text not null default '',
 active boolean not null default true,
 source text not null default 'ONE - División Territorial 2021',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(level,code),unique(level,municipality,district,name)
);
alter table public.espaillat_territorial_catalog enable row level security;
revoke all on public.espaillat_territorial_catalog from anon,authenticated;

insert into public.espaillat_territorial_catalog(level,code,name,municipality,district) values
('MUNICIPIO','09-01','Moca','Moca',''),('MUNICIPIO','09-02','Cayetano Germosén','Cayetano Germosén',''),
('MUNICIPIO','09-03','Gaspar Hernández','Gaspar Hernández',''),('MUNICIPIO','09-04','Jamao al Norte','Jamao al Norte',''),
('MUNICIPIO','09-05','San Víctor','San Víctor',''),
('DISTRITO','09-01-01','Moca','Moca','Moca'),('DISTRITO','09-01-02','José Contreras','Moca','José Contreras'),
('DISTRITO','09-01-03','Juan López','Moca','Juan López'),('DISTRITO','09-01-04','San Víctor','Moca','San Víctor'),
('DISTRITO','09-01-05','Las Lagunas','Moca','Las Lagunas'),('DISTRITO','09-01-06','Canca La Reyna','Moca','Canca La Reyna'),
('DISTRITO','09-01-07','El Higüerito','Moca','El Higüerito'),('DISTRITO','09-01-08','Monte de La Jagua','Moca','Monte de La Jagua'),
('DISTRITO','09-01-09','La Ortega','Moca','La Ortega'),
('DISTRITO','09-02-01','Cayetano Germosén','Cayetano Germosén','Cayetano Germosén'),
('DISTRITO','09-03-01','Gaspar Hernández','Gaspar Hernández','Gaspar Hernández'),('DISTRITO','09-03-02','Joba Arriba','Gaspar Hernández','Joba Arriba'),
('DISTRITO','09-03-03','Veragua','Gaspar Hernández','Veragua'),('DISTRITO','09-03-04','Villa Magante','Gaspar Hernández','Villa Magante'),
('DISTRITO','09-04-01','Jamao al Norte','Jamao al Norte','Jamao al Norte'),
('DISTRITO','09-05-01','San Víctor','San Víctor','San Víctor')
on conflict do nothing;

-- Conserva todos los sectores utilizados por las áreas institucionales.
insert into public.espaillat_territorial_catalog(level,code,name,municipality,district,source)
select 'SECTOR','TP-'||substr(md5(lower(trim(p.municipality))||'|'||lower(trim(coalesce(p.district,'')))||'|'||lower(trim(p.sector))),1,20),trim(p.sector),trim(p.municipality),trim(coalesce(p.district,'')),'Proyectos institucionales'
from public.technical_projects p where trim(coalesce(p.municipality,''))<>'' and trim(coalesce(p.sector,''))<>'' on conflict do nothing;
insert into public.espaillat_territorial_catalog(level,code,name,municipality,district,source)
select 'SECTOR','CO-'||substr(md5(lower(trim(c.municipality))||'|'||lower(trim(c.district))||'|'||lower(trim(c.sector))),1,20),trim(c.sector),trim(c.municipality),trim(c.district),'Catastro comercial'
from public.commercial_customers c where trim(c.municipality)<>'' and trim(c.sector)<>'' on conflict do nothing;

create or replace function public.list_espaillat_territory(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null then return jsonb_build_object('success',false,'error','Sesión inválida.');end if;
 return jsonb_build_object('success',true,
  'municipalities',(select coalesce(jsonb_agg(to_jsonb(t) order by name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='MUNICIPIO' and active),
  'districts',(select coalesce(jsonb_agg(to_jsonb(t) order by municipality,name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='DISTRITO' and active),
  'sectors',(select coalesce(jsonb_agg(to_jsonb(t) order by municipality,district,name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='SECTOR' and active));
end$$;
grant execute on function public.list_espaillat_territory(text) to anon,authenticated;

-- Los formularios técnicos, de planificación y financieros reciben el mismo catálogo.
create or replace function public.list_project_catalogs(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare u public.app_users;result jsonb;
begin
 u:=public.hr_authenticated_user(p_token);if u.id is null then return jsonb_build_object('success',false,'error','Sesión inválida.');end if;
 select jsonb_build_object(
  'suppliers',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='supplier'),'[]'::jsonb),
  'accounts',coalesce(jsonb_agg(to_jsonb(c) order by c.code) filter(where catalog_type='account'),'[]'::jsonb),
  'processes',coalesce(jsonb_agg(to_jsonb(c) order by c.code) filter(where catalog_type='process'),'[]'::jsonb),
  'municipalities',(select coalesce(jsonb_agg(to_jsonb(t) order by name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='MUNICIPIO' and active),
  'districts',(select coalesce(jsonb_agg(to_jsonb(t) order by municipality,name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='DISTRITO' and active),
  'sectors',(select coalesce(jsonb_agg(to_jsonb(t) order by municipality,district,name),'[]'::jsonb) from public.espaillat_territorial_catalog t where level='SECTOR' and active),
  'fundingSources',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='funding_source'),'[]'::jsonb),
  'workTypes',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='work_type'),'[]'::jsonb),
  'workStatuses',coalesce(jsonb_agg(to_jsonb(c) order by c.name) filter(where catalog_type='work_status'),'[]'::jsonb)
 ) into result from public.administrative_catalogs c;
 return jsonb_build_object('success',true,'catalogs',result);
end$$;
grant execute on function public.list_project_catalogs(text) to anon,authenticated;
