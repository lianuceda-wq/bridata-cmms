# Bridata CMMS

SaaS multi-tenant para gestión de mantenimiento de activos.

## Estado
Starter técnico inicial: Next.js + Supabase + autenticación + esquema PostgreSQL multi-tenant + RLS.

## Requisitos
- Node.js LTS
- npm
- Cuenta Supabase
- Git

## 1. Instalar
```bash
npm install
```

## 2. Configurar Supabase
Copia:
```bash
cp .env.example .env.local
```

Completa:
```env
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=...
```

## 3. Crear esquema
Ejecuta el SQL de:

`supabase/migrations/0001_initial.sql`

en el SQL Editor de Supabase o mediante Supabase CLI.

## 4. Ejecutar
```bash
npm run dev
```

Abrir `http://localhost:3000`.

## Módulos planificados
- Dashboard
- Activos
- Planes de mantenimiento
- Programación
- Órdenes de trabajo
- Inspecciones
- Técnicos
- Inventario
- Herramientas / EPP
- Costos
- Proveedores
- Documentos
- Reportes / KPIs
- Integraciones
- Administración SaaS

## Seguridad
El starter activa Row Level Security en las tablas operacionales y usa membresías por tenant. Antes de producción se deben agregar políticas específicas por rol para escritura, auditoría reforzada, rate limiting, pruebas de aislamiento y gestión segura de funciones administrativas.
