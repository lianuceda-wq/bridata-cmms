import Link from 'next/link'
import { requireTenant } from '@/lib/tenant'
import BudgetForm from './BudgetForm'
import { changeBudgetStatus, createLaborRate } from './actions'
import styles from './analytics.module.css'

function pct(value:unknown){return value===null||value===undefined?'—':`${Number(value).toFixed(1)}%`}
function hours(value:unknown){return value===null||value===undefined?'—':`${Number(value).toFixed(2)} h`}
function money(value:unknown,currency='PEN'){return value===null||value===undefined?'—':new Intl.NumberFormat('es-PE',{style:'currency',currency}).format(Number(value))}
function monthLabel(value:string){return new Intl.DateTimeFormat('es-PE',{timeZone:'UTC',month:'short',year:'numeric'}).format(new Date(value))}

export default async function AnalyticsPage(){
  const {supabase,tenant,role}=await requireTenant()
  const canConfigure=['owner','admin','planner'].includes(role)

  const [
    {data:maintenance},{data:reliability},{data:hydraulic},{data:costs},{data:inventory},{data:purchases},
    {data:definitions},{data:budgets},{data:budgetExecution},{data:rates},{data:sites},{data:assets},{data:members},
  ]=await Promise.all([
    supabase.from('maintenance_kpis_monthly').select('*').eq('tenant_id',tenant.id).order('month',{ascending:false}).limit(12),
    supabase.from('reliability_kpis_monthly').select('*').eq('tenant_id',tenant.id).order('month',{ascending:false}).limit(12),
    supabase.from('hydraulic_kpis_monthly').select('*').eq('tenant_id',tenant.id).order('month',{ascending:false}).limit(12),
    supabase.from('maintenance_cost_kpis_monthly').select('*').eq('tenant_id',tenant.id).order('month',{ascending:false}).limit(24),
    supabase.from('inventory_kpis').select('*').eq('tenant_id',tenant.id).maybeSingle(),
    supabase.from('purchase_kpis').select('*').eq('tenant_id',tenant.id),
    supabase.from('metric_definitions').select('*').eq('is_active',true).order('category').order('name'),
    supabase.from('maintenance_budgets').select('id,code,name,period_start,period_end,currency,status').eq('tenant_id',tenant.id).order('period_start',{ascending:false}).limit(20),
    supabase.from('maintenance_budget_execution').select('*').eq('tenant_id',tenant.id),
    supabase.from('labor_rate_versions').select('id,user_id,labor_role,hourly_rate,currency,valid_from,valid_to,rate_source:is_active').eq('tenant_id',tenant.id).eq('is_active',true).order('valid_from',{ascending:false}).limit(50),
    supabase.from('sites').select('id,code,name').eq('tenant_id',tenant.id).order('name'),
    supabase.from('assets').select('id,code,name,site_id').eq('tenant_id',tenant.id).eq('is_active',true).order('code'),
    supabase.from('tenant_members').select('user_id,role,is_active').eq('tenant_id',tenant.id).eq('is_active',true),
  ])

  const memberIds=(members??[]).map(m=>m.user_id)
  const {data:profiles}=memberIds.length?await supabase.from('profiles').select('id,full_name,email').in('id',memberIds):{data:[]}
  const profileMap=new Map((profiles??[]).map(p=>[p.id,p]))

  const maint=maintenance?.[0]
  const rel=reliability?.[0]
  const hyd=hydraulic?.[0]
  const penCosts=(costs??[]).find(c=>c.currency==='PEN')
  const penPurchases=(purchases??[]).find(p=>p.currency==='PEN')
  const activeBudgetRows=(budgetExecution??[])
  const budgetPen=activeBudgetRows.filter(b=>b.currency==='PEN')
  const budgetAmount=budgetPen.reduce((s,b)=>s+Number(b.budget_amount??0),0)
  const budgetActual=budgetPen.reduce((s,b)=>s+Number(b.actual_amount??0),0)
  const budgetPct=budgetAmount>0?100*budgetActual/budgetAmount:null

  const trends=new Map<string,{month:string;maintenance?:any;reliability?:any;hydraulic?:any;cost?:any}>()
  for(const row of maintenance??[]){const key=String(row.month);trends.set(key,{...(trends.get(key)??{month:key}),maintenance:row})}
  for(const row of reliability??[]){const key=String(row.month);trends.set(key,{...(trends.get(key)??{month:key}),reliability:row})}
  for(const row of hydraulic??[]){const key=String(row.month);trends.set(key,{...(trends.get(key)??{month:key}),hydraulic:row})}
  for(const row of (costs??[]).filter(c=>c.currency==='PEN')){const key=String(row.month);trends.set(key,{...(trends.get(key)??{month:key}),cost:row})}
  const trendRows=[...trends.values()].sort((a,b)=>b.month.localeCompare(a.month)).slice(0,12)

  return <main className="content stack gap-24">
    <section className={styles.hero}>
      <div><span className="badge">Analytics</span><h1>Indicadores de mantenimiento</h1><p className="muted">{tenant.name} · métricas calculadas desde hechos operacionales de BRIDATA.</p></div>
      <div className={styles.heroActions}><Link className="button button-secondary" href="/dashboard/work-orders">Drill-down OT</Link><Link className="button button-secondary" href="/dashboard/failures">Drill-down fallas</Link><Link className="button button-secondary" href="/dashboard/hydraulics">Drill-down hidráulica</Link></div>
    </section>

    <section className={styles.metrics}>
      <div className={styles.metric}><span>Cumplimiento plan</span><strong>{pct(maint?.compliance_percent)}</strong><small>{maint?.executed_planned_orders??0} / {maint?.planned_orders??0} OT</small><Link href="/dashboard/work-orders">Ver órdenes →</Link></div>
      <div className={styles.metric}><span>Dentro de programa</span><strong>{pct(maint?.on_time_percent)}</strong><small>{maint?.late_planned_orders??0} fuera de fecha</small><Link href="/dashboard/work-orders">Trazar →</Link></div>
      <div className={styles.metric}><span>MTTR</span><strong>{hours(rel?.mttr_hours)}</strong><small>{rel?.failure_count??0} fallas del mes</small><Link href="/dashboard/failures">Ver fallas →</Link></div>
      <div className={styles.metric}><span>Cumplimiento hidráulico</span><strong>{pct(hyd?.compliance_percent)}</strong><small>{hyd?.out_of_range_readings??0} fuera de rango</small><Link href="/dashboard/hydraulics">Ver lecturas →</Link></div>
      <div className={styles.metric}><span>Costo mantenimiento</span><strong>{money(penCosts?.total_cost,'PEN')}</strong><small>{penCosts?.missing_valuations??0} costos sin valorar</small></div>
      <div className={styles.metric}><span>Stock bajo mínimo</span><strong>{inventory?.below_minimum_count??0}</strong><small>{inventory?.reorder_count??0} en reorden</small><Link href="/dashboard/inventory">Ver inventario →</Link></div>
      <div className={styles.metric}><span>Compras por llegar</span><strong>{money(penPurchases?.pending_amount,'PEN')}</strong><small>{penPurchases?.open_purchase_orders??0} OC abiertas</small><Link href="/dashboard/inventory">Ver compras →</Link></div>
      <div className={styles.metric}><span>Ejecución presupuesto</span><strong>{pct(budgetPct)}</strong><small>{money(budgetActual,'PEN')} / {money(budgetAmount,'PEN')}</small></div>
      <div className={styles.metric}><span>Correctivos</span><strong>{maint?.corrective_orders??0}</strong><small>Preventivos {maint?.preventive_orders??0}</small></div>
      <div className={styles.metric}><span>OT vencidas</span><strong className={Number(maint?.overdue_planned_orders??0)>0?styles.bad:styles.good}>{maint?.overdue_planned_orders??0}</strong><small>Planificadas no completadas</small></div>
    </section>

    <section className="card table-card">
      <div className="section-heading"><div><strong>Tendencia mensual</strong><p className="muted small">Mismas vistas analíticas que podrá consumir Power BI.</p></div></div>
      {trendRows.length===0?<div className="empty-state"><span className="muted">Todavía no hay histórico suficiente.</span></div>:<div className="table-wrap"><table className={styles.trendTable}><thead><tr><th>Mes</th><th>Cumplimiento</th><th>Dentro programa</th><th>Fallas</th><th>MTTR</th><th>Hidráulico</th><th>Costo PEN</th></tr></thead><tbody>{trendRows.map(row=><tr key={row.month}><td>{monthLabel(row.month)}</td><td>{pct(row.maintenance?.compliance_percent)}</td><td>{pct(row.maintenance?.on_time_percent)}</td><td>{row.reliability?.failure_count??0}</td><td>{hours(row.reliability?.mttr_hours)}</td><td>{pct(row.hydraulic?.compliance_percent)}</td><td>{money(row.cost?.total_cost,'PEN')}</td></tr>)}</tbody></table></div>}
    </section>

    {canConfigure&&<section className={styles.grid2}>
      <form action={createLaborRate} className="card stack">
        <div><strong>Tarifas de mano de obra</strong><p className="muted small">Prioridad: usuario específico → función → tarifa general. Cada sesión guarda snapshot histórico.</p></div>
        <select className="input" name="user_id" defaultValue=""><option value="">Tarifa no específica por usuario</option>{(members??[]).map(member=>{const p=profileMap.get(member.user_id);return <option key={member.user_id} value={member.user_id}>{p?.full_name||p?.email||member.user_id} · {member.role}</option>})}</select>
        <input className="input" name="labor_role" placeholder="Función opcional: técnico, soldador..."/>
        <div className="form-grid"><input className="input" name="hourly_rate" type="number" min="0" step="any" placeholder="Tarifa / hora" required/><input className="input" name="currency" defaultValue="PEN" maxLength={3}/></div>
        <label className={styles.label}>Vigente desde<input className="input" name="valid_from" type="date" defaultValue={new Date().toISOString().slice(0,10)} required/></label>
        <input className="input" name="notes" placeholder="Nota / fuente de tarifa"/>
        <button className="button" type="submit">Crear nueva versión</button>
        <div className={styles.rateList}>{(rates??[]).slice(0,8).map(rate=>{const p=rate.user_id?profileMap.get(rate.user_id):null;return <div className={styles.rate} key={rate.id}><div><strong>{p?.full_name||p?.email||rate.labor_role||'General'}</strong><span>Desde {rate.valid_from}{rate.valid_to?` hasta ${rate.valid_to}`:''}</span></div><b>{money(rate.hourly_rate,rate.currency)}/h</b></div>})}</div>
      </form>
      <BudgetForm sites={sites??[]} assets={assets??[]}/>
    </section>}

    <section className="card table-card">
      <div className="section-heading"><div><strong>Presupuestos</strong><p className="muted small">Solo presupuestos aprobados/cerrados alimentan ejecución presupuestal.</p></div></div>
      {(budgets??[]).length===0?<div className="empty-state"><span className="muted">Sin presupuestos.</span></div>:<div className="table-wrap"><table><thead><tr><th>Presupuesto</th><th>Periodo</th><th>Estado</th><th>Moneda</th><th>Presupuestado</th><th>Ejecutado</th><th>%</th><th>Acción</th></tr></thead><tbody>{(budgets??[]).map(budget=>{const rows=activeBudgetRows.filter(r=>r.budget_id===budget.id);const budgetTotal=rows.reduce((s,r)=>s+Number(r.budget_amount??0),0);const actualTotal=rows.reduce((s,r)=>s+Number(r.actual_amount??0),0);const execution=budgetTotal?100*actualTotal/budgetTotal:null;return <tr key={budget.id}><td><strong>{budget.code}</strong><div className="muted small">{budget.name}</div></td><td>{budget.period_start} → {budget.period_end}</td><td><span className={styles.budgetState}>{budget.status}</span></td><td>{budget.currency}</td><td>{rows.length?money(budgetTotal,budget.currency):budget.status==='draft'?'Pendiente aprobación':'—'}</td><td>{rows.length?money(actualTotal,budget.currency):'—'}</td><td>{pct(execution)}</td><td>{canConfigure&&budget.status==='draft'?<form action={changeBudgetStatus}><input type="hidden" name="budget_id" value={budget.id}/><input type="hidden" name="status" value="approved"/><button className="button button-secondary button-compact" type="submit">Aprobar</button></form>:canConfigure&&budget.status==='approved'?<form action={changeBudgetStatus}><input type="hidden" name="budget_id" value={budget.id}/><input type="hidden" name="status" value="closed"/><button className="button button-secondary button-compact" type="submit">Cerrar</button></form>:<span className="muted">—</span>}</td></tr>})}</tbody></table></div>}
    </section>

    <section className="card stack">
      <div><strong>Catálogo y trazabilidad de KPIs</strong><p className="muted small">El catálogo documenta la regla. Los valores no se almacenan aquí; se calculan desde las vistas fuente.</p></div>
      <div className={styles.catalog}>{(definitions??[]).map(def=><article className={styles.metricDef} key={def.code}><header><strong>{def.name}</strong><code>{def.code}</code></header><span className={styles.formula}>{def.formula_description}</span><span className={styles.source}>{def.source_view} · {def.freshness}</span>{def.description&&<span className="muted small">{def.description}</span>}{def.drilldown_route&&<Link href={def.drilldown_route}>Drill-down →</Link>}</article>)}</div>
    </section>
  </main>
}
