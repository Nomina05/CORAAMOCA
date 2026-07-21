-- Manual institucional de cargos por grupo ocupacional y familia funcional.
create table if not exists public.hr_position_catalog(
 id uuid primary key default gen_random_uuid(), occupational_group text not null check(occupational_group in ('I','II','III','IV','V')),
 family text not null, position_name text not null, active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(occupational_group,position_name)
);
alter table public.hr_position_catalog enable row level security;
revoke all on public.hr_position_catalog from anon,authenticated;

insert into public.hr_position_catalog(occupational_group,family,position_name) values
('I','Servicios Generales','Conserje'),('I','Servicios Generales','Parqueador'),('I','Servicios Generales','Fotocopiador'),
('I','Servicios Generales','Mensajero Interno'),('I','Servicios Generales','Portero'),('I','Servicios Generales','Vigilante'),
('I','Servicios Generales','Jardinero'),('I','Servicios Generales','Ayudante de Mantenimiento'),('I','Servicios Generales','Mensajero Externo'),
('I','Servicios Generales','Chofer I'),('I','Servicios Generales','Chofer II'),('I','Servicios Generales','Ayudante de Plomero'),
('I','Servicios Generales','Operador de Equipo de Bombeo'),('I','Servicios Generales','Recolector de Muestras de Agua Potable'),
('I','Servicios Generales','Lector de Medidores'),('I','Servicios Generales','Operador de Equipo Pesado'),('I','Servicios Generales','Operador de Válvulas'),
('II','Supervisión y Apoyo','Recepcionista'),('II','Supervisión y Apoyo','Secretaria'),('II','Supervisión y Apoyo','Secretaria Ejecutiva'),
('II','Supervisión y Apoyo','Auxiliar Administrativo'),('II','Supervisión y Apoyo','Auxiliar Comercial'),('II','Supervisión y Apoyo','Auxiliar de Servicio al Cliente'),
('II','Supervisión y Apoyo','Auxiliar de Relaciones Públicas'),('II','Supervisión y Apoyo','Auxiliar de Almacén y Suministro'),('II','Supervisión y Apoyo','Auxiliar de Facturación'),
('II','Supervisión y Apoyo','Auxiliar de Catastro'),('II','Supervisión y Apoyo','Auxiliar de Gestión de Cobros'),('II','Supervisión y Apoyo','Auxiliar de Valija'),
('II','Supervisión y Apoyo','Cajero'),('II','Supervisión y Apoyo','Digitador'),('II','Supervisión y Apoyo','Gestor de Cobros'),
('II','Supervisión y Apoyo','Operador de Planta de Tratamiento de Agua Potable'),('II','Supervisión y Apoyo','Operador de Planta de Tratamiento de Aguas Residuales'),
('II','Supervisión y Apoyo','Supervisor General'),('II','Supervisión y Apoyo','Supervisor Comercial'),('II','Supervisión y Apoyo','Supervisor de Redes de Agua Potable'),
('II','Supervisión y Apoyo','Supervisor de Protocolo'),('II','Supervisión y Apoyo','Encargado(a) de Sección de Seguridad'),('II','Supervisión y Apoyo','Encargado(a) de Sección de Mayordomía'),
('III','Técnicos','Plomero I'),('III','Técnicos','Plomero II'),('III','Técnicos','Soldador'),('III','Técnicos','Albañil'),('III','Técnicos','Electricista'),
('III','Técnicos','Operador de Obra de Toma'),('III','Técnicos','Técnico en Electrónica'),('III','Técnicos','Técnico Administrativo'),
('III','Técnicos','Técnico de Tesorería'),('III','Técnicos','Técnico de Nómina'),('III','Técnicos','Técnico de Contabilidad'),
('III','Técnicos','Técnico de Recursos Humanos'),('III','Técnicos','Técnico de Compras y Contrataciones'),('III','Técnicos','Técnico de Archivística'),
('III','Técnicos','Técnico de Laboratorio de Control de Calidad del Agua'),('III','Técnicos','Técnico de Cloración'),('III','Técnicos','Soporte Técnico Informático'),
('III','Técnicos','Programador de Computadoras'),('III','Técnicos','Administrador de Redes'),('III','Técnicos','Monitor de Cámaras'),
('III','Técnicos','Diagramador'),('III','Técnicos','Diseñador Gráfico'),('III','Técnicos','Diseñador de Página Web'),('III','Técnicos','Fotógrafo'),('III','Técnicos','Camarógrafo'),
('III','Técnicos','Coordinador de Incorporaciones de Agua Potable y Saneamiento'),('III','Técnicos','Encargado(a) de Sección de Transportación'),
('III','Técnicos','Encargado(a) de Sección de Almacén y Suministro'),('III','Técnicos','Encargado(a) de Sección de Corte y Reconexión'),
('III','Técnicos','Encargado(a) de Centros de Pagos Externos'),('III','Técnicos','Encargado(a) de Sección de Mantenimiento y Reparación'),('III','Técnicos','Encargado(a) de Sección de Obras de Toma'),
('IV','Gestión Institucional','Analista de Planificación'),('IV','Gestión Institucional','Analista de Desarrollo Institucional'),('IV','Gestión Institucional','Analista de Calidad en la Gestión'),
('IV','Gestión Institucional','Analista de Proyectos'),('IV','Gestión Institucional','Analista de Cooperación Internacional'),('IV','Gestión Institucional','Analista de Datos Estadísticos'),('IV','Gestión Institucional','Analista de Control y Análisis de Operaciones'),
('IV','Gestión del Talento Humano','Analista de Recursos Humanos'),('IV','Gestión del Talento Humano','Analista de Capacitación y Desarrollo'),('IV','Gestión del Talento Humano','Psicólogo Organizacional'),
('IV','Gestión Financiera','Analista Financiero'),('IV','Gestión Financiera','Analista de Presupuesto'),('IV','Gestión Financiera','Analista de Presupuesto de Obras'),('IV','Gestión Financiera','Contador'),
('IV','Tecnología de la Información','Analista de Sistemas Informáticos'),('IV','Tecnología de la Información','Administrador de Base de Datos'),
('IV','Ingeniería','Agrimensor'),('IV','Ingeniería','Supervisor de Obras'),('IV','Ingeniería','Laboratorista de Control de Calidad del Agua'),
('IV','Gestión Social y Desarrollo Sostenible','Analista de Gestión Social'),('IV','Gestión Social y Desarrollo Sostenible','Analista de Gestión Documental'),
('IV','Gestión Social y Desarrollo Sostenible','Analista de Derechos Humanos'),('IV','Gestión Social y Desarrollo Sostenible','Analista de Cohesión Territorial'),
('IV','Gestión Social y Desarrollo Sostenible','Analista de Gestión Integral de Riesgo'),('IV','Gestión Social y Desarrollo Sostenible','Analista de Cambios Climáticos'),('IV','Gestión Social y Desarrollo Sostenible','Analista de Asistencia Social'),
('IV','Comunicación','Periodista'),('IV','Comercial','Administrador(a) de Centros de Servicio al Cliente'),
('V','Secciones','Encargado(a) de Sección de Archivo y Correspondencia'),('V','Secciones','Encargado(a) de Sección de Protocolo y Eventos'),
('V','Secciones','Encargado(a) de Sección de Cooperación Internacional'),('V','Secciones','Encargado(a) de Sección de Redes Sociales y Medios Digitales'),
('V','Secciones','Encargado(a) de Sección de Servicio al Cliente'),('V','Secciones','Encargado(a) de Sección de Registro, Control y Nómina'),
('V','Secciones','Encargado(a) de Sección de Evaluación del Desempeño y Capacitación'),('V','Secciones','Encargado(a) de Sección de Organización del Trabajo y Compensación'),
('V','Secciones','Encargado(a) de Sección de Control de Activos Fijos'),('V','Secciones','Encargado(a) de Sección de Tesorería'),('V','Secciones','Encargado(a) de Sección de Presupuesto'),
('V','Secciones','Encargado(a) de Sección de Gestión de Cobros'),('V','Secciones','Encargado(a) de Sección de Administración de Servicios TIC'),('V','Secciones','Encargado(a) de Sección de Operaciones TIC'),
('V','Secciones','Encargado(a) de Sección de Tratamiento de Agua Potable'),('V','Secciones','Encargado(a) de Sección de Control de Calidad de Agua Potable'),('V','Secciones','Encargado(a) de Sección de Laboratorio'),
('V','Secciones','Encargado(a) de Sección de Mantenimiento de Redes de Agua Potable'),('V','Secciones','Encargado(a) de Sección de Operación y Distribución de Agua Potable'),
('V','Secciones','Encargado(a) de Sección de Catastro de Redes de Agua Potable'),('V','Secciones','Encargado(a) de Sección de Operación y Mantenimiento de Zonas Periféricas'),
('V','Secciones','Encargado(a) de Sección de Electromecánica'),('V','Secciones','Encargado(a) de Sección de Construcciones'),('V','Secciones','Encargado(a) de Sección de Diseño y Presupuesto de Obras'),
('V','Secciones','Encargado(a) de Sección de Fiscalización y Control de Obras'),('V','Secciones','Encargado(a) de Sección de Operación y Mantenimiento de Redes de Aguas Residuales'),
('V','Secciones','Encargado(a) de Sección de Control de Calidad de Aguas Residuales'),('V','Secciones','Encargado(a) de Sección de Tratamiento de Aguas Residuales'),
('V','Secciones','Encargado(a) de Sección de Micromedición'),('V','Secciones','Encargado(a) de Sección de Catastro de Usuarios'),('V','Secciones','Encargado(a) de Sección de Facturación'),
('V','Secciones','Encargado(a) de Sección de Prensa'),('V','Secciones','Encargado(a) de Sección de Planeación y Preparación de Contrataciones'),('V','Secciones','Encargado(a) de Sección de Gestión Contractual'),
('V','Divisiones','Encargado(a) de División de Servicios Generales'),('V','Divisiones','Encargado(a) de División de Relaciones Públicas'),('V','Divisiones','Encargado(a) de División de Participación Social y Ciudadana'),
('V','Departamentos','Encargado(a) del Departamento de Contabilidad'),('V','Departamentos','Encargado(a) del Departamento de Formulación, Monitoreo y Evaluación de Planes, Programas y Proyectos'),
('V','Departamentos','Encargado(a) del Departamento de Desarrollo Institucional y Calidad en la Gestión'),('V','Departamentos','Encargado(a) del Departamento de Gestión Operativa'),
('V','Departamentos','Encargado(a) del Departamento de Gestión Comercial'),('V','Departamentos','Encargado(a) del Departamento de Aguas Residuales y Saneamiento'),
('V','Departamentos','Encargado(a) del Departamento de Producción y Tratamiento de Agua Potable'),('V','Departamentos','Encargado(a) del Departamento de Operación y Mantenimiento de Agua Potable'),
('V','Departamentos','Encargado(a) del Departamento de Ingeniería'),('V','Departamentos','Encargado(a) del Departamento Financiero'),('V','Departamentos','Encargado(a) del Departamento Administrativo'),
('V','Departamentos','Encargado(a) del Departamento de Tecnologías de la Información y Comunicación'),('V','Departamentos','Encargado(a) del Departamento Jurídico'),
('V','Departamentos','Encargado(a) del Departamento de Control y Análisis de Operaciones'),('V','Departamentos','Encargado(a) del Departamento de Contrataciones Públicas'),
('V','Departamentos','Encargado(a) de la Oficina de Acceso a la Información Pública'),
('V','Direcciones','Director(a) de Planificación y Desarrollo'),('V','Direcciones','Director(a) de Comunicaciones'),('V','Direcciones','Director(a) de Recursos Humanos'),
('V','Direcciones','Director(a) Administrativo Financiero'),('V','Direcciones','Director(a) Técnico'),('V','Direcciones','Director(a) Comercial')
on conflict(occupational_group,position_name) do update set family=excluded.family,active=true,updated_at=now();

create or replace function public.list_hr_position_catalog(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_user public.app_users;begin v_user:=public.hr_authenticated_user(p_token);
 if v_user.id is null or (v_user.role<>'Administrador' and not coalesce((v_user.permissions->>'ver_recursos_humanos')::boolean,false)) then return jsonb_build_object('success',false,'error','No posee permiso para consultar el manual de cargos.');end if;
 return jsonb_build_object('success',true,'positions',coalesce((select jsonb_agg(to_jsonb(x) order by x.occupational_group,x.family,x.position_name) from(select id,occupational_group,family,position_name from public.hr_position_catalog where active)x),'[]'::jsonb));end $$;
grant execute on function public.list_hr_position_catalog(text) to anon,authenticated;
