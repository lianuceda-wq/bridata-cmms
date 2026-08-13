# Arquitectura — Bridata CMMS

## Objetivo
SaaS multi-tenant para mantenimiento de activos inspirado en patrones de CMMS/GMAO modernos.

## Stack inicial
- Next.js + React + TypeScript
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- Supabase Realtime
- Supabase Edge Functions (fase siguiente)
- PostgreSQL Row Level Security para aislamiento multiempresa

## Dominios principales
1. Tenants y membresías
2. Sitios / fundos / plantas
3. Activos jerárquicos
4. Planes de mantenimiento
5. Órdenes de trabajo
6. Técnicos y cuadrillas
7. Inventario y almacenes
8. Costos
9. Inspecciones y evidencias
10. KPIs y analítica
11. Integraciones
12. Administración SaaS

## Principio de seguridad
Toda entidad operacional debe quedar asociada a `tenant_id`. El acceso se valida en PostgreSQL mediante RLS; nunca se confía únicamente en filtros del frontend.
