# Validación de la fundación multi-tenant

## Aplicado en Supabase

Migraciones activas:

1. `initial`
2. `assets_locations_roles`
3. `security_function_hardening`
4. `performance_rls_indexes`

## Seguridad validada

- Todas las tablas públicas del núcleo tienen RLS habilitado.
- Un usuario de Tenant A ve únicamente su tenant, sus activos y su membresía.
- `can_manage_tenant()` devuelve falso para un tenant ajeno.
- Un intento de `INSERT` de un usuario del Tenant A sobre un activo del Tenant B es bloqueado.
- El test se ejecutó dentro de una transacción y terminó con `ROLLBACK`.

## Onboarding validado

Flujo probado transaccionalmente:

`auth user → bootstrap_tenant() → owner membership → site → location → asset`

Resultado esperado y obtenido: 1 tenant, 1 sede, 1 ubicación, 1 activo y rol `owner` visibles para el usuario de prueba.

## Aplicación

GitHub Actions ejecuta:

```bash
npm install
npm run typecheck
npm run build
```

La primera ejecución falló únicamente por intentar usar caché npm sin `package-lock.json`. El workflow fue corregido y la segunda ejecución completó correctamente TypeScript y build.
