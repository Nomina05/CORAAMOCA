# CORAAMOCA Gestión Institucional

Sistema web institucional para proyectos, cubicaciones, presupuesto, expedientes, recursos humanos, reportes, usuarios y auditoría.

## Ambientes

- Desarrollo local: use `.env.local` tomando como guía `.env.development.example`.
- Pruebas y Preview de Vercel: configure un proyecto Supabase exclusivo de pruebas.
- Producción: configure variables únicamente en el ambiente Production de Vercel usando `.env.production.example`.
- Nunca reutilice la base de producción en pruebas ni confirme archivos `.env` con credenciales.

## Validación antes de publicar

```bash
npm ci
npm run validate
```

GitHub Actions ejecuta automáticamente lint, TypeScript, pruebas de reglas institucionales y compilación. Vercel debe desplegar producción únicamente desde `main` después de que la validación finalice correctamente.

## Variables protegidas de GitHub

Configure en Settings → Secrets and variables → Actions:

- `TEST_SUPABASE_URL`
- `TEST_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_DB_URL`

## Copias de seguridad

El flujo `Copia de seguridad Supabase` genera diariamente un archivo `pg_dump` y lo conserva como artefacto privado durante 14 días. También puede ejecutarse manualmente desde GitHub Actions. Verifique periódicamente la restauración en el ambiente de pruebas; un respaldo sin prueba de restauración no debe considerarse validado.

## Migraciones automáticas

El flujo `Aplicar migraciones Supabase` se ejecuta al publicar cambios SQL en `main`. Requiere el secreto protegido `SUPABASE_DB_URL` y aplica las migraciones institucionales en orden, deteniéndose ante cualquier error. Al finalizar verifica la existencia de las tablas principales.

## Migraciones más recientes

Ejecute en Supabase SQL Editor, respetando el orden:

1. `supabase/complete_audit.sql`
2. `supabase/institutional_notifications.sql`
3. `supabase/technical_operations.sql`
4. `supabase/integrated_module_persistence.sql`
5. `supabase/system_module_integration.sql`

## Estado técnico

`/api/system/status` informa ambiente, versión, despliegue, disponibilidad de Supabase y tiempo de respuesta. Los errores de pantalla se presentan mediante una interfaz controlada y se envían al registro técnico cuando la migración correspondiente está activa.
