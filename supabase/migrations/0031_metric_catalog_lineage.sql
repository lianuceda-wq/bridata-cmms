-- Bridata CMMS - catálogo de métricas, no almacena resultados

create table public.metric_definitions (
  code text primary key,
  name text not null,
  category text not null,
  unit text,
  freshness text not null check(freshness in ('realtime','near_realtime','scheduled')),
  source_view text not null,
  formula_description text not null,
  drilldown_route text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.metric_definitions(code,name,category,unit,freshness,source_view,formula_description,drilldown_route,description) values
('maintenance_compliance','Cumplimiento del plan','planificacion','%','near_realtime','maintenance_kpis_monthly','OT planificadas ejecutadas / OT planificadas × 100','/dashboard/work-orders','Cumplimiento de órdenes originadas por planes de mantenimiento.'),
('maintenance_on_time','Cumplimiento dentro de programa','planificacion','%','near_realtime','maintenance_kpis_monthly','OT planificadas completadas antes o en due_at / OT planificadas × 100','/dashboard/work-orders','Distingue ejecución dentro y fuera de la fecha objetivo.'),
('failure_count','Cantidad de fallas','confiabilidad','eventos','realtime','reliability_kpis_monthly','Conteo de failure_events no cancelados','/dashboard/failures','Cada fila puede rastrearse hasta el evento y su OT.'),
('mttr','MTTR','confiabilidad','h','near_realtime','reliability_kpis_monthly','Promedio(restored_at - repair_started_at)','/dashboard/failures','Tiempo medio efectivo de reparación; no equivale a horas-hombre.'),
('mtbf','MTBF por activo','confiabilidad','h','near_realtime','asset_reliability_metrics','Promedio(siguiente occurred_at - previous restored_at)','/dashboard/failures','Tiempo operativo entre restauración y siguiente falla.'),
('hydraulic_compliance','Cumplimiento hidráulico','riego','%','near_realtime','hydraulic_kpis_monthly','Lecturas evaluadas dentro de min/max / lecturas evaluadas × 100','/dashboard/hydraulics','Usa snapshots históricos de nominales y límites configurables.'),
('inventory_below_minimum','SKU bajo mínimo','inventario','SKU','realtime','inventory_kpis','Conteo de combinaciones almacén-material con disponible < mínimo','/dashboard/inventory','El saldo deriva del ledger de movimientos.'),
('purchase_pending','Compras por llegar','compras','moneda','realtime','purchase_kpis','Σ (cantidad ordenada - cantidad recibida) × precio unitario','/dashboard/inventory','Separado por moneda.'),
('maintenance_cost','Costo de mantenimiento','costos','moneda','near_realtime','maintenance_cost_kpis_monthly','Σ cost_entries valorizados','/dashboard/analytics','Incluye material, HH valorizadas, servicios y contratistas.'),
('budget_execution','Ejecución presupuestal','costos','%','near_realtime','maintenance_budget_execution','Costo real del alcance / presupuesto del alcance × 100','/dashboard/analytics','Trazable por periodo, sitio, activo, tipo de mantenimiento y categoría.'),
('labor_hours','Horas-hombre','mano_obra','HH','realtime','work_order_labor_metrics','Σ (ended_at - started_at) por sesión de trabajador','/dashboard/work-orders','Se mantiene separado del MTTR.')
on conflict(code) do update set
  name=excluded.name,category=excluded.category,unit=excluded.unit,freshness=excluded.freshness,
  source_view=excluded.source_view,formula_description=excluded.formula_description,
  drilldown_route=excluded.drilldown_route,description=excluded.description,is_active=true,updated_at=now();

alter table public.metric_definitions enable row level security;
create policy metric_definitions_select on public.metric_definitions for select to authenticated using(is_active=true);
grant select on public.metric_definitions to authenticated;
revoke insert,update,delete on public.metric_definitions from authenticated;

create trigger metric_definitions_updated_at before update on public.metric_definitions for each row execute function public.set_updated_at();
