# Bridata CMMS

SaaS multi-tenant para gestión de mantenimiento de activos.

## Estado
Fundación técnica validada: Next.js + Supabase + autenticación + PostgreSQL multi-tenant + RLS + jerarquía Fundo/Sede → Ubicación → Activo.

## Validación realizada
- TypeScript: PASS
- Next.js build: PASS
- RLS multi-tenant: PASS
- Bloqueo de escritura cross-tenant: PASS
- Onboarding `bootstrap_tenant`: PASS
- Creación controlada sede → ubicación → activo: PASS

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
Las migraciones viven en `supabase/migrations/` y deben aplicarse en orden.

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
La aplicación usa Row Level Security como barrera principal de aislamiento por tenant. Las funciones `SECURITY DEFINER` están endurecidas, el acceso anónimo fue revocado y las políticas operacionales distinguen roles de administración, planificación, supervisión, técnico y lectura.
