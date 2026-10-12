# Informe de auditoría técnica del sistema CORAAMOCA

Fecha: 12 de octubre de 2026  
Alcance: aplicación Next.js, APIs, autenticación, permisos, migraciones Supabase, respaldo, pruebas, dependencias y automatización GitHub/Vercel.

## Resumen ejecutivo

La aplicación compila y sus datos institucionales se conservan en Supabase. Las operaciones sensibles se ejecutan mediante funciones SQL con sesión, permisos y auditoría. Durante la revisión se identificaron y corrigieron cuatro incidencias relevantes: autorregistro público heredado, exposición anónima del estado técnico, migración automática incompleta para recuperación desde cero y dependencias de producción vulnerables.

Resultado posterior a las correcciones:

- Dependencias de producción: 0 vulnerabilidades conocidas.
- Migración completa de Supabase: satisfactoria.
- Respaldo cifrado de Supabase: operativo y programado.
- Pruebas automáticas: 20 reglas funcionales y de seguridad.
- Compilación, TypeScript y lint: incluidos como controles obligatorios de publicación.

## Incidencias corregidas

### SEC-01 — Autorregistro público heredado — Crítica

La ruta `/api/auth/register` permitía invocar `register_app_user` sin una sesión administrativa. Esto contradecía la regla institucional que exige crear usuarios desde Usuarios y Roles y vincularlos a empleados activos.

Corrección:

- La ruta ahora devuelve `403` y no crea cuentas.
- Se revocó en PostgreSQL la ejecución de `register_app_user` para `public`, `anon` y `authenticated`.
- La creación válida permanece en `admin_create_employee_user`, protegida por sesión y rol Administrador.
- Se agregó una prueba automática para impedir regresiones.

### SEC-02 — Dependencias vulnerables — Crítica/Alta

La auditoría inicial encontró 15 vulnerabilidades: 1 crítica, 12 altas, 1 moderada y 1 baja. Next.js 16.2.6 concentraba la incidencia crítica y varias altas.

Corrección:

- Next.js y `eslint-config-next` se actualizaron a 16.4.0.
- Se regeneró `package-lock.json`.
- La auditoría de dependencias de producción reporta 0 vulnerabilidades.
- Cada push ejecutará `npm audit --omit=dev --audit-level=high` y bloqueará la publicación si reaparece una vulnerabilidad alta o crítica en producción.

### SEC-03 — Estado técnico accesible sin sesión — Alta

`/api/system/status` informaba ambiente, versión, despliegue y disponibilidad de base de datos sin verificar sesión.

Corrección:

- La ruta exige cookie de sesión válida.
- Las solicitudes anónimas o con sesión vencida reciben `401`.
- Se agregó una prueba automática de protección.

### OPS-01 — Migración incompleta para recuperación — Alta

El flujo automático aplicaba ampliaciones sobre la base existente, pero omitía scripts base. Una instalación limpia o recuperación por desastre podía fallar.

Corrección:

- Se incorporaron `username_auth.sql`, `technical_projects.sql`, `cubicaciones_workflow.sql`, `project_digital_file.sql` y `personal_dashboard.sql` en el orden de migración.
- Se declaró explícitamente `must_change_password` en la migración de seguridad.
- La secuencia completa fue ejecutada satisfactoriamente contra Supabase.

### APP-01 — Efectos React con datos potencialmente obsoletos — Media

Nómina, viáticos y jerarquía organizacional utilizaban funciones recreadas fuera de las dependencias de sus efectos y memorias.

Corrección:

- Se estabilizaron las funciones mediante `useCallback`.
- Se corrigieron las dependencias de `useEffect` y `useMemo`.
- Se eliminó código no utilizado del informe de inversión pública.

## Controles verificados

- Todas las rutas funcionales, excepto inicio de sesión, requieren cookie de sesión.
- Las tablas sensibles principales tienen RLS habilitado y acceso directo revocado para `anon` y `authenticated`.
- Los cambios de pago y avance físico se validan nuevamente en PostgreSQL, no solo en la interfaz.
- Las sesiones se almacenan mediante hash y vencen después de 12 horas.
- Existe bloqueo temporal después de cinco intentos fallidos para usuarios conocidos.
- Suspender un usuario elimina sus sesiones activas.
- Restablecer una contraseña elimina sesiones y obliga cambio en el próximo acceso.
- Los pagos de cubicaciones recalculan retención, pago neto, proyecto, presupuesto, panel y reportes.
- El respaldo diario se genera con PostgreSQL 17, se cifra antes de almacenarse y se retiene 14 días.
- No se encontraron claves secretas de Supabase ni contraseñas incrustadas en el repositorio.

## Riesgos residuales y mejoras recomendadas

### Prioridad alta

1. Activar Dependabot y CodeQL en la configuración de GitHub. Las APIs informaron que Dependabot está deshabilitado y que no existe análisis CodeQL.
2. Implementar limitación de intentos por IP o dispositivo para nombres de usuario inexistentes. El bloqueo actual protege cuentas conocidas, pero no limita tráfico distribuido hacia el endpoint de acceso.
3. Realizar una restauración de prueba trimestral. El respaldo está verificado, pero una copia solo debe considerarse confiable después de demostrar su restauración en un ambiente aislado.
4. Utilizar un secreto de cifrado exclusivo para respaldos. Actualmente el archivo se cifra con la credencial de base; separar ambos secretos mejora la rotación y reduce impacto ante compromiso.

### Prioridad media

1. Incorporar pruebas end-to-end con navegador para login, permisos, cubicaciones, pagos, reportes, nómina y acciones de personal.
2. Añadir pruebas SQL de concurrencia para secuencias, pagos simultáneos, cierres presupuestarios y cambios de permisos durante una sesión.
3. Crear un ambiente Supabase exclusivo de pruebas. La validación de compilación ya acepta secretos de prueba, pero debe evitar que las pruebas integrales escriban en producción.
4. Revisar si el repositorio debe continuar público. Aunque no contiene secretos, incluye estructura interna, SQL institucional y reglas operativas.
5. Definir una política formal de conservación para auditorías, documentos y datos de empleados.

### Prioridad baja

1. Sustituir etiquetas `<img>` por `next/image` donde resulte conveniente para optimizar carga.
2. Corregir las advertencias restantes de hooks en el componente principal mediante una separación gradual en módulos más pequeños.
3. Dividir `app/page.tsx`, que concentra múltiples módulos, para mejorar mantenibilidad y pruebas aisladas.
4. Actualizar las acciones de GitHub cuando existan versiones nativas para Node.js 24; actualmente GitHub muestra una advertencia de compatibilidad futura, no un fallo.

## Riesgo residual de herramientas de desarrollo

`npm audit` mantiene cinco alertas altas en la cadena `eslint-config-next` → `@next/eslint-plugin-next` → `fast-glob` → `micromatch` → `braces`. No forman parte del paquete desplegado en producción y npm no ofrece una corrección compatible sin degradar a una versión antigua de Next.js. El flujo las informa, pero no bloquea la publicación; la auditoría de dependencias de producción sí es obligatoria.

## Conclusión

El sistema queda en condición operativa, con las incidencias críticas identificadas corregidas y controles automáticos fortalecidos. El siguiente ciclo recomendado debe priorizar CodeQL/Dependabot, restauraciones periódicas comprobadas y pruebas end-to-end de permisos y procesos financieros.
