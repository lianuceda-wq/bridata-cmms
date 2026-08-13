# BRIDATA Reports & Analytics API

## Principio

BRIDATA mantiene una sola definición de cada KPI. Dashboard, exportación CSV y API externa consumen las mismas vistas SQL tenant-scoped.

## Reportes disponibles

- `maintenance`
- `reliability`
- `hydraulics`
- `costs`
- `inventory`
- `purchases`
- `budget`
- `inspections`
- `attendance`
- `work_orders`

## Endpoint externo

`GET /api/analytics/{report}`

Parámetros opcionales:

- `from=YYYY-MM-DD`
- `to=YYYY-MM-DD`
- `limit=1..5000`

Autenticación:

`Authorization: Bearer brd_live_...`

La API key se genera desde **Reportes → Claves de analítica**. El secreto se muestra una sola vez. PostgreSQL conserva únicamente SHA-256, scopes, expiración, revocación, último uso y límite horario.

## Power Query / Power BI

```powerquery
let
    BaseUrl = "https://TU_DOMINIO/api/analytics/maintenance?from=2026-01-01&to=2026-12-31",
    Response = Json.Document(
        Web.Contents(
            BaseUrl,
            [Headers=[Authorization="Bearer TU_CLAVE_BRIDATA"]]
        )
    ),
    Rows = Response[rows],
    Result = Table.FromRecords(Rows)
in
    Result
```

La clave debe almacenarse como credencial/parámetro seguro del dataset y no incrustarse en archivos compartidos.

## Exportación interna

Usuarios autenticados pueden consultar:

`GET /api/reports/{report}?from=YYYY-MM-DD&to=YYYY-MM-DD`

CSV Excel-friendly:

`GET /api/reports/{report}/export?from=YYYY-MM-DD&to=YYYY-MM-DD`

El CSV usa UTF-8 BOM y `;` como separador.

## Seguridad

- la API key está asociada a un solo tenant;
- cada clave define su lista explícita de reportes;
- expiración y revocación son opcionales/administrables;
- el límite horario se valida de forma transaccional;
- el gateway SQL selecciona únicamente vistas predefinidas;
- no existe SQL dinámico proporcionado por el consumidor;
- `service_role` no se expone ni es requerido por el endpoint Next.js;
- las solicitudes quedan registradas en `analytics_api_requests`.
